//
//  ChatView.swift
//  leanring-buddy
//
//  Centered, ChatGPT-style chat surface. When the transcript is empty
//  the composer sits in the middle of the window under a "Ready when
//  you are." headline. Once the conversation starts, the composer drops
//  to the bottom and the transcript fills the space above it. The
//  composer is a rounded-rectangle box that contains the text input,
//  inline model picker, and a send button — all wired into the same
//  shared model selection that the voice flow uses.
//
//  Each user message silently attaches a fresh screenshot of every
//  connected display before being sent (in `ChatViewModel.sendDraftMessage`).
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel

    /// Whether to render the editorial top strip ("Chat" eyebrow +
    /// "New chat" button). The dashboard embeds this view alongside a
    /// chat-history sidebar that already exposes a New chat affordance,
    /// so the strip is suppressed there. The standalone floating chat
    /// window keeps it on so it has somewhere to start a fresh chat.
    var showsHeader: Bool = true

    /// Drives the inline model-picker popover anchored on the composer.
    /// Using a custom popover (instead of SwiftUI's native `Menu`) lets
    /// the dropdown match the brand-styled persona/theme pickers used
    /// elsewhere in the app — paper card surface, hairline, hover wash.
    @State private var isModelPickerPresented: Bool = false

    /// Avatar to render next to assistant replies that didn't capture a
    /// persona snapshot (e.g. older messages, or replies sent before
    /// CompanionManager was wired in). Falls back to the `.me` pseudo-
    /// persona avatar so the chat still shows a face. Computed once per
    /// view body to avoid the synchronous PersonaStore lookup churning
    /// while the user types.
    private var defaultAssistantAvatar: PersonaAvatar {
        return PersonaStore.mePseudoPersona.avatar
    }

    private var isTranscriptEmpty: Bool {
        chatViewModel.messages.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Paper background — extends edge-to-edge so the window has the
            // off-white "printed page" feel the brand calls for.
            ElevenLabsBrand.Colors.paper
                .ignoresSafeArea()

            if isTranscriptEmpty {
                centeredHeroLayout
            } else {
                activeChatLayout
            }
        }
        .frame(minWidth: 600, minHeight: 560)
    }

    // MARK: - Empty-state centered layout

    /// Empty-state layout — a vertically centered "Ready when you are."
    /// headline with the composer pill directly underneath and a row of
    /// suggestion chips below it. Mirrors the ChatGPT-style "box in the
    /// middle" composition the user asked for.
    private var centeredHeroLayout: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Spacer()
                    newChatButton
                }
                .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                .padding(.top, ElevenLabsBrand.Spacing.md)
            }

            Spacer()

            VStack(spacing: ElevenLabsBrand.Spacing.lg) {
                Text("Ready when you are.")
                    .font(ElevenLabsBrand.Typography.hero(size: 36))
                    .tracking(-0.5)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                composerStack
                    .frame(maxWidth: 720)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ElevenLabsBrand.Spacing.lg)

            if let errorMessage = chatViewModel.lastErrorMessage {
                errorBanner(errorMessage: errorMessage)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                    .padding(.top, ElevenLabsBrand.Spacing.md)
            }

            Spacer()
        }
    }

    // MARK: - Active-chat layout

    /// Active-chat layout — header strip, scrollable transcript, and the
    /// composer pinned to the bottom. The composer is the same view used
    /// in the empty state, just docked below the transcript.
    private var activeChatLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if showsHeader {
                    chatHeader
                }
                transcriptScrollArea
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 110)
                    }
            }

            composerStack
                .frame(maxWidth: 720)
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.bottom, ElevenLabsBrand.Spacing.md)
        }
    }

    // MARK: - Header

    /// Editorial-style header: a "Chat" eyebrow on the left and a single
    /// ghost "new chat" icon-button on the right. No background fill — the
    /// header sits directly on the paper and is separated from content
    /// only by a hairline rule.
    private var chatHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                Text("Chat")
                    .font(ElevenLabsBrand.Typography.eyebrow)
                    .tracking(0.2)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

                Spacer()

                newChatButton
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
            .padding(.vertical, ElevenLabsBrand.Spacing.md)

            Rectangle()
                .fill(ElevenLabsBrand.Colors.hairline)
                .frame(height: 1)
        }
    }

    private var newChatButton: some View {
        Button(action: {
            chatViewModel.startNewChat()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                Text("New chat")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                Capsule().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Clear the current conversation and start fresh")
    }

    // MARK: - Transcript

    private var transcriptScrollArea: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
                    ForEach(chatViewModel.messages) { message in
                        ChatMessageCard(
                            message: message,
                            fallbackAssistantAvatar: defaultAssistantAvatar
                        )
                            .id(message.id)
                    }

                    if let errorMessage = chatViewModel.lastErrorMessage {
                        errorBanner(errorMessage: errorMessage)
                    }

                    // Invisible anchor at the very bottom so we can
                    // scrollTo it whenever a new message lands or the
                    // streaming text grows.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollAnchorID)
                }
                .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                .padding(.top, ElevenLabsBrand.Spacing.md)
                .padding(.bottom, ElevenLabsBrand.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: chatViewModel.messages.count) { _ in
                scrollTranscriptToBottom(scrollViewProxy: scrollViewProxy)
            }
            // While streaming, the message count is stable but the last
            // message's text is growing — re-scroll on text changes too
            // so the user sees the response unfurl at the bottom.
            .onChange(of: chatViewModel.messages.last?.text ?? "") { _ in
                scrollTranscriptToBottom(scrollViewProxy: scrollViewProxy)
            }
        }
    }

    private static let scrollAnchorID = "chat-bottom-anchor"

    private func scrollTranscriptToBottom(scrollViewProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            scrollViewProxy.scrollTo(Self.scrollAnchorID, anchor: .bottom)
        }
    }

    // MARK: - Error banner

    private func errorBanner(errorMessage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.gradientCoral)
                .padding(.top, 2)
            Text(errorMessage)
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.gradientCoral.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.gradientCoral.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Composer pill

    private var composerStack: some View {
        composerPill
    }

    /// The single rounded pill that holds every input control: the
    /// multi-line text input, an inline model picker, and either a
    /// circular send button (when the user has typed something) or
    /// a "thinking" indicator (while responding).
    private var composerPill: some View {
        HStack(alignment: .center, spacing: 8) {
            ChatComposerTextEditor(
                text: $chatViewModel.draftMessage,
                onSubmit: {
                    chatViewModel.sendDraftMessage()
                }
            )
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomLeading) {
                if chatViewModel.draftMessage.isEmpty {
                    Text("Ask anything")
                        .font(.system(size: 14))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                        // Sit clear of the NSTextView caret. The text view has
                        // a 2pt container inset, so the caret renders ~2pt in;
                        // pad enough to leave the caret visible on its own.
                        .padding(.leading, 10)
                        // Match the NSTextView's 6pt bottom container inset so
                        // the placeholder baseline lines up with the bottom of
                        // the blinking caret.
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                }
            }

            inlineModelPicker

            if chatViewModel.isResponding {
                thinkingIndicator
            } else if !chatViewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    /// Inline model picker rendered as `Balanced ▾`-style text. Reuses
    /// `ModelPickerKind` so the menu stays in sync with the menu bar
    /// panel and dashboard settings — the selected model
    /// UserDefaults value is the source of truth. Popover surface
    /// matches the brand persona/theme dropdowns elsewhere in the app
    /// (paper card, hairline, paper-recessed hover wash).
    private var inlineModelPicker: some View {
        let currentModelKind = ModelPickerKind.fromModelId(chatViewModel.selectedModelId)

        return Button(action: { isModelPickerPresented.toggle() }) {
            HStack(spacing: 4) {
                Text(currentModelKind.shortLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .pointerCursor()
        .help("Change which AI model answers")
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .top) {
            modelPickerPopoverContent
        }
    }

    /// Body of the model-picker popover. One row per model, each with
    /// the shape glyph + long label + one-line descriptor. Selected row
    /// gets a trailing checkmark. Mirrors `ThemePickerPopoverRow` in
    /// CompanionPanelView so the two pickers feel like the same control.
    private var modelPickerPopoverContent: some View {
        let currentModelKind = ModelPickerKind.fromModelId(chatViewModel.selectedModelId)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(ModelPickerKind.allCases, id: \.self) { modelKind in
                ModelPickerPopoverRow(
                    modelKind: modelKind,
                    isSelected: currentModelKind == modelKind,
                    onSelect: {
                        chatViewModel.setSelectedModel(modelId: modelKind.modelId)
                        isModelPickerPresented = false
                    }
                )
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(ElevenLabsBrand.Colors.card)
    }

    /// Send button — replaces the voice button when the user has typed
    /// something. Inline circular ink button so it lives inside the pill
    /// rather than as a separate element.
    private var sendButton: some View {
        Button(action: {
            chatViewModel.sendDraftMessage()
        }) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ElevenLabsBrand.Colors.paper)
                .frame(width: 32, height: 32)
                .background(Circle().fill(ElevenLabsBrand.Colors.inkPure))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .pointerCursor()
        .help("Send (⌘+Return)")
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            StickyThinkingOrb(diameter: 14)
            Text("Thinking…")
                .font(ElevenLabsBrand.Typography.caption)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Message Card

/// One message in the transcript. User messages are right-aligned ink
/// cards (black fill, white text), with the screenshot Sticky saw at
/// send-time rendered underneath the bubble so the user can see exactly
/// what the model was looking at. Assistant messages are left-aligned
/// paper cards prefixed by the active persona's circular avatar — no
/// generic ElevenLabs wordmark — so it always reads as "the persona is
/// the one talking", matching the voice surface.
private struct ChatMessageCard: View {
    let message: ChatMessage
    /// Avatar to fall back on when the assistant message has no persona
    /// snapshot (older messages from before persona-aware chat landed).
    let fallbackAssistantAvatar: PersonaAvatar

    @ObservedObject private var authenticationManager = AuthenticationManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
            switch message.role {
            case .user:
                Spacer(minLength: 60)
                userCardWithScreenshot
            case .assistant:
                assistantPersonaAvatar
                assistantCard
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: User

    /// User bubble plus the captured screenshot rendered as a thumbnail
    /// directly underneath. The two are stacked so they appear visually
    /// linked (this message → these are the pixels Sticky saw). The
    /// screenshot is omitted when no capture is attached — older
    /// messages or sends where the capture failed shouldn't show a
    /// broken empty frame.
    private var userCardWithScreenshot: some View {
        VStack(alignment: .trailing, spacing: 6) {
            userCard
            if let screenshotJPEG = message.attachedScreenshotJPEG,
               let nsImage = NSImage(data: screenshotJPEG) {
                attachedScreenshotThumbnail(nsImage: nsImage)
            }
        }
        .frame(maxWidth: 460, alignment: .trailing)
    }

    private var userCard: some View {
        Text(message.text)
            .font(ElevenLabsBrand.Typography.body)
            .foregroundColor(ElevenLabsBrand.Colors.paper)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, ElevenLabsBrand.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.inkPure)
            )
    }

    /// Thumbnail of the screenshot Sticky saw when this message was
    /// sent. Width is capped to match the bubble; height is derived
    /// from the image's true aspect ratio so wide displays, ultrawides,
    /// and portrait monitors all render at correct proportions without
    /// being cropped or letterboxed.
    private func attachedScreenshotThumbnail(nsImage: NSImage) -> some View {
        let imagePixelSize = nsImage.size
        let aspectRatio: CGFloat = {
            guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return 16.0 / 9.0 }
            return imagePixelSize.width / imagePixelSize.height
        }()

        return Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: 460, alignment: .trailing)
            .clipShape(RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
    }

    // MARK: Assistant

    /// Circular avatar of the persona who produced this reply. Resolves
    /// from `personaSelectionAtCreation` when set so the avatar is
    /// stable per-message even after the user switches persona; falls
    /// back to whatever avatar the chat view passed in when the
    /// snapshot is missing.
    private var assistantPersonaAvatar: some View {
        PersonaAvatarView(
            avatar: resolvedAssistantAvatar,
            diameter: 28,
            uploadedImageOverridePath: resolvedAssistantUploadedImagePath
        )
        .padding(.top, 4)
    }

    private var resolvedAssistantAvatar: PersonaAvatar {
        if let personaSelection = message.personaSelectionAtCreation,
           let wheelPersona = PersonaStore.wheelPersonaForSelection(personaSelection) {
            return wheelPersona.avatar
        }
        return fallbackAssistantAvatar
    }

    private var resolvedAssistantUploadedImagePath: String? {
        if let personaSelection = message.personaSelectionAtCreation,
           let wheelPersona = PersonaStore.wheelPersonaForSelection(personaSelection) {
            return PersonaStore.uploadedProfilePicturePath(forPersonaId: wheelPersona.id)
        }
        return PersonaStore.uploadedProfilePicturePath(forPersonaId: PersonaStore.mePseudoPersona.id)
    }

    @ViewBuilder
    private var assistantCard: some View {
        if message.text.isEmpty && message.isStreaming {
            streamingPlaceholder
        } else {
            ChatMarkdownView(markdownText: message.text)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.vertical, ElevenLabsBrand.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                        .fill(ElevenLabsBrand.Colors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                        .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                )
        }
    }

    private var streamingPlaceholder: some View {
        HStack(spacing: 10) {
            StickyThinkingOrb(diameter: 18)
            Text("Thinking…")
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, ElevenLabsBrand.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Model Picker Popover Row
//
// Single row inside the composer's model popover: glyph + long label +
// one-line descriptor + (when active) a trailing checkmark. Hovering
// fills the row with a paper-recessed wash so the click target is
// obvious. Visually matches `ThemePickerPopoverRow` in CompanionPanelView
// so the brand dropdowns feel like one control.

private struct ModelPickerPopoverRow: View {
    let modelKind: ModelPickerKind
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text(modelKind.glyphCharacter)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(modelKind.longLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)

                    Text(modelKind.descriptor)
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? ElevenLabsBrand.Colors.paperRecessed : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Composer text editor

/// NSViewRepresentable wrapping NSTextView so we can intercept Return
/// (send) vs. Shift+Return (newline) ourselves. SwiftUI's TextField is
/// single-line and SwiftUI's TextEditor doesn't give us a clean hook to
/// distinguish those two key events on macOS.
private struct ChatComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(ElevenLabsBrand.Colors.ink)
        textView.insertionPointColor = NSColor(ElevenLabsBrand.Colors.ink)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Avoid clobbering the user's caret position when the binding
        // mirrors back the same string we just emitted from the editor.
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        /// Intercepts Return to send (without modifiers) and lets
        /// Shift+Return fall through to insert a newline.
        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
                if modifierFlags.contains(.shift) {
                    // Shift+Return → newline (default behavior)
                    return false
                }
                // Plain Return → send
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Sticky thinking orb

/// Animated Sticky-logo silhouette used in place of a stock spinner while
/// the assistant is generating a reply. Matches the menu-bar icon shape
/// (round top, flat base — the "sticky orb"), and adds two layered
/// animations so the indicator reads as the app actively thinking rather
/// than a generic loading state:
///   1. A vertical bob (the orb lifts off its flat base).
///   2. A subtle squash on landing (the orb compresses against the base).
/// The shape is drawn from scratch so it looks crisp at any size and
/// stays in sync with the existing menu-bar Sticky silhouette.
private struct StickyThinkingOrb: View {
    let diameter: CGFloat

    @State private var animationPhase: Double = 0

    var body: some View {
        // The orb itself. Drawn in the brand "ink" so the silhouette
        // matches the menu-bar icon's filled-black look on the light
        // chat surface.
        StickyOrbShape()
            .fill(ElevenLabsBrand.Colors.ink)
            .frame(width: diameter, height: diameter)
            .scaleEffect(x: squashX, y: squashY, anchor: .bottom)
            .offset(y: bobOffset)
            .frame(width: diameter * 1.6, height: diameter * 1.6)
            .onAppear {
                // One continuous, autoreversing easeInOut animation drives
                // every derived value below. Using a single phase keeps the
                // squash/bob perfectly in sync without juggling multiple
                // timers.
                withAnimation(
                    .easeInOut(duration: 0.85)
                        .repeatForever(autoreverses: true)
                ) {
                    animationPhase = 1
                }
            }
    }

    // animationPhase: 0 = resting on base (squashed)
    //                 1 = floating at peak (slightly stretched)

    private var bobOffset: CGFloat {
        // Negative y = up. Bob travels ~25% of the diameter.
        -CGFloat(animationPhase) * diameter * 0.25
    }

    private var squashX: CGFloat {
        // At rest: 1.08 (squashed wider). At peak: 0.96 (stretched taller).
        1.08 - 0.12 * CGFloat(animationPhase)
    }

    private var squashY: CGFloat {
        // Inverse of squashX so volume reads as roughly preserved.
        0.92 + 0.12 * CGFloat(animationPhase)
    }
}

