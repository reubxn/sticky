//
//  DashboardNavigationState.swift
//  leanring-buddy
//
//  Shared navigation state for the Dashboard window: which sidebar
//  section is selected and (optionally) which persona is focused
//  inside the Personas tab. A separate ObservableObject so the mini
//  panel can request "open the dashboard pinned to teammate X" from
//  outside the SwiftUI hierarchy.
//

import Combine
import Foundation

/// Top-level dashboard sections, ordered as they appear in the
/// sidebar. `tastes` is the renamed Personas list per the user's
/// "rename them tastes" instruction (the underlying types are still
/// PersonaBundle — only the surface label changes).
enum DashboardSection: String, CaseIterable, Identifiable {
    case tastes
    case team
    case profile
    case recordings
    case chats
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tastes:     return "Tastes"
        case .team:       return "Team"
        case .profile:    return "Profile"
        case .recordings: return "Recordings"
        case .chats:      return "Chats"
        case .settings:   return "Settings"
        }
    }

    var iconSymbolName: String {
        switch self {
        case .tastes:     return "person.crop.circle"
        case .team:       return "person.2"
        case .profile:    return "person.text.rectangle"
        case .recordings: return "waveform"
        case .chats:      return "bubble.left.and.bubble.right"
        case .settings:   return "gearshape"
        }
    }
}

@MainActor
final class DashboardNavigationState: ObservableObject {
    static let shared = DashboardNavigationState()

    /// Currently visible section. Defaults to Tastes — that's the
    /// dashboard's primary content for the hackathon demo.
    @Published var selectedSection: DashboardSection = .tastes

    /// When non-nil, the Personas tab opens scrolled to / showing
    /// this persona. Cleared when the user navigates away. Set by
    /// "click a persona in the mini panel" so the dashboard opens
    /// directly to that teammate's read-only view.
    @Published var focusedPersonaId: String? = nil
}
