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
    /// JPEG screenshot captured at the moment this user message was sent,
    /// rendered inline beneath the bubble so the user can see what Sticky
    /// was looking at when answering. Nil for assistant messages and for
    /// older user messages that pre-date this feature. Populated during
    /// `runChatSend` once `CompanionScreenCaptureUtility` returns.
    var attachedScreenshotJPEG: Data?
    /// Snapshot of which persona was active when the assistant produced
    /// this reply, so the avatar shown next to the bubble doesn't change
    /// retroactively if the user switches persona afterwards. Populated
    /// for assistant messages only.
    var personaSelectionAtCreation: PersonaSelection?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        isStreaming: Bool = false,
        createdAt: Date = Date(),
        attachedScreenshotJPEG: Data? = nil,
        personaSelectionAtCreation: PersonaSelection? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.createdAt = createdAt
        self.attachedScreenshotJPEG = attachedScreenshotJPEG
        self.personaSelectionAtCreation = personaSelectionAtCreation
    }
}

@MainActor
final class ChatViewModel: ObservableObject {

    /// Same Worker proxy URL the voice flow uses. Hardcoded here rather
    /// than reaching into CompanionManager so the chat can be created
    /// before/independently of the voice manager.
    private static let workerChatProxyURL = "https://clicky-proxy.reubanramsden.workers.dev/chat"

    /// Base text rules for the chat surface. Deliberately generic — the
    /// chat is for asking questions about whatever is on screen, with
    /// less of the "spoken-word, point-at-things" framing the voice
    /// system prompt has. No `[POINT:...]` tag instructions because the
    /// chat doesn't drive the cursor overlay. The active persona's
    /// identity (soul + taste, or roleplay framing for a teammate) is
    /// composed in front of this in `composeSystemPromptForActivePersona`.
    private static let baseChatRules = """
    Each user message is accompanied by a fresh screenshot of every connected \
    display so you can see exactly what they're looking at right now. Use the \
    screenshot to answer concretely about what's on screen — refer to specific \
    UI elements, text, errors, or content visible in the image. If the user's \
    question is not about what's on screen, just answer the question normally. \
    Keep replies clear and conversational. Use markdown when it helps \
    (code blocks for code, lists for steps), but don't over-format short replies. \
    Do not output `[POINT:...]` tags or any cursor-pointing instructions — this \
    is a text chat, not a voice/cursor surface.
    """

    /// Default identity paragraph used when no teammate persona is
    /// active. Mirrors the "you're sticky" line from the voice prompt
    /// so the chat agent has a recognisable identity to fall back on.
    private static let stickyIdentityParagraph = """
    You are Sticky, a helpful AI assistant in a chat window on the user's Mac.
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
        return ClaudeAPI(proxyURL: Self.workerChatProxyURL, model: selectedModelClaudeId)
    }()

    /// Mirrors the voice flow's model preference so picking Sonnet/Opus
    /// in the menu bar panel applies to chat too. Reads the same
    /// UserDefaults key the voice path writes to. Updated by
    /// `refreshSelectedModelFromUserDefaults()` which the chat window
    /// calls each time it becomes visible.
    @Published private(set) var selectedModelClaudeId: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"

    /// In-flight send task. Cancelled if the user sends a new message
    /// before the previous response finishes streaming.
    private var currentSendTask: Task<Void, Never>?

    /// Stable id for the currently-active chat session. Each finalized
    /// assistant message overwrites the same on-disk file under this
    /// id, so the Dashboard's Chats tab shows one growing entry per
    /// chat — not a new entry per message. Reset on `startNewChat`
    /// so the next conversation starts a separate archive file.
    private var activeChatHistorySessionId: String = UUID().uuidString

    /// Weak reference to the shared CompanionManager so the chat surface
    /// can read the active persona, taste profile, and team scope at
    /// send-time. Weak because CompanionManager owns the app lifecycle —
    /// the chat view model is a leaf and must never extend it. Nil when
    /// the chat is created before CompanionManager exists (e.g. in
    /// SwiftUI previews); in that case we fall back to a generic Sticky
    /// system prompt with no persona injection.
    private weak var companionManagerForPersona: CompanionManager?

    /// Inject the shared CompanionManager so the chat can mirror voice's
    /// persona behavior. Called once by `ChatWindowController` after both
    /// objects exist. Safe to call multiple times — last write wins.
    func setCompanionManager(_ companionManager: CompanionManager) {
        companionManagerForPersona = companionManager
    }

    /// Picks up the latest model selection from UserDefaults. Called by
    /// the chat window whenever it's shown so swapping Sonnet ↔ Opus in
    /// the menu bar panel takes effect on the next chat send without
    /// needing a Combine wire-up between the two windows.
    func refreshSelectedModelFromUserDefaults() {
        let latestSelectedModel = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"
        if latestSelectedModel != selectedModelClaudeId {
            selectedModelClaudeId = latestSelectedModel
            claudeAPI.model = latestSelectedModel
        }
    }

    /// Updates the selected Claude model from the inline picker in the
    /// chat composer. Persists to the same UserDefaults key the menu bar
    /// panel + voice flow read from so all three surfaces stay in sync.
    func setSelectedModel(claudeModelId: String) {
        guard claudeModelId != selectedModelClaudeId else { return }
        selectedModelClaudeId = claudeModelId
        claudeAPI.model = claudeModelId
        UserDefaults.standard.set(claudeModelId, forKey: "selectedClaudeModel")
        // CompanionManager owns the canonical published copy of
        // selectedModel for the menu bar UI; mirror the change into it
        // when available so the footer picker reflects this picker.
        companionManagerForPersona?.setSelectedModel(claudeModelId)
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

    func cancelProtectedActivity() {
        currentSendTask?.cancel()
        currentSendTask = nil
        isResponding = false
        messages.removeAll()
        draftMessage = ""
        lastErrorMessage = nil
    }

    /// Currently active chat history session id, exposed so the chat
    /// history sidebar can highlight which session is loaded.
    var currentChatHistorySessionId: String {
        return activeChatHistorySessionId
    }

    /// Loads an archived session into the live transcript, replacing
    /// whatever was there. The chat continues writing to that session's
    /// file on disk — sending a new message extends the same archive
    /// rather than starting a fresh one — so history-sidebar resume
    /// feels continuous.
    ///
    /// Voice sessions are loaded as read-only context: the transcript
    /// shows up but the user is expected to start a new chat to continue
    /// (since voice and text are different mediums and switching mid-
    /// archive would muddle the on-disk `medium` field).
    func loadArchivedSession(_ session: DashboardChatSession) {
        currentSendTask?.cancel()
        currentSendTask = nil
        isResponding = false
        lastErrorMessage = nil

        let restoredMessages: [ChatMessage] = session.messages.map { archivedMessage in
            let restoredRole: ChatMessage.Role = (archivedMessage.role == "user") ? .user : .assistant
            return ChatMessage(
                id: UUID(uuidString: archivedMessage.id) ?? UUID(),
                role: restoredRole,
                text: archivedMessage.text,
                isStreaming: false,
                createdAt: archivedMessage.createdAt
            )
        }

        messages = restoredMessages
        // Voice sessions get a fresh id when continued from text — we
        // don't want a text reply to overwrite the voice archive's
        // `medium: "voice"` flag. Text sessions resume in place.
        if session.medium == "voice" {
            activeChatHistorySessionId = UUID().uuidString
        } else {
            activeChatHistorySessionId = session.id
        }
    }

    /// Sends the current `draftMessage`. Captures a screenshot, appends
    /// a user message + a placeholder assistant message to the list,
    /// then streams Claude's reply into the placeholder.
    func sendDraftMessage() {
        guard AuthenticationManager.shared.canAccessProductionFeatures else {
            lastErrorMessage = "Workspace setup must finish before chat is available."
            DashboardWindowController.shared.showDashboardWindow()
            return
        }

        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        guard !isResponding else { return }

        let userMessage = ChatMessage(role: .user, text: trimmedDraft)
        // Snapshot the persona at send-time so the assistant avatar
        // shown next to the reply doesn't shift if the user switches
        // persona mid-stream.
        let personaSelectionAtSendTime = companionManagerForPersona?.personaSelection
        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            text: "",
            isStreaming: true,
            personaSelectionAtCreation: personaSelectionAtSendTime
        )

        messages.append(userMessage)
        messages.append(assistantPlaceholder)
        let userMessageID = userMessage.id
        let assistantPlaceholderID = assistantPlaceholder.id

        draftMessage = ""
        lastErrorMessage = nil
        isResponding = true

        // Build the conversation history Claude needs *before* the new
        // user/assistant pair we just appended — so prior turns are
        // included as context but the current question isn't duplicated.
        let priorMessages = messages.dropLast(2)
        let conversationHistory = Self.buildConversationHistory(from: Array(priorMessages))

        // Build the persona-aware system prompt now (on the main actor)
        // so the Claude call site doesn't have to hop back to the main
        // actor to read CompanionManager state. Captured once per send;
        // mid-stream persona changes don't affect the in-flight reply.
        let composedSystemPrompt = composeSystemPromptForActivePersona()

        currentSendTask?.cancel()
        currentSendTask = Task { [weak self] in
            await self?.runChatSend(
                userText: trimmedDraft,
                userMessageID: userMessageID,
                assistantPlaceholderID: assistantPlaceholderID,
                conversationHistory: conversationHistory,
                composedSystemPrompt: composedSystemPrompt
            )
        }
    }

    /// The end-to-end chat send: capture screenshots → call Claude with
    /// streaming → write streamed text into the placeholder assistant
    /// message → mark complete (or show an error and remove the
    /// placeholder).
    private func runChatSend(
        userText: String,
        userMessageID: UUID,
        assistantPlaceholderID: UUID,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        composedSystemPrompt: String
    ) async {
        defer {
            isResponding = false
        }

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

            // Pick the screenshot to render inline beneath the user's
            // message. Prefer the screen the cursor is on so what the
            // user sees attached matches what they were looking at when
            // they hit send. Falls back to the first screen if the
            // cursor screen flag isn't set on any capture.
            let screenshotForInlineDisplay: Data? = {
                if let cursorCapture = screenCaptures.first(where: { $0.isCursorScreen }) {
                    return cursorCapture.imageData
                }
                return screenCaptures.first?.imageData
            }()
            attachScreenshotToUserMessage(
                userMessageID: userMessageID,
                screenshotJPEG: screenshotForInlineDisplay
            )

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
                systemPrompt: composedSystemPrompt,
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
        // Strip the trailing `[USED:...]` tag injected by the taste-aware
        // system prompt — chat doesn't render the applied-principles
        // chip, so the tag would just look like noise to the user.
        let (cleanedText, _) = TastePromptBuilder.parseUsedTag(
            from: messages[messageIndex].text
        )
        messages[messageIndex].text = cleanedText
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
        // Record the persona this chat was had with so the dashboard's
        // Chats tab can group sessions under their persona. Falls back
        // to `__me__` (the local user) when no companion manager is
        // wired up — happens in SwiftUI previews and very early launch.
        let personaIdForArchive: String = companionManagerForPersona
            .map { Self.personaIdForArchiving($0.personaSelection) } ?? PersonaStore.mePseudoPersona.id
        DashboardChatHistoryStore.recordSession(
            sessionId: activeChatHistorySessionId,
            messages: archivableMessages,
            personaId: personaIdForArchive,
            medium: "text"
        )
    }

    /// Translates the in-memory `PersonaSelection` enum into the flat
    /// string id used by the on-disk session JSON. Mirrors the wheel's
    /// id convention so a session archived under `"reuban"` or
    /// `"__team__"` lines up with whatever `PersonaStore` returns at
    /// read time.
    private static func personaIdForArchiving(_ selection: PersonaSelection) -> String {
        switch selection {
        case .me: return PersonaStore.mePseudoPersona.id
        case .team: return PersonaStore.teamPseudoPersona.id
        case .teammate(let id): return id
        }
    }

    private func removeAssistantMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    /// Stores the captured cursor-screen JPEG on the user message so the
    /// view can render it inline as a thumbnail under the bubble. Called
    /// from `runChatSend` once the screen-capture utility returns.
    private func attachScreenshotToUserMessage(userMessageID: UUID, screenshotJPEG: Data?) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == userMessageID }) else { return }
        messages[messageIndex].attachedScreenshotJPEG = screenshotJPEG
    }

    // MARK: - Persona-aware system prompt

    /// Composes the system prompt for the chat send. Mirrors voice's
    /// behavior:
    /// - When a teammate persona is active, prepend the roleplay framing
    ///   header + the teammate's `soul` + their bundled taste principles.
    ///   The default Sticky identity paragraph is dropped so the model
    ///   doesn't fight the persona.
    /// - When `.me` / `.team` is active, use the Sticky identity paragraph
    ///   plus the user's saved taste profile (and team profile when scope
    ///   is `.team`) as judgment context.
    /// - When `companionManagerForPersona` is nil (e.g. previews), fall
    ///   back to the bare Sticky identity + base rules.
    ///
    /// All variants append `baseChatRules` so the chat-specific format
    /// guidance (markdown, no `[POINT:...]` tags, screenshot framing) is
    /// always present regardless of persona.
    private func composeSystemPromptForActivePersona() -> String {
        if let companionManager = companionManagerForPersona {
            if let teammateBundle = companionManager.activeTeammateBundle {
                return composeSystemPromptForTeammatePersona(teammateBundle: teammateBundle)
            }
            return composeSystemPromptForOwnerPersona(companionManager: companionManager)
        }
        return Self.stickyIdentityParagraph + "\n\n" + Self.baseChatRules
    }

    /// Builds the chat system prompt when the user is wearing a teammate's
    /// persona. Mirrors `CompanionManager.composeSystemPromptForTeammatePersona`
    /// — same roleplay framing, same soul + taste injection — adapted for
    /// the chat surface (no pointing tags, markdown encouraged).
    private func composeSystemPromptForTeammatePersona(teammateBundle: PersonaBundle) -> String {
        let teammateTasteContextBlock = TastePromptBuilder.tasteContextBlock(
            personalProfile: teammateBundle.taste,
            teamProfile: nil,
            scope: .personal
        )

        let roleplayFramingHeader = """
        you are roleplaying as \(teammateBundle.displayName) — \(teammateBundle.role ?? "teammate"). this is not a character you reference, it's the identity you fully inhabit for this entire conversation.

        embody them completely: their tone, cadence, vocabulary, opinions, areas of expertise, blind spots, and quirks. speak as them in the first person. when the user asks who you are, who they're talking to, what your name is, or what you do, answer in-character — give your name (\(teammateBundle.displayName)), your role (\(teammateBundle.role ?? "teammate")), and a sentence or two of context that fits the personality below. do not say you are sticky, do not say you are an ai, do not break character. if asked something \(teammateBundle.displayName) wouldn't know about, react the way they would — curious, dismissive, deflecting to their own expertise — rather than refusing.

        the personality, voice, and values you should emulate are described next.
        """

        var promptSections: [String] = [roleplayFramingHeader]

        if !teammateBundle.soul.isEmpty {
            promptSections.append(teammateBundle.soul)
        }

        if !teammateTasteContextBlock.isEmpty {
            promptSections.append(teammateTasteContextBlock)
        }

        // Every teammate is part of the same team, so they all get the
        // team brief + dropped files as background context. Mirrors the
        // voice flow in CompanionManager.composeSystemPromptForTeammatePersona.
        let teamContextOverviewBlock = TeamContextPromptBuilder
            .teamContextBlock(profile: TeamContextStore.loadProfile())
        if !teamContextOverviewBlock.isEmpty {
            promptSections.append(teamContextOverviewBlock)
        }

        promptSections.append("stay fully in character as \(teammateBundle.displayName) for every reply. the rules below are about response format (length, register, markdown) — apply them through \(teammateBundle.displayName)'s voice, not by reverting to a generic assistant.")

        promptSections.append(Self.baseChatRules)

        return promptSections.joined(separator: "\n\n")
    }

    /// Builds the chat system prompt when persona is `.me` or `.team`.
    /// Uses the user's own taste profile from disk (preferring TASTE.md,
    /// falling back to the legacy JSON store) and unions in the team
    /// profile when scope is `.team`. Stays as Sticky — no roleplay
    /// framing — but grounds replies in the saved principles.
    private func composeSystemPromptForOwnerPersona(companionManager: CompanionManager) -> String {
        let identitySection = Self.stickyIdentityParagraph

        // Prefer the owner's TASTE.md so freshly-taught principles show
        // up in chat without an app restart, mirroring the voice flow.
        let loadedPersonalProfile: TasteProfile? = {
            if let ownerBundle = PersonaStore.myCurrentBundle() {
                return ownerBundle.taste
            }
            return try? TasteProfileStore.loadProfile()
        }()

        guard let personalProfile = loadedPersonalProfile else {
            return identitySection + "\n\n" + Self.baseChatRules
        }

        let activeScope = companionManager.tasteScope
        let loadedTeamProfile: TeamTasteProfile? = (activeScope == .team)
            ? TeamTasteProfileStore.loadTeamProfile()
            : nil

        let tasteContextBlock = TastePromptBuilder.buildTasteContextBlock(
            personalProfile: personalProfile,
            teamProfile: loadedTeamProfile,
            scope: activeScope
        )

        // Team context (brief + files) is only injected when the user is
        // operating in team scope. Personal scope stays clean — this
        // matches the voice flow in CompanionManager.
        let teamContextOverviewBlock: String = (activeScope == .team)
            ? TeamContextPromptBuilder.teamContextBlock(profile: TeamContextStore.loadProfile())
            : ""

        if tasteContextBlock.promptText.isEmpty && teamContextOverviewBlock.isEmpty {
            return identitySection + "\n\n" + Self.baseChatRules
        }

        return [identitySection, teamContextOverviewBlock, tasteContextBlock.promptText, Self.baseChatRules]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
