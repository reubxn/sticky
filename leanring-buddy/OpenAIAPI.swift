//
//  OpenAIAPI.swift
//  OpenAI API Implementation with streaming support
//

import Foundation

final class OpenAIAPI: StreamingVisionLanguageModelAPI {
    private static let tlsWarmupLock = NSLock()
    private static var hasStartedTLSWarmup = false

    private let apiURL: URL
    var model: String
    private let session: URLSession

    init(proxyURL: String, model: String = "gpt-5.2-2025-12-11") {
        self.apiURL = URL(string: proxyURL)!
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)

        warmUpTLSConnectionIfNeeded()
    }

    private func makeAPIRequest() -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func warmUpTLSConnectionIfNeeded() {
        Self.tlsWarmupLock.lock()
        let shouldStartTLSWarmup = !Self.hasStartedTLSWarmup
        if shouldStartTLSWarmup {
            Self.hasStartedTLSWarmup = true
        }
        Self.tlsWarmupLock.unlock()

        guard shouldStartTLSWarmup,
              var warmupURLComponents = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            return
        }

        warmupURLComponents.path = "/"
        warmupURLComponents.query = nil
        warmupURLComponents.fragment = nil
        guard let warmupURL = warmupURLComponents.url else { return }

        var warmupRequest = URLRequest(url: warmupURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in }.resume()
    }

    private func detectImageMediaType(for imageData: Data) -> String {
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            if [UInt8](imageData.prefix(4)) == pngSignature {
                return "image/png"
            }
        }
        return "image/jpeg"
    }

    private func requestBody(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        stream: Bool,
        maximumCompletionTokens: Int
    ) throws -> Data {
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append(["type": "text", "text": image.label])
            contentBlocks.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(detectImageMediaType(for: image.data));base64,\(image.data.base64EncodedString())"
                ]
            ])
        }
        contentBlocks.append(["type": "text", "text": userPrompt])
        messages.append(["role": "user", "content": contentBlocks])

        return try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_completion_tokens": maximumCompletionTokens,
            "stream": stream,
            "messages": messages
        ])
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()
        var request = makeAPIRequest()
        let bodyData = try requestBody(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            stream: true,
            maximumCompletionTokens: 1_024
        )
        request.httpBody = bodyData

        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 OpenAI streaming request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        let (byteStream, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenAIAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            throw NSError(
                domain: "OpenAIAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBodyChunks.joined(separator: "\n"))"
                ]
            )
        }

        var accumulatedResponseText = ""
        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }
            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = eventPayload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let textChunk = delta["content"] as? String else {
                continue
            }

            accumulatedResponseText += textChunk
            await onTextChunk(accumulatedResponseText)
        }

        return (
            text: accumulatedResponseText,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    func analyzeImage(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()
        var request = makeAPIRequest()
        request.httpBody = try requestBody(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            stream: false,
            maximumCompletionTokens: 600
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "OpenAIAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(responseString)"]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NSError(
                domain: "OpenAIAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        return (text: text, duration: Date().timeIntervalSince(startTime))
    }
}
