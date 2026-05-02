//
//  PersonaBundle.swift
//  leanring-buddy
//
//  A "persona" is a complete identity Sticky can wear — a face, a soul,
//  a voice, and a taste profile, all bundled together. Picking a persona
//  in the panel swaps every visible/audible piece of the companion at
//  once: the cursor becomes their face, the system prompt is prepended
//  with their personality, the TTS speaks in their voice, and answers are
//  grounded in their saved taste principles.
//
//  The MVP ships three sample teammate bundles baked into the app (see
//  PersonaStore). The "Me" and "Team" selections fall back to the user's
//  own configured Sticky — their selected ElevenLabs voice, their saved
//  TasteProfile on disk, the default colored orb cursor.
//

import Foundation
import SwiftUI

/// Which identity Sticky is currently wearing. Persisted to UserDefaults
/// so the user's choice survives restarts.
///
/// - `.me` — the user's own configured Clicky (their selected voice, their
///   saved personal taste profile, the default colored orb cursor). The
///   existing taste-scope toggle (Personal vs Team) still applies when
///   this case is active.
/// - `.team` — same chrome as `.me` but the system prompt also unions in
///   the team taste profile. Kept around for backward compatibility with
///   the existing scope toggle; in a future cleanup we could merge this
///   into a single picker row.
/// - `.teammate(id:)` — borrow another person's full persona bundle. The
///   bundle's `soul`, `voiceId`, `taste`, and `avatar` all take over for
///   the duration of the selection.
enum PersonaSelection: Equatable, Hashable {
    case me
    case team
    case teammate(id: String)

    /// Stable string used for UserDefaults persistence and analytics.
    var persistenceKey: String {
        switch self {
        case .me: return "me"
        case .team: return "team"
        case .teammate(let id): return "teammate:\(id)"
        }
    }

    /// Inverse of `persistenceKey`. Returns nil when the stored value
    /// doesn't decode (e.g. a teammate id that's been removed since the
    /// preference was written) so callers can fall back to `.me`.
    static func fromPersistenceKey(_ key: String) -> PersonaSelection? {
        if key == "me" { return .me }
        if key == "team" { return .team }
        if key.hasPrefix("teammate:") {
            let id = String(key.dropFirst("teammate:".count))
            guard !id.isEmpty else { return nil }
            return .teammate(id: id)
        }
        return nil
    }
}

/// How the persona's face is rendered on the cursor. Three cases lets us
/// ship a working sample-data MVP today (initials/symbols don't need
/// image assets) and seamlessly upgrade to real photos later by swapping
/// the case to `.imageFile`.
enum PersonaAvatar: Codable, Equatable, Hashable {
    /// Two-or-three-letter initials drawn over a solid colored circle.
    /// Used for sample personas while real photos aren't shipped yet.
    case initials(text: String, hexColor: String)

    /// SF Symbol name centered over a solid colored circle. Useful for
    /// the "Team" pseudo-persona (which has no single face).
    case systemSymbol(name: String, hexColor: String)

    /// Filename of an image inside the persona's directory in
    /// Application Support. Resolved by `PersonaStore.imageURL(for:)`.
    /// Switch to this case once the user uploads a real photo for a
    /// teammate.
    case imageFile(filename: String)

    /// The accent color associated with this avatar — used to tint the
    /// halo glow around the cursor and the small swatches in the panel
    /// picker. For `.imageFile` we don't know the photo's dominant color
    /// without sampling pixels, so callers should fall back to the
    /// persona's separate `accentColorHex` in that case.
    var accentHexColor: String? {
        switch self {
        case .initials(_, let hex), .systemSymbol(_, let hex):
            return hex
        case .imageFile:
            return nil
        }
    }
}

/// One persona bundle. Owned by a single account in the long-term vision
/// (the person uploads their own photo, writes their own soul, picks
/// their own voice, teaches their own taste). For the hackathon MVP all
/// three teammate bundles are static sample data inside `PersonaStore`.
struct PersonaBundle: Codable, Identifiable, Equatable {
    /// Stable url-safe identifier. Used as the directory name on disk
    /// when we eventually persist real bundles to Application Support.
    let id: String

    /// Display name shown in the picker — usually a first name.
    var displayName: String

    /// Short role/title shown under the name in the picker (e.g.
    /// "Design Lead", "Staff Engineer"). Optional — pass nil to suppress.
    var role: String?

    /// How the face is rendered on the cursor and in the picker.
    var avatar: PersonaAvatar

    /// Hex color string used as the halo/accent color around the cursor
    /// when this persona is active. Falls back to the avatar's
    /// `accentHexColor` if nil. Required for `.imageFile` avatars where
    /// we can't infer a color from the avatar case itself.
    var accentColorHex: String

    /// The persona's "personality" prose. Prepended to the existing
    /// Sticky voice system prompt when this persona is active so Claude
    /// answers in their voice. Free-form markdown — no schema, no
    /// length cap (the Sticky base prompt is already long, a paragraph
    /// or two extra is fine).
    var soul: String

    /// ElevenLabs voice id used for TTS while this persona is active.
    /// Must be one of the ids in `ElevenLabsTTSClient.freeVoices` so we
    /// know the user's account has access to it.
    var voiceId: String

    /// The persona's saved taste profile. Injected as judgment context
    /// into the system prompt the same way the user's own taste is
    /// injected when persona is `.me`.
    var taste: TasteProfile

    /// Resolves the SwiftUI `Color` for the halo around this persona's
    /// cursor. Tries `accentColorHex` first, then the avatar's case-
    /// specific accent. Defaults to a warm amber if both are missing /
    /// malformed so the cursor always has *some* glow color.
    var accentColor: Color {
        if let color = Color(hexString: accentColorHex) { return color }
        if let avatarHex = avatar.accentHexColor,
           let color = Color(hexString: avatarHex) {
            return color
        }
        return Color(red: 1.00, green: 0.62, blue: 0.18) // amber fallback
    }
}

// MARK: - Color hex parsing

extension Color {
    /// Best-effort hex string → SwiftUI Color. Accepts `#rrggbb` or
    /// `rrggbb`. Returns nil for malformed input. Intentionally simple
    /// — we don't need alpha or 3-digit shorthand for persona accents.
    init?(hexString: String) {
        var sanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let rgbValue = UInt32(sanitized, radix: 16) else {
            return nil
        }
        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
