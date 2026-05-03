//
//  TasteCommandParser.swift
//  leanring-buddy
//
//  Lightweight transcript parsing for local Taste Engine observation context.
//

import Foundation

enum TasteCommandParser {
    static func observationContext(from transcript: String) -> TasteEngineObservationContext {
        let normalizedTranscript = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TasteEngineObservationContext(
            transcript: transcript,
            intent: inferredIntent(from: normalizedTranscript),
            keywords: extractedKeywords(from: normalizedTranscript)
        )
    }

    private static func inferredIntent(from normalizedTranscript: String) -> String {
        if normalizedTranscript.contains("like")
            || normalizedTranscript.contains("love")
            || normalizedTranscript.contains("prefer")
            || normalizedTranscript.contains("good") {
            return "positive_preference"
        }

        if normalizedTranscript.contains("dislike")
            || normalizedTranscript.contains("hate")
            || normalizedTranscript.contains("avoid")
            || normalizedTranscript.contains("bad") {
            return "negative_preference"
        }

        if normalizedTranscript.contains("remember")
            || normalizedTranscript.contains("notice")
            || normalizedTranscript.contains("observe") {
            return "observation"
        }

        return "note"
    }

    private static func extractedKeywords(from normalizedTranscript: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "again", "also", "and", "are", "because", "but", "can",
            "for", "from", "have", "into", "like", "look", "make", "more",
            "not", "now", "observe", "please", "remember", "that", "the",
            "this", "with", "you"
        ]

        let words = normalizedTranscript
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .map(String.init)
            .filter { word in
                word.count > 2 && !stopWords.contains(word)
            }

        var uniqueKeywords: [String] = []
        for word in words {
            guard !uniqueKeywords.contains(word) else { continue }
            uniqueKeywords.append(word)
            if uniqueKeywords.count == 8 {
                break
            }
        }

        return uniqueKeywords
    }
}
