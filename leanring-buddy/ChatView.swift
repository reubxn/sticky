//
//  ChatView.swift
//  leanring-buddy
//
//  Editorial-style chat surface using the ElevenLabs brand system.
//  Paper background, white message cards on paper, a hero gradient tile
//  for the empty state, and a floating pill composer with a black-pill
//  primary CTA. Replaces the earlier bubble-on-system-material layout.
//
//  Each user message silently attaches a fresh screenshot of every
//  connected display before being sent (in `ChatViewModel.sendDraftMessage`).
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Paper background — extends edge-to-edge so the window has the
            // off-white "printed page" feel the brand calls for.
            ElevenLabsBrand.Colors.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader

                transcriptScrollArea
                    // Bottom inset reserves space for the floating composer
                    // so the last message never sits directly under it.
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 96)
                    }
            }

            floatingComposer
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.bottom, ElevenLabsBrand.Spacing.md)
        }
        .frame(minWidth: 540, minHeight: 560)
    }

    // MARK: - Header

    /// Editorial-style header: wordmark on the left, a single ghost
    /// "new chat" icon-button on the right. No background fill — the
    /// header sits directly on the paper and is separated from content
    /// only by a hairline rule.
    private var chatHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                ElevenLabsWordmark(size: 16)

                Text("Chat")
                    .font(ElevenLabsBrand.Typography.eyebrow)
                    .tracking(0.2)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.leading, ElevenLabsBrand.Spacing.xs)

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
                    if chatViewModel.messages.isEmpty {
                        emptyStateHero
                            .padding(.top, ElevenLabsBrand.Spacing.lg)
                    } else {
                        ForEach(chatViewModel.messages) { message in
                            ChatMessageCard(message: message)
                                .id(message.id)
                        }
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

    // MARK: - Empty state

    /// Hero-style empty state — a gradient tile with an eyebrow + display
    /// headline that mirrors the ElevenLabs landing-page rhythm. Replaces
    /// the previous tiny SF Symbol + two paragraphs.
    private var emptyStateHero: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            ElevenLabsGradientTile(gradient: ElevenLabsBrand.Gradients.skyBlush) {
                VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                    Spacer(minLength: 0)
                    ElevenLabsEyebrow("AI COMPANION")
                        .foregroundColor(.white.opacity(0.85))

                    Text("Ask about anything\non your screen.")
                        .font(ElevenLabsBrand.Typography.hero(size: 30))
                        .tracking(-0.5)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ElevenLabsBrand.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 220)

            HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen attached automatically")
                        .font(ElevenLabsBrand.Typography.bodyStrong)
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text("Every message includes a fresh screenshot of all your displays so the model can see what you're looking at.")
                        .font(ElevenLabsBrand.Typography.body)
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(ElevenLabsBrand.Spacing.md)
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

    // MARK: - Composer

    /// The composer floats above the transcript as a self-contained card.
    /// Editor on the left, "Send" pill on the right (or a thinking indicator
    /// while streaming). The screenshot disclosure has been moved into the
    /// empty state so the composer stays focused on input.
    private var floatingComposer: some View {
        HStack(alignment: .bottom, spacing: ElevenLabsBrand.Spacing.sm) {
            ChatComposerTextEditor(text: $chatViewModel.draftMessage, onSubmit: {
                chatViewModel.sendDraftMessage()
            })
            .frame(minHeight: 32, maxHeight: 120)

            if chatViewModel.isResponding {
                thinkingIndicator
            } else {
                Button(action: {
                    chatViewModel.sendDraftMessage()
                }) {
                    HStack(spacing: 6) {
                        Text("Send")
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSendDisabled)
                .opacity(isSendDisabled ? 0.4 : 1.0)
            }
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
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    private var isSendDisabled: Bool {
        chatViewModel.isResponding
            || chatViewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            Text("Thinking…")
                .font(ElevenLabsBrand.Typography.caption)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(ElevenLabsBrand.Colors.paperRecessed))
        .overlay(Capsule().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1))
    }
}

// MARK: - Message Card

/// One message in the transcript. User messages are right-aligned ink
/// cards (black fill, white text). Assistant messages are left-aligned
/// paper cards prefixed with the "II" wordmark mark, so the brand
/// identity is implicit in every reply without a "Sticky" role label
/// taking up vertical space.
private struct ChatMessageCard: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
            switch message.role {
            case .user:
                Spacer(minLength: 60)
                userCard
            case .assistant:
                assistantMark
                assistantCard
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: User

    private var userCard: some View {
        Text(message.text)
            .font(ElevenLabsBrand.Typography.body)
            .foregroundColor(ElevenLabsBrand.Colors.onAccent)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, ElevenLabsBrand.Spacing.sm)
            .frame(maxWidth: 460, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.inkPure)
            )
    }

    // MARK: Assistant

    /// Two short vertical bars matching the "II" of the wordmark. Sits to
    /// the left of every assistant card as the brand identity for the
    /// reply — no explicit "Sticky" label needed.
    private var assistantMark: some View {
        HStack(spacing: 2) {
            Capsule()
                .fill(ElevenLabsBrand.Colors.inkPure)
                .frame(width: 3, height: 14)
            Capsule()
                .fill(ElevenLabsBrand.Colors.inkPure)
                .frame(width: 3, height: 14)
        }
        .padding(.top, 14)
        .padding(.leading, 2)
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
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
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
