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

enum TasteTeachingPersona: String, CaseIterable, Identifiable, Codable {
    case magda
    case leo
    case reuban

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .magda:
            return "Magda"
        case .leo:
            return "Leo"
        case .reuban:
            return "Reuban"
        }
    }

    var roleTitle: String {
        switch self {
        case .magda:
            return "Design"
        case .leo:
            return "Analysis"
        case .reuban:
            return "Integration"
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

enum TasteEngineTasteFusionMode: String, Codable {
    case singleProfile = "single_profile"
    case weightedBlend = "weighted_blend"
}

struct TasteEngineTasteProfileRef: Codable {
    let profileId: String
    let displayName: String?
    let weight: Double?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case displayName = "display_name"
        case weight
        case role
    }
}

struct TasteEngineTasteProfileSelection: Codable {
    let selectedProfiles: [TasteEngineTasteProfileRef]

    enum CodingKeys: String, CodingKey {
        case selectedProfiles = "selected_profiles"
    }
}

struct TasteEngineTasteFusionMetadata: Codable {
    let mode: TasteEngineTasteFusionMode?
    let selectedProfiles: [TasteEngineTasteProfileRef]?
    let deploymentIntent: String?
    let source: String?
    let appliedToRanking: Bool?
    let recommendationLens: TasteEngineRecommendationLens?

    enum CodingKeys: String, CodingKey {
        case mode
        case selectedProfiles = "selected_profiles"
        case deploymentIntent = "deployment_intent"
        case source
        case appliedToRanking = "applied_to_ranking"
        case recommendationLens = "recommendation_lens"
    }
}

struct TasteEngineRecommendationLens: Codable {
    let id: String
    let label: String?
    let instruction: String?
    let priorityTags: [String]?
    let deprioritizeTags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case instruction
        case priorityTags = "priority_tags"
        case deprioritizeTags = "deprioritize_tags"
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
    let creatorProfileId: String?
    let collaboratorProfileIds: [String]?

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
    let creatorProfileId: String?
    let collaboratorProfileIds: [String]?

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
    let sourceDecisionPackages: [TasteEngineDecisionPackageCitation]?
    let guidance: TasteEngineRecommendationGuidance?
    let trust: TasteEngineRecommendationTrust?
    let rationale: String?
}

struct TasteEngineDecisionPackageCitation: Codable {
    let packageId: String?
    let sphereId: String?
    let status: String?
    let centralDecision: String?
    let reusableRule: String?
    let summaryMarkdown: String?
    let deploymentPrompt: String?
    let useWhen: [String]?
    let avoidWhen: [String]?
}

struct TasteEngineRecommendationGuidance: Codable {
    let summary: String?
}

struct TasteEngineRecommendationTrust: Codable {
    let recommendationStatus: String?
    let sphereStatus: String?
    let usesOnlyApprovedSources: Bool?
    let approvedSourceCount: Int?
    let lifecycleNote: String?
}

struct TasteEngineClickyApplyGuidance: Codable {
    let spokenSummary: String?
    let activeLens: TasteEngineRecommendationLens?
    let citedSphereIds: [String]?
    let citedPackageIds: [String]?
    let trustSummary: String?
}

struct TasteEngineClickyTeachResponse: Codable {
    let packageId: String?
    let packageStatus: String?
    let sphereId: String?
    let sphereLabel: String?
    let creatorProfileId: String?
    let centralDecision: String?
    let reusableRule: String?
    let followUpQuestion: String?
    let summaryMarkdown: String?
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

struct TasteEngineScreenshotEvidence: Encodable {
    let dataURL: String
    let label: String
    let isCursorScreen: Bool
    let displayWidthInPoints: Int
    let displayHeightInPoints: Int
    let screenshotWidthInPixels: Int
    let screenshotHeightInPixels: Int
    let screenCount: Int

    enum CodingKeys: String, CodingKey {
        case dataURL = "data_url"
        case dataUrl = "dataUrl"
        case label
        case isCursorScreen = "is_cursor_screen"
        case displayWidthInPoints = "display_width_in_points"
        case displayHeightInPoints = "display_height_in_points"
        case screenshotWidthInPixels = "screenshot_width_in_pixels"
        case screenshotHeightInPixels = "screenshot_height_in_pixels"
        case screenCount = "screen_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dataURL, forKey: .dataURL)
        try container.encode(dataURL, forKey: .dataUrl)
        try container.encode(label, forKey: .label)
        try container.encode(isCursorScreen, forKey: .isCursorScreen)
        try container.encode(displayWidthInPoints, forKey: .displayWidthInPoints)
        try container.encode(displayHeightInPoints, forKey: .displayHeightInPoints)
        try container.encode(screenshotWidthInPixels, forKey: .screenshotWidthInPixels)
        try container.encode(screenshotHeightInPixels, forKey: .screenshotHeightInPixels)
        try container.encode(screenCount, forKey: .screenCount)
    }
}

struct TasteEngineRecommendationRequest: Encodable {
    let transcript: String
    let conversationTranscript: String
    let prompt: String
    let screenshotDataURL: String
    let screenshot: String
    let screenshotEvidence: TasteEngineScreenshotEvidence
    let mode: String
    let tasteProfileSelection: TasteEngineTasteProfileSelection?
    let fusionMode: TasteEngineTasteFusionMode?
    let deploymentIntent: String?
    let recommendationLens: TasteEngineRecommendationLens?

    enum CodingKeys: String, CodingKey {
        case designContext = "design_context"
        case weightedObjectIds = "weighted_object_ids"
        case includeDrafts = "include_drafts"
        case limit
        case tasteProfileSelection = "taste_profile_selection"
        case fusionMode = "fusion_mode"
        case deploymentIntent = "deployment_intent"
        case recommendationLens = "recommendation_lens"
        case transcript
        case conversationTranscript = "conversation_transcript"
        case conversationText = "conversation_text"
        case prompt
        case screenshotDataURL
        case screenshotDataUrl
        case imageDataUrl
        case screenshot
        case screenshotEvidence = "screenshot_evidence"
        case screenshotMetadata = "screenshot_metadata"
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
        try container.encodeIfPresent(tasteProfileSelection, forKey: .tasteProfileSelection)
        try container.encodeIfPresent(fusionMode, forKey: .fusionMode)
        try container.encodeIfPresent(deploymentIntent, forKey: .deploymentIntent)
        try container.encodeIfPresent(recommendationLens, forKey: .recommendationLens)

        // Keep these legacy fields for compatibility with older local engine experiments.
        try container.encode(transcript, forKey: .transcript)
        try container.encode(conversationTranscript, forKey: .conversationTranscript)
        try container.encode(conversationTranscript, forKey: .conversationText)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(screenshotDataURL, forKey: .screenshotDataURL)
        try container.encode(screenshotDataURL, forKey: .screenshotDataUrl)
        try container.encode(screenshotDataURL, forKey: .imageDataUrl)
        try container.encode(screenshot, forKey: .screenshot)
        try container.encode(screenshotEvidence, forKey: .screenshotEvidence)
        try container.encode(screenshotEvidence, forKey: .screenshotMetadata)
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
    let conversationTranscript: String
    let screenshotEvidence: TasteEngineScreenshotEvidence?
    let mode: String

    enum CodingKeys: String, CodingKey {
        case designContext = "design_context"
        case observations
        case transcript
        case conversationTranscript = "conversation_transcript"
        case conversationText = "conversation_text"
        case screenshotEvidence = "screenshot_evidence"
        case screenshotMetadata = "screenshot_metadata"
        case screenshotDataURL = "screenshot_data_url"
        case screenshotDataUrl = "screenshotDataUrl"
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
        try container.encode(conversationTranscript, forKey: .conversationTranscript)
        try container.encode(conversationTranscript, forKey: .conversationText)
        if let screenshotEvidence {
            try container.encode(screenshotEvidence, forKey: .screenshotEvidence)
            try container.encode(screenshotEvidence, forKey: .screenshotMetadata)
            try container.encode(screenshotEvidence.dataURL, forKey: .screenshotDataURL)
            try container.encode(screenshotEvidence.dataURL, forKey: .screenshotDataUrl)
        }
        try container.encode(context, forKey: .context)
        try container.encode(mode, forKey: .mode)
    }
}

private struct TasteEngineCapturePayload: Encodable {
    let kind: String
    let trigger: String
    let text: String
    let transcript: String
    let userNote: String
    let screenshotDataURL: String
    let creatorProfileId: String?
    let collaboratorProfileIds: [String]?
    let metadata: TasteEngineCaptureMetadata

    enum CodingKeys: String, CodingKey {
        case kind
        case trigger
        case text
        case transcript
        case userNote = "user_note"
        case screenshotDataURL = "screenshot_data_url"
        case creatorProfileId = "creator_profile_id"
        case collaboratorProfileIds = "collaborator_profile_ids"
        case metadata
    }
}

private struct TasteEngineCaptureMetadata: Encodable {
    let source: String
    let mode: String
    let transcript: String
    let conversationTranscript: String
    let screenshotEvidence: TasteEngineScreenshotEvidence

    enum CodingKeys: String, CodingKey {
        case source
        case mode
        case transcript
        case conversationTranscript = "conversation_transcript"
        case conversationText = "conversation_text"
        case screenshotEvidence = "screenshot_evidence"
        case screenshotMetadata = "screenshot_metadata"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(mode, forKey: .mode)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(conversationTranscript, forKey: .conversationTranscript)
        try container.encode(conversationTranscript, forKey: .conversationText)
        try container.encode(screenshotEvidence, forKey: .screenshotEvidence)
        try container.encode(screenshotEvidence, forKey: .screenshotMetadata)
    }
}

struct TasteEngineCaptureIngestRequest: Encodable {
    let transcript: String
    let context: TasteEngineObservationContext
    let conversationTranscript: String
    let screenshotEvidence: TasteEngineScreenshotEvidence
    let mode: String
    let creatorProfileId: String?
    let collaboratorProfileIds: [String]?

    enum CodingKeys: String, CodingKey {
        case capture
        case designContext = "design_context"
        case sphereLabel = "sphere_label"
        case creatorProfileId = "creator_profile_id"
        case collaboratorProfileIds = "collaborator_profile_ids"
        case transcript
        case conversationTranscript = "conversation_transcript"
        case screenshotEvidence = "screenshot_evidence"
        case screenshotDataURL = "screenshot_data_url"
        case mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let capture = TasteEngineCapturePayload(
            kind: "voice",
            trigger: "push_to_talk",
            text: transcript,
            transcript: transcript,
            userNote: transcript,
            screenshotDataURL: screenshotEvidence.dataURL,
            creatorProfileId: creatorProfileId,
            collaboratorProfileIds: collaboratorProfileIds,
            metadata: TasteEngineCaptureMetadata(
                source: "macOS Clicky",
                mode: mode,
                transcript: transcript,
                conversationTranscript: conversationTranscript,
                screenshotEvidence: screenshotEvidence
            )
        )

        try container.encode(capture, forKey: .capture)
        try container.encode(context.designContext, forKey: .designContext)
        try container.encode(context.intent, forKey: .sphereLabel)
        try container.encodeIfPresent(creatorProfileId, forKey: .creatorProfileId)
        try container.encodeIfPresent(collaboratorProfileIds, forKey: .collaboratorProfileIds)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(conversationTranscript, forKey: .conversationTranscript)
        try container.encode(screenshotEvidence, forKey: .screenshotEvidence)
        try container.encode(screenshotEvidence.dataURL, forKey: .screenshotDataURL)
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
    let tasteFusion: TasteEngineTasteFusionMetadata?
    let recommendationLens: TasteEngineRecommendationLens?
    let clickyGuidance: TasteEngineClickyApplyGuidance?
    let clickyTeach: TasteEngineClickyTeachResponse?
    let sphere: TasteEngineSphere?
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
            clickyGuidance?.spokenSummary,
            clickyTeach?.centralDecision,
            clickyTeach?.reusableRule,
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
            if let guidanceSummary = strongestRecommendation.guidance?.summary, !guidanceSummary.isEmpty {
                return "i'd use \(sphereName). \(guidanceSummary)"
            }
            if let rationale = strongestRecommendation.rationale, !rationale.isEmpty {
                return "i'd use \(sphereName). \(rationale)"
            }
            return "i'd use \(sphereName)."
        }

        if let draftSphereCreated {
            return "i assembled a draft sphere called \(draftSphereCreated.displayName)."
        }

        if let sphere {
            return "i assembled a draft sphere called \(sphere.displayName)."
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
        case tasteFusion
        case recommendationLens
        case clickyGuidance
        case clickyTeach
        case sphere
        case decision
        case target
        case point
        case pointTargetResponse = "pointTarget"
    }
}
