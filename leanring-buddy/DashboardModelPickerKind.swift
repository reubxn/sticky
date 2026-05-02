//
//  DashboardModelPickerKind.swift
//  leanring-buddy
//
//  Friendly mapping for the three Claude models the app supports —
//  "Fast thinker / Balanced / Deep thinker" with a shape glyph each
//  ("△" / "○" / "✦"). Used by both the mini-panel footer and the
//  Dashboard's Settings tab so the labels stay in sync. The Claude
//  model id is still the source of truth — this enum just sits on
//  top of it for display purposes.
//

import Foundation

enum ModelPickerKind: String, CaseIterable {
    case fastThinker
    case balanced
    case deepThinker

    /// The Claude model id this kind corresponds to. The app already
    /// uses these strings throughout (`CompanionManager.selectedModel`,
    /// chat view model, settings screen), so this is just a friendlier
    /// label on top.
    var claudeModelId: String {
        switch self {
        case .fastThinker:  return "claude-haiku-4-5-20251001"
        case .balanced:     return "claude-sonnet-4-6"
        case .deepThinker:  return "claude-opus-4-7"
        }
    }

    /// Short label for the menu trigger ("Fast", "Balanced", "Deep").
    var shortLabel: String {
        switch self {
        case .fastThinker:  return "Fast"
        case .balanced:     return "Balanced"
        case .deepThinker:  return "Deep"
        }
    }

    /// Long label for the dropdown rows ("Fast thinker", "Balanced",
    /// "Deep thinker"). The dashboard uses this; the menu uses the
    /// short label so the trigger doesn't get crowded.
    var longLabel: String {
        switch self {
        case .fastThinker:  return "Fast thinker"
        case .balanced:     return "Balanced"
        case .deepThinker:  return "Deep thinker"
        }
    }

    /// One-line descriptor shown in menu rows + dashboard rows.
    var descriptor: String {
        switch self {
        case .fastThinker:  return "snappy answers, light reasoning"
        case .balanced:     return "good default for most asks"
        case .deepThinker:  return "slower, sharper, harder problems"
        }
    }

    /// Single-character shape glyph that visually represents the
    /// model's character. Triangle for fast (sharp/forward), circle
    /// for balanced (steady/whole), four-point star for deep
    /// (multifaceted). Drawn as a Text glyph rather than an SF
    /// Symbol so the same character renders identically across
    /// menu/dashboard/footer.
    var glyphCharacter: String {
        switch self {
        case .fastThinker:  return "▲"
        case .balanced:     return "●"
        case .deepThinker:  return "✦"
        }
    }

    /// Inverse of `claudeModelId` — picks a kind from a stored model
    /// string. Falls back to `.balanced` for unknown ids so a stale
    /// UserDefaults value doesn't render an empty menu.
    static func fromClaudeModelId(_ modelId: String) -> ModelPickerKind {
        return ModelPickerKind.allCases.first(where: { $0.claudeModelId == modelId })
            ?? .balanced
    }
}
