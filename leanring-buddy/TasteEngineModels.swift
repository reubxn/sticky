//
//  TasteEngineModels.swift
//  leanring-buddy
//
//  Shared models for Clicky's local Taste Engine integration.
//

import Foundation

enum SphereMode: String, CaseIterable, Identifiable, Codable {
    case assistant
    case observation
    case deployment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .assistant:
            return "Assistant"
        case .observation:
            return "Observe"
        case .deployment:
            return "Deploy"
        }
    }

    var shortDescription: String {
        switch self {
        case .assistant:
            return "Claude"
        case .observation:
            return "Learning"
        case .deployment:
            return "Recommending"
        }
    }

    var usesTasteEngine: Bool {
        switch self {
        case .assistant:
            return false
        case .observation, .deployment:
            return true
        }
    }
}

struct TasteEngineDesignContext: Codable {
    let targetName: String?
    let surface: String?
    let intent: String?
    let audience: String?
    let constraints: [String]?
    let positiveTerms: [String]?
    let negativeTerms: [String]?

    enum CodingKeys: String, CodingKey {
        case targetName = "target_name"
        case surface
        case intent
        case audience
        case constraints
        case positiveTerms = "positive_terms"
        case negativeTerms = "negative_terms"
    }
}

struct TasteEngineWeightedObject: Codable, Identifiable {
    let id: String?
    let label: String?
    let normalizedLabel: String?
    let name: String?
    let type: String?
    let source: String?
    let status: String?
    let weight: Double?
    let confidence: Double?
    let tags: [String]?
    let evidence: [String]?
    let rationale: String?

    var displayLabel: String {
        return label ?? name ?? normalizedLabel ?? type ?? id ?? "object"
    }
}

struct TasteEngineSphereAssociation: Codable {
    let weightedObjectId: String?
    let weight: Double?
    let confidence: Double?
    let rationale: String?
    let evidence: [String]?
}

struct TasteEngineSphere: Codable, Identifiable {
    let id: String?
    let name: String?
    let label: String?
    let description: String?
    let status: String?
    let source: String?
    let centroidTags: [String]?
    let associations: [TasteEngineSphereAssociation]?
    let weight: Double?
    let confidence: Double?
    let objects: [TasteEngineWeightedObject]?

    var displayName: String {
        return name ?? label ?? id ?? "sphere"
    }

    var displayConfidence: Double? {
        if let confidence {
            return confidence
        }

        guard let associations, !associations.isEmpty else {
            return nil
        }

        let confidenceTotal = associations.reduce(0.0) { partialResult, association in
            return partialResult + (association.confidence ?? association.weight ?? 0.5)
        }
        return confidenceTotal / Double(associations.count)
    }
}

struct TasteEngineSphereRecommendation: Codable {
    let sphere: TasteEngineSphere
    let score: Double?
    let matchedWeightedObjectIds: [String]?
    let rationale: String?
}

struct TasteEnginePointTarget: Codable {
    let x: Double
    let y: Double
    let label: String?
    let screenNumber: Int?
}

struct TasteEngineDecision: Codable {
    let action: String?
    let summary: String?
    let rationale: String?
    let confidence: Double?
    let target: TasteEnginePointTarget?
}

struct TasteEngineRecommendationRequest: Encodable {
    let transcript: String
    let prompt: String
    let screenshotDataURL: String
    let screenshot: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case designContext = "design_context"
        case weightedObjectIds = "weighted_object_ids"
        case includeDrafts = "include_drafts"
        case limit
        case transcript
        case prompt
        case screenshotDataURL
        case screenshotDataUrl
        case imageDataUrl
        case screenshot
        case mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let keywords = TasteEngineObservationContext.extractedKeywords(from: transcript)
        let designContext = TasteEngineDesignContext(
            targetName: prompt,
            surface: "macOS screen",
            intent: transcript,
            audience: nil,
            constraints: screenshotDataURL.isEmpty ? [] : ["cursor-screen screenshot attached"],
            positiveTerms: keywords,
            negativeTerms: nil
        )

        try container.encode(designContext, forKey: .designContext)
        try container.encode([String](), forKey: .weightedObjectIds)
        try container.encode(true, forKey: .includeDrafts)
        try container.encode(5, forKey: .limit)

        // Keep these legacy fields for compatibility with older local engine experiments.
        try container.encode(transcript, forKey: .transcript)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(screenshotDataURL, forKey: .screenshotDataURL)
        try container.encode(screenshotDataURL, forKey: .screenshotDataUrl)
        try container.encode(screenshotDataURL, forKey: .imageDataUrl)
        try container.encode(screenshot, forKey: .screenshot)
        try container.encode(mode, forKey: .mode)
    }
}

struct TasteEngineObservationContext: Codable {
    let transcript: String
    let intent: String
    let keywords: [String]

    var designContext: TasteEngineDesignContext {
        return TasteEngineDesignContext(
            targetName: intent,
            surface: "macOS observation",
            intent: transcript,
            audience: nil,
            constraints: nil,
            positiveTerms: keywords,
            negativeTerms: nil
        )
    }

    static func extractedKeywords(from transcript: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "again", "also", "and", "are", "because", "but", "can",
            "for", "from", "have", "into", "like", "look", "make", "more",
            "not", "now", "observe", "please", "remember", "that", "the",
            "this", "with", "you"
        ]

        let words = transcript
            .lowercased()
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

private struct TasteEngineObservationPayload: Encodable {
    let weightedObjectId: String
    let label: String
    let sphereLabel: String
    let weight: Double
    let confidence: Double
    let rationale: String
    let evidence: [String]

    enum CodingKeys: String, CodingKey {
        case weightedObjectId = "weighted_object_id"
        case label
        case sphereLabel = "sphere_label"
        case weight
        case confidence
        case rationale
        case evidence
    }
}

struct TasteEngineObservationRequest: Encodable {
    let transcript: String
    let context: TasteEngineObservationContext
    let mode: String

    enum CodingKeys: String, CodingKey {
        case designContext = "design_context"
        case observations
        case transcript
        case context
        case mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let observationKeywords = context.keywords.isEmpty
            ? ["observed preference"]
            : Array(context.keywords.prefix(6))
        let observations = observationKeywords.map { keyword in
            TasteEngineObservationPayload(
                weightedObjectId: keyword,
                label: keyword,
                sphereLabel: context.intent,
                weight: context.intent == "negative_preference" ? 0.24 : 0.62,
                confidence: 0.52,
                rationale: "Captured from Clicky observation mode.",
                evidence: [transcript]
            )
        }

        try container.encode(context.designContext, forKey: .designContext)
        try container.encode(observations, forKey: .observations)

        // Keep these legacy fields for compatibility with older local engine experiments.
        try container.encode(transcript, forKey: .transcript)
        try container.encode(context, forKey: .context)
        try container.encode(mode, forKey: .mode)
    }
}

struct TasteEngineAPIResponse: Codable {
    let summary: String?
    let message: String?
    let recommendation: String?
    let observation: String?
    let status: String?
    let observationSessionId: String?
    let spheres: [TasteEngineSphere]?
    let weightedObjects: [TasteEngineWeightedObject]?
    let associationsCreated: [TasteEngineSphereAssociation]?
    let recommendations: [TasteEngineSphereRecommendation]?
    let draftSphereCreated: TasteEngineSphere?
    let decision: TasteEngineDecision?
    let target: TasteEnginePointTarget?
    private let point: TasteEnginePointTarget?
    private let pointTargetResponse: TasteEnginePointTarget?

    var spokenSummary: String {
        let candidates = [
            summary,
            message,
            recommendation,
            observation,
            decision?.summary,
            decision?.rationale,
            status
        ]

        for candidate in candidates {
            if let trimmedCandidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmedCandidate.isEmpty {
                return trimmedCandidate
            }
        }

        if let strongestRecommendation = recommendations?.first {
            let sphereName = strongestRecommendation.sphere.displayName
            if let rationale = strongestRecommendation.rationale, !rationale.isEmpty {
                return "i'd use \(sphereName). \(rationale)"
            }
            return "i'd use \(sphereName)."
        }

        if let draftSphereCreated {
            return "i assembled a draft sphere called \(draftSphereCreated.displayName)."
        }

        if let strongestSphere = spheres?.first {
            return "i saved this observation into \(strongestSphere.displayName)."
        }

        if let strongestObject = weightedObjects?.first {
            return "i logged \(strongestObject.displayLabel)."
        }

        if let associationsCreated, !associationsCreated.isEmpty {
            return "i saved \(associationsCreated.count) weighted association\(associationsCreated.count == 1 ? "" : "s")."
        }

        return "done."
    }

    var pointTarget: TasteEnginePointTarget? {
        return target ?? decision?.target ?? pointTargetResponse ?? point
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case message
        case recommendation
        case observation
        case status
        case observationSessionId
        case spheres
        case weightedObjects
        case associationsCreated
        case recommendations
        case draftSphereCreated
        case decision
        case target
        case point
        case pointTargetResponse = "pointTarget"
    }
}
