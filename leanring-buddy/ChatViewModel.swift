//
//  ChatViewModel.swift
//  leanring-buddy
//
//  Backing state for the pop-out chat window. Holds the message list,
//  manages an in-flight streaming response from Claude, and captures a
//  fresh screenshot for every user message so Claude always has visual
//  context for what the user is asking about.
//
//  Owns its own ClaudeAPI instance so the chat works independently of
//  the voice flow's ClaudeAPI — we don't want a chat send to clobber a
//  mid-flight voice response or vice versa.
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// One entry in the chat transcript. Either typed by the user or
/// streamed back from Claude. Identifiable so SwiftUI can diff the list
/// efficiently as new messages arrive and the assistant message updates
/// chunk-by-chunk during streaming.
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    /// True for an assistant message that is still being streamed in.
    /// The view uses this to render a subtle "typing" affordance.
    var isStreaming: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}

@MainActor
final class ChatViewModel: ObservableObject {

    /// Same Worker proxy URL the voice flow uses. Hardcoded here rather
    /// than reaching into CompanionManager so the chat can be created
    /// before/independently of the voice manager.
    private static let workerChatProxyURL = "https://clicky-proxy.reubanramsden.workers.dev/chat"

    /// System prompt for the chat surface. Deliberately generic — the
    /// chat is for asking questions about whatever is on screen, with
    /// less of the "spoken-word, point-at-things" framing the voice
    /// system prompt has. No `[POINT:...]` tag instructions because the
    /// chat doesn't drive the cursor overlay.
    private static let chatSystemPrompt = """
    You are Sticky, a helpful AI assistant in a chat window on the user's Mac. \
    Each user message is accompanied by a fresh screenshot of every connected \
    display so you can see exactly what they're looking at right now. Use the \
    screenshot to answer concretely about what's on screen — refer to specific \
    UI elements, text, errors, or content visible in the image. If the user's \
    question is not about what's on screen, just answer the question normally. \
    Keep replies clear and conversational. Use markdown when it helps \
    (code blocks for code, lists for steps), but don't over-format short replies.
    """

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isResponding: Bool = false
    /// User-facing error string for the last failed send. Cleared on the
    /// next successful send. Surfaced as a small banner in the chat view.
    @Published private(set) var lastErrorMessage: String? = nil

    /// The text in the input field. Bound directly to the TextField so
    /// the view model can clear it when a message is sent.
    @Published var draftMessage: String = ""

    private lazy var claudeAPI: ClaudeAPI = {
        return ClaudeAPI(proxyURL: Self.workerChatProxyURL, model: selectedModel)
    }()

    /// Mirrors the voice flow's model preference so picking Sonnet/Opus
    /// in the menu bar panel applies to chat too. Reads the same
    /// UserDefaults key the voice path writes to. Updated by
    /// `refreshSelectedModelFromUserDefaults()` which the chat window
    /// calls each time it becomes visible.
    private var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"

    /// In-flight send task. Cancelled if the user sends a new message
    /// before the previous response finishes streaming.
    private var currentSendTask: Task<Void, Never>?

    /// Stable id for the currently-active chat session. Each finalized
    /// assistant message overwrites the same on-disk file under this
    /// id, so the Dashboard's Chats tab shows one growing entry per
    /// chat — not a new entry per message. Reset on `startNewChat`
    /// so the next conversation starts a separate archive file.
    private var activeChatHistorySessionId: String = UUID().uuidString

    /// Picks up the latest model selection from UserDefaults. Called by
    /// the chat window whenever it's shown so swapping Sonnet ↔ Opus in
    /// the menu bar panel takes effect on the next chat send without
    /// needing a Combine wire-up between the two windows.
    func refreshSelectedModelFromUserDefaults() {
        let latestSelectedModel = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"
        if latestSelectedModel != selectedModel {
            selectedModel = latestSelectedModel
            claudeAPI.model = latestSelectedModel
        }
    }

    /// Clears the entire transcript. Used by the "New chat" button.
    /// Cancels any in-flight response so a new chat starts truly empty.
    func startNewChat() {
        currentSendTask?.cancel()
        currentSendTask = nil
        messages.removeAll()
        lastErrorMessage = nil
        isResponding = false
        // Mint a new id so the next chat archives to a fresh file
        // instead of overwriting the just-finished session.
        activeChatHistorySessionId = UUID().uuidString
    }

    /// Sends the current `draftMessage`. Captures a screenshot, appends
    /// a user message + a placeholder assistant message to the list,
    /// then streams Claude's reply into the placeholder.
    func sendDraftMessage() {
        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        guard !isResponding else { return }

        let userMessage = ChatMessage(role: .user, text: trimmedDraft)
        let assistantPlaceholder = ChatMessage(role: .assistant, text: "", isStreaming: true)

        messages.append(userMessage)
        messages.append(assistantPlaceholder)
        let assistantPlaceholderID = assistantPlaceholder.id

        draftMessage = ""
        lastErrorMessage = nil
        isResponding = true

        // Build the conversation history Claude needs *before* the new
        // user/assistant pair we just appended — so prior turns are
        // included as context but the current question isn't duplicated.
        let priorMessages = messages.dropLast(2)
        let conversationHistory = Self.buildConversationHistory(from: Array(priorMessages))

        currentSendTask?.cancel()
        currentSendTask = Task { [weak self] in
            await self?.runChatSend(
                userText: trimmedDraft,
                assistantPlaceholderID: assistantPlaceholderID,
                conversationHistory: conversationHistory
            )
        }
    }

    /// The end-to-end chat send: capture screenshots → call Claude with
    /// streaming → write streamed text into the placeholder assistant
    /// message → mark complete (or show an error and remove the
    /// placeholder).
    private func runChatSend(
        userText: String,
        assistantPlaceholderID: UUID,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)]
    ) async {
        defer {
            isResponding = false
        }

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

            // Same labeling pattern as the voice flow so Claude has the
            // pixel dimensions of each screenshot — useful if it ever
            // needs to point at something, and harmless otherwise.
            let labeledImagesForClaude = screenCaptures.map { capture in
                let dimensionInfoSuffix = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                return (data: capture.imageData, label: capture.label + dimensionInfoSuffix)
            }

            try Task.checkCancellation()

            let (_, _) = try await claudeAPI.analyzeImageStreaming(
                images: labeledImagesForClaude,
                systemPrompt: Self.chatSystemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userText,
                onTextChunk: { @MainActor [weak self] accumulatedStreamedText in
                    guard let self else { return }
                    self.updateStreamingAssistantMessage(
                        id: assistantPlaceholderID,
                        text: accumulatedStreamedText
                    )
                }
            )

            // Mark the assistant message as no-longer-streaming so the
            // typing affordance disappears.
            finalizeAssistantMessage(id: assistantPlaceholderID)
        } catch is CancellationError {
            // The user sent another message or hit "New chat" — silently
            // drop the placeholder so we don't leave a half-finished
            // assistant bubble in the transcript.
            removeAssistantMessage(id: assistantPlaceholderID)
        } catch {
            removeAssistantMessage(id: assistantPlaceholderID)
            lastErrorMessage = userFacingErrorMessage(for: error)
        }
    }

    private func updateStreamingAssistantMessage(id: UUID, text: String) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[messageIndex].text = text
    }

    private func finalizeAssistantMessage(id: UUID) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[messageIndex].isStreaming = false
        // Archive (or update) the session on disk so the Dashboard's
        // Chats tab + the mini panel's recent-activity feed can show
        // it. Overwrites the same file each time the chat grows.
        archiveCurrentChatSessionToDisk()
    }

    /// Snapshots the current message list to the dashboard chat
    /// history store under the stable `activeChatHistorySessionId`.
    /// Called after each finalized assistant message so the archive
    /// stays current, and called from the disk-backed recent-activity
    /// feed in the mini panel.
    private func archiveCurrentChatSessionToDisk() {
        let archivableMessages: [DashboardChatMessage] = messages.map { message in
            DashboardChatMessage(
                id: message.id.uuidString,
                role: message.role == .user ? "user" : "assistant",
                text: message.text,
                createdAt: message.createdAt
            )
        }
        DashboardChatHistoryStore.recordSession(
            sessionId: activeChatHistorySessionId,
            messages: archivableMessages
        )
    }

    private func removeAssistantMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    /// Translates an arbitrary thrown error into a short, user-readable
    /// sentence for the error banner. We never show raw NSError dumps to
    /// the user — they're long and contain JSON the user can't act on.
    private func userFacingErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach Claude — check your internet connection and try again."
        }
        if nsError.domain == "ClaudeAPI" {
            // ClaudeAPI puts the upstream status code into `code`. 401/403
            // means the proxy rejected us; everything else we treat as a
            // generic "something went wrong".
            if nsError.code == 401 || nsError.code == 403 {
                return "The Claude proxy refused this request. The team may need to redeploy the worker."
            }
            return "Claude couldn't answer that one. Try again?"
        }
        return "Something went wrong. Try again?"
    }

    /// Converts the visible message list into the (userPlaceholder,
    /// assistantResponse) tuple format ClaudeAPI expects. Skips any
    /// assistant message that's still streaming or empty (defensive — we
    /// only call this on the *prior* turns, but the guard is cheap).
    /// Pairs are formed by walking the list and matching each user
    /// message to the next non-empty assistant message after it.
    private static func buildConversationHistory(
        from priorMessages: [ChatMessage]
    ) -> [(userPlaceholder: String, assistantResponse: String)] {
        var conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = []
        var pendingUserText: String? = nil

        for message in priorMessages {
            switch message.role {
            case .user:
                pendingUserText = message.text
            case .assistant:
                if let userText = pendingUserText, !message.text.isEmpty, !message.isStreaming {
                    conversationHistory.append(
                        (userPlaceholder: userText, assistantResponse: message.text)
                    )
                    pendingUserText = nil
                }
            }
        }

        return conversationHistory
    }
}
