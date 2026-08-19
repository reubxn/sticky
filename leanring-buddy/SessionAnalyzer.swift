//
//  SessionAnalyzer.swift
//  leanring-buddy
//
//  Sends a teach session (transcript + frame timeline) to the selected AI model and parses
//  the returned JSON into a TeachSessionResult. No raw HTTP — uses the
//  existing provider client.
//

import Foundation

enum SessionAnalyzerError: Error, LocalizedError {
    case noJSONFoundInResponse(rawResponse: String)
    case jsonDecodeFailed(underlying: Error, rawJSON: String)

    var errorDescription: String? {
        switch self {
        case .noJSONFoundInResponse:
            return "The AI model didn't return parseable JSON for the teach session."
        case .jsonDecodeFailed(let underlying, _):
            return "Couldn't decode teach session JSON: \(underlying.localizedDescription)"
        }
    }
}

/// Bundles the analyzer output with the frame data it referenced. The review
/// UI needs the original frames to render thumbnails next to each ambiguous
/// moment's question, so we hand them back instead of letting them fall out
/// of scope as soon as the model call finishes.
struct TeachSessionAnalysis {
    let result: TeachSessionResult
    /// The frames actually sent to the model, in the order it saw them.
    /// `AmbiguousMoment.frameIndex` indexes into this array.
    let selectedFrames: [(data: Data, timestamp: TimeInterval)]
}

enum SessionAnalyzer {
    /// Maximum number of frames sent to Claude. Keeps the request small enough
    /// to be fast and cheap. Frames are picked evenly across the session.
    private static let maxFramesPerSession = 10

    /// Analyzes a finished teach session. Picks up to 10 evenly-spaced frames,
    /// sends them to the selected model with the taste-extraction system prompt, and parses
    /// the streamed reply into a TeachSessionResult. Returns the parsed result
    /// alongside the frame timeline the analyzer actually used, so the review
    /// UI can render thumbnails for each ambiguous moment by frame index.
    ///
    /// Throws if the model returns nothing parseable. Caller should log + recover.
    static func analyzeTeachSession(
        transcript: String,
        frames: [(data: Data, timestamp: TimeInterval)],
        api: any StreamingVisionLanguageModelAPI
    ) async throws -> TeachSessionAnalysis {
        let selectedFrames = pickEvenlySpacedFrames(frames, maxCount: maxFramesPerSession)

        let labeledImages: [(data: Data, label: String)] = selectedFrames.enumerated().map { (frameIndex, frame) in
            let label = "Frame \(frameIndex) — t = \(String(format: "%.1f", frame.timestamp))s"
            return (data: frame.data, label: label)
        }

        let frameTimestamps = selectedFrames.map { $0.timestamp }

        let (responseText, _) = try await api.analyzeImageStreaming(
            images: labeledImages,
            systemPrompt: TasteExtractionPrompt.systemPrompt(),
            conversationHistory: [],
            userPrompt: TasteExtractionPrompt.userPrompt(
                transcript: transcript,
                frameTimestamps: frameTimestamps
            ),
            onTextChunk: { _ in
                // No streaming UI for teach analysis — we wait for the full
                // response and parse it as JSON in one shot.
            }
        )

        guard let jsonString = extractFirstJSONObject(from: responseText) else {
            throw SessionAnalyzerError.noJSONFoundInResponse(rawResponse: responseText)
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw SessionAnalyzerError.jsonDecodeFailed(
                underlying: NSError(domain: "SessionAnalyzer", code: -1),
                rawJSON: jsonString
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return parseISO8601Date(dateString) ?? Date()
        }

        do {
            let parsedResult = try decoder.decode(TeachSessionResult.self, from: jsonData)
            return TeachSessionAnalysis(result: parsedResult, selectedFrames: selectedFrames)
        } catch {
            throw SessionAnalyzerError.jsonDecodeFailed(underlying: error, rawJSON: jsonString)
        }
    }

    // MARK: - Frame selection

    /// Picks up to `maxCount` frames spread evenly across the input. Returns
    /// the input as-is if it's already at or below `maxCount`.
    private static func pickEvenlySpacedFrames(
        _ frames: [(data: Data, timestamp: TimeInterval)],
        maxCount: Int
    ) -> [(data: Data, timestamp: TimeInterval)] {
        guard frames.count > maxCount else { return frames }
        guard maxCount > 0 else { return [] }

        if maxCount == 1 {
            return [frames[frames.count / 2]]
        }

        var selectedFrames: [(data: Data, timestamp: TimeInterval)] = []
        let step = Double(frames.count - 1) / Double(maxCount - 1)
        for stepIndex in 0..<maxCount {
            let frameIndex = min(Int(round(Double(stepIndex) * step)), frames.count - 1)
            selectedFrames.append(frames[frameIndex])
        }
        return selectedFrames
    }

    // MARK: - JSON extraction

    /// Walks the response looking for the first balanced top-level JSON object.
    /// Models sometimes wrap replies in markdown fences or prose — this
    /// finds the actual `{...}` payload regardless. Handles strings and
    /// escapes so braces inside strings don't confuse the depth tracker.
    private static func extractFirstJSONObject(from text: String) -> String? {
        guard let firstOpenBraceIndex = text.firstIndex(of: "{") else { return nil }

        var braceDepth = 0
        var insideStringLiteral = false
        var nextCharacterIsEscaped = false

        var currentIndex = firstOpenBraceIndex
        while currentIndex < text.endIndex {
            let currentCharacter = text[currentIndex]

            if nextCharacterIsEscaped {
                nextCharacterIsEscaped = false
            } else if insideStringLiteral {
                if currentCharacter == "\\" {
                    nextCharacterIsEscaped = true
                } else if currentCharacter == "\"" {
                    insideStringLiteral = false
                }
            } else {
                if currentCharacter == "\"" {
                    insideStringLiteral = true
                } else if currentCharacter == "{" {
                    braceDepth += 1
                } else if currentCharacter == "}" {
                    braceDepth -= 1
                    if braceDepth == 0 {
                        return String(text[firstOpenBraceIndex...currentIndex])
                    }
                }
            }

            currentIndex = text.index(after: currentIndex)
        }

        return nil
    }

    /// Parses ISO8601 strings with or without fractional seconds, falling back
    /// to nil. We use this in a custom dateDecodingStrategy because Foundation's
    /// built-in `.iso8601` is strict about the fractional-seconds flag.
    private static func parseISO8601Date(_ dateString: String) -> Date? {
        let withFractionalFormatter = ISO8601DateFormatter()
        withFractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalFormatter.date(from: dateString) {
            return date
        }

        let withoutFractionalFormatter = ISO8601DateFormatter()
        withoutFractionalFormatter.formatOptions = [.withInternetDateTime]
        return withoutFractionalFormatter.date(from: dateString)
    }
}
