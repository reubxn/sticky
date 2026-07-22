//
//  PersonaStore.swift
//  leanring-buddy
//
//  Loads the available persona bundles Sticky can wear.
//

import Foundation
import SwiftUI

enum PersonaStore {
    /// Which persona owns this Sticky install. Teach mode appends newly
    /// extracted principles to this persona's TASTE.md.
    static let myPersonaId: String = "reuban"

    /// Re-reads the local user's bundle so freshly taught principles become
    /// available without restarting the app.
    static func myCurrentBundle() -> PersonaBundle? {
        return try? PersonaTasteFileStore.loadBundle(forId: myPersonaId)
    }

    /// Teammates are loaded only from TASTE.md files. Missing persona files
    /// produce an empty teammate list instead of fabricated fallback data.
    static let availableTeammates: [PersonaBundle] = {
        let bundlesFromMarkdown = PersonaTasteFileStore.loadAllAvailableBundles()
        if !bundlesFromMarkdown.isEmpty {
            print("📄 PersonaStore: loaded \(bundlesFromMarkdown.count) bundle(s) from TASTE.md")
        }
        return bundlesFromMarkdown.filter { $0.id != myPersonaId }
    }()

    /// The local user's bundle is kept separate from the teammate list so
    /// `.me` can borrow its avatar and accent color.
    static let myOwnBundle: PersonaBundle? = {
        PersonaTasteFileStore.loadAllAvailableBundles()
            .first(where: { $0.id == myPersonaId })
    }()

    static func teammate(withId id: String) -> PersonaBundle? {
        return availableTeammates.first(where: { $0.id == id })
    }

    static let teamPseudoPersona: PersonaBundle = PersonaBundle(
        id: "__team__",
        displayName: "Team",
        role: "Pooled taste",
        avatar: .systemSymbol(name: "person.2.fill", hexColor: "#7C8DA3"),
        accentColorHex: "#7C8DA3",
        soul: "",
        voiceId: "",
        taste: TasteProfile(userId: "team-pseudo", principles: [], updatedAt: Date())
    )

    static let mePseudoPersona: PersonaBundle = PersonaBundle(
        id: "__me__",
        displayName: "Me",
        role: "Your taste",
        avatar: myOwnBundle?.avatar
            ?? .systemSymbol(name: "person.fill", hexColor: "#3B82F6"),
        accentColorHex: myOwnBundle?.accentColorHex ?? "#3B82F6",
        soul: "",
        voiceId: "",
        taste: TasteProfile(userId: "local-user", principles: [], updatedAt: Date())
    )

    static var allWheelPersonas: [PersonaBundle] {
        return [mePseudoPersona, teamPseudoPersona] + availableTeammates
    }

    static func selectionForWheelPersona(_ persona: PersonaBundle) -> PersonaSelection {
        switch persona.id {
        case mePseudoPersona.id:
            return .me
        case teamPseudoPersona.id:
            return .team
        default:
            return .teammate(id: persona.id)
        }
    }

    static func wheelPersonaForSelection(_ selection: PersonaSelection) -> PersonaBundle? {
        switch selection {
        case .me:
            return mePseudoPersona
        case .team:
            return teamPseudoPersona
        case .teammate(let id):
            return teammate(withId: id)
        }
    }

    @MainActor
    static func uploadedProfilePicturePath(forPersonaId personaId: String) -> String? {
        guard personaId == myPersonaId || personaId == mePseudoPersona.id else { return nil }
        return DashboardMockAuthState.shared.profilePicturePath
    }
}
