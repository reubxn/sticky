//
//  DashboardModelPickerKind.swift
//  leanring-buddy
//
//  Friendly mapping for the AI models the app supports. Used by both
//  the chat composer and the Dashboard's Settings tab so labels stay
//  in sync. The provider model id remains the source of truth.
//

import Foundation

enum AIProvider: Equatable {
    case anthropic
    case openAI
}

enum ModelPickerKind: String, CaseIterable {
    case fastThinker
    case balanced
    case deepThinker
    case chatGPT

    static let preferenceKey = "selectedAIModel"
    static let defaultModelId = ModelPickerKind.chatGPT.modelId

    var provider: AIProvider {
        switch self {
        case .fastThinker, .balanced, .deepThinker:
            return .anthropic
        case .chatGPT:
            return .openAI
        }
    }

    var modelId: String {
        switch self {
        case .fastThinker:  return "claude-haiku-4-5-20251001"
        case .balanced:     return "claude-sonnet-4-6"
        case .deepThinker:  return "claude-opus-4-7"
        case .chatGPT:      return "gpt-5.2-2025-12-11"
        }
    }

    var shortLabel: String {
        switch self {
        case .fastThinker:  return "Fast"
        case .balanced:     return "Balanced"
        case .deepThinker:  return "Deep"
        case .chatGPT:      return "ChatGPT"
        }
    }

    var longLabel: String {
        switch self {
        case .fastThinker:  return "Fast thinker"
        case .balanced:     return "Balanced"
        case .deepThinker:  return "Deep thinker"
        case .chatGPT:      return "ChatGPT"
        }
    }

    var descriptor: String {
        switch self {
        case .fastThinker:  return "Claude · snappy answers, light reasoning"
        case .balanced:     return "Claude · good default for most asks"
        case .deepThinker:  return "Claude · slower, sharper, harder problems"
        case .chatGPT:      return "OpenAI · GPT-5.2"
        }
    }

    var glyphCharacter: String {
        switch self {
        case .fastThinker:  return "▲"
        case .balanced:     return "●"
        case .deepThinker:  return "✦"
        case .chatGPT:      return "◆"
        }
    }

    static func fromModelId(_ modelId: String) -> ModelPickerKind {
        return ModelPickerKind.allCases.first(where: { $0.modelId == modelId })
            ?? .chatGPT
    }
}
