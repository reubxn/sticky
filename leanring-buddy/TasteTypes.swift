//
//  TasteTypes.swift
//  leanring-buddy
//
//  Shared data shapes for Reverse Clicky's teach/apply modes.
//  Frozen at hour 0 of the hackathon — do not change without coordinating
//  across all owners.
//

import Foundation

enum TasteMode: String, Codable, CaseIterable {
    case ask
    case teach
    case apply

    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .teach: return "Teach"
        case .apply: return "Apply"
        }
    }
}

enum TasteScope: String, Codable {
    case personal
    case team
}

enum TasteDomain: String, Codable {
    case design
    case writing
    case code
    case general
}

/// A single taste principle the user has approved. Stored on disk in
/// taste-profile.json. Each teach session can produce many of these.
struct TastePrinciple: Codable, Identifiable {
    let id: String
    var domain: TasteDomain
    var statement: String
    var confidence: Double
    var evidence: [String]
    var tags: [String]
    var approved: Bool
    var authorId: String
    var createdAt: Date
    var updatedAt: Date
}

struct TasteProfile: Codable {
    var userId: String
    var principles: [TastePrinciple]
    var updatedAt: Date
}

struct TeamTasteProfile: Codable {
    var teamId: String
    var name: String
    var principles: [TastePrinciple]
    var updatedAt: Date
}

/// A moment Claude noticed in the teach session but isn't sure why the user
/// did it. Becomes one MCQ card in the post-session review. principleByOption
/// holds the four candidate principles in the same order as options — the user
/// picks one (or types their own) and that principle gets saved.
struct AmbiguousMoment: Codable, Identifiable {
    let id: String
    var frameIndex: Int
    var question: String
    var options: [String]
    var principleByOption: [TastePrinciple]
}

/// What SessionAnalyzer returns after a teach session. Confident principles
/// auto-save. Ambiguous moments show as review cards.
struct TeachSessionResult: Codable {
    var confident: [TastePrinciple]
    var ambiguous: [AmbiguousMoment]
}

/// State machine for a teach session. Parallel to (and independent of)
/// CompanionVoiceState — the user can still talk to Clicky while a teach
/// session is running, though for MVP we don't expect them to.
enum TeachSessionState {
    case idle
    case recording
    case analyzing
}
