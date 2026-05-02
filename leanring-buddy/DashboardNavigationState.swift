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
    case chat
    case memory
    case tastes
    case team
    case profile
    case recordings
    case chats
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat:       return "Chat"
        case .memory:     return "Memory"
        case .tastes:     return "Tastes"
        case .team:       return "Team"
        case .profile:    return "Profile"
        case .recordings: return "Recordings"
        case .chats:      return "Chat history"
        case .settings:   return "Settings"
        }
    }

    var iconSymbolName: String {
        switch self {
        case .chat:       return "bubble.left.and.bubble.right.fill"
        case .memory:     return "books.vertical.fill"
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

    /// Currently visible section. Defaults to live Chat — the dashboard
    /// is now the app's main interface, and Chat is the primary thing
    /// the user does there.
    @Published var selectedSection: DashboardSection = .chat

    /// When non-nil, the Personas tab opens scrolled to / showing
    /// this persona. Cleared when the user navigates away. Set by
    /// "click a persona in the mini panel" so the dashboard opens
    /// directly to that teammate's read-only view.
    @Published var focusedPersonaId: String? = nil
}
