//
//  ReviewCardStack.swift
//  leanring-buddy
//
//  SwiftUI surface for the post-teach-session review queue. Shows one card
//  at a time with a frame thumbnail, the question Claude is asking, and four
//  numbered options. Picking an option saves a TastePrinciple to the central
//  mind and advances the queue. Skipping discards the moment.
//
//  Click-to-pick and keyboard both work. The card-level VStack is focusable,
//  grabs focus on appear, and routes 1-4 / right-arrow / Esc through
//  .onKeyPress. Selecting "Something else" (option 4 or pressing 4) drops
//  focus into a TextField for typing a custom answer; cancelling or saving
//  there returns focus to the card so the next moment is keyboard-driven
//  too. Works because MenuBarPanelManager uses a KeyablePanel subclass that
//  overrides canBecomeKey -> true.
//

import SwiftUI

struct ReviewCardStack: View {
    @ObservedObject var companionManager: CompanionManager

    private var currentMoment: AmbiguousMoment? {
        companionManager.pendingAmbiguousMoments.first
    }

    /// Position of the current card in the review queue, ahead of the
    /// initial-queue-size lookup we don't have. We stash the original total
    /// the first time we see a non-empty queue so "X / N" stays stable as
    /// the queue drains.
    @State private var initialQueueSize: Int = 0
    @State private var cardsAlreadyAnswered: Int = 0

    /// True when the user clicked option 4 ("Something else") and we've
    /// flipped the card into custom-answer mode. The four option buttons
    /// are replaced by an inline text field + Save / Cancel actions.
    @State private var isComposingCustomAnswer: Bool = false
    @State private var customAnswerText: String = ""
    @FocusState private var isCustomAnswerFieldFocused: Bool

    /// When true, the moment thumbnail expands from the small 80pt preview
    /// to a 240pt detail view so the user can actually see what they were
    /// looking at when the moment was captured. Reset whenever the queue
    /// advances to a new moment so each card opens collapsed.
    @State private var isThumbnailExpanded: Bool = false

    /// Focus state for the card-level key catcher. Keeps a hidden focusable
    /// view focused while the option list is showing so 1-4 / arrows / Esc
    /// shortcuts route through .onKeyPress. When the user enters compose
    /// mode the text field steals focus, which is what we want — typed
    /// characters go into the field rather than triggering shortcuts.
    @FocusState private var isCardKeyCatcherFocused: Bool

    var body: some View {
        if let momentToReview = currentMoment {
            cardContent(momentToReview: momentToReview)
                .focusable(!isComposingCustomAnswer)
                .focused($isCardKeyCatcherFocused)
                .onKeyPress(phases: .down) { keyPress in
                    handleCardKeyPress(keyPress)
                }
                .onAppear {
                    if initialQueueSize == 0 {
                        initialQueueSize = companionManager.pendingAmbiguousMoments.count
                        cardsAlreadyAnswered = 0
                    }
                    // Grab focus on first appearance so the user can use
                    // 1-4 / arrows / Esc immediately. Subsequent cards
                    // reuse the same view and keep focus automatically.
                    DispatchQueue.main.async {
                        isCardKeyCatcherFocused = true
                    }
                }
                .onChange(of: companionManager.pendingAmbiguousMoments.count) { newCount in
                    // When the queue shrinks we've answered or skipped one.
                    // When it grows (a new session finishes), reset.
                    if newCount > initialQueueSize {
                        initialQueueSize = newCount
                        cardsAlreadyAnswered = 0
                    } else if newCount < initialQueueSize - cardsAlreadyAnswered {
                        cardsAlreadyAnswered += 1
                    }

                    if newCount == 0 {
                        initialQueueSize = 0
                        cardsAlreadyAnswered = 0
                    }

                    // Always exit the custom-answer compose state when we
                    // move to a new card — otherwise the text field would
                    // carry leftover text into the next moment.
                    resetCustomAnswerCompositionState()

                    // Each card opens with the small thumbnail by default —
                    // a previously-expanded image shouldn't carry over to
                    // the next moment.
                    isThumbnailExpanded = false
                }
        }
    }

    @ViewBuilder
    private func cardContent(momentToReview: AmbiguousMoment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            if let frameThumbnail = thumbnailImage(for: momentToReview.frameIndex) {
                // Thumbnail is a button so the user can click to enlarge it.
                // Keeps the small 80pt preview by default (the card is dense
                // already) and grows to 240pt for a closer look — the JPEG
                // is already in memory so toggling is free.
                Button(action: {
                    isThumbnailExpanded.toggle()
                }) {
                    frameThumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: isThumbnailExpanded ? 240 : 80)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.easeInOut(duration: 0.18), value: isThumbnailExpanded)
            }

            // Question reads as the hero of the card — bold rounded sans
            // at a generous size, lowercased to match the panel wordmark
            // and the punchy "for you / active" reference register.
            Text(momentToReview.question.lowercased())
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.95))
                .tracking(-0.4)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            if isComposingCustomAnswer {
                customAnswerComposer
            } else {
                VStack(spacing: 6) {
                    // Render the first three options as numbered pills.
                    // The 4th option from the analyzer is conventionally
                    // "Something else" — it's a different *kind* of action
                    // (opens a composer instead of saving a candidate
                    // principle) so it gets a visually distinct row below.
                    let numberedOptions = Array(momentToReview.options.prefix(3).enumerated())
                    ForEach(numberedOptions, id: \.offset) { optionIndex, optionLabel in
                        optionButton(
                            optionIndex: optionIndex,
                            optionLabel: optionLabel
                        )
                    }

                    if momentToReview.options.count >= 4 {
                        Rectangle()
                            .fill(Color(NSColor.separatorColor).opacity(0.5))
                            .frame(height: 1)
                            .padding(.vertical, 2)

                        typeMyOwnAnswerButton
                    }
                }

                keyboardHintChip

                cardFooter
            }
        }
        .padding(14)
        // Glass-on-warm card surface. The dropdown background is heavily
        // textured already, so the card stays mostly transparent and uses
        // a hairline white border to separate from the gradient instead
        // of fighting it with another fill.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var cardHeader: some View {
        HStack {
            // Tracked-out micro caption — same register as the panel's
            // "mode" / "scope" labels.
            Text("quick check — why did you do this?")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundColor(Color.white.opacity(0.50))

            Spacer()

            Text(progressLabel)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .tracking(1.5)
                .foregroundColor(Color.white.opacity(0.50))
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            // Subtle back-arrow undo. Visually quieter than skip / end so
            // it doesn't compete — it's a recovery affordance, not a
            // primary action. No-op when the undo stack is empty so users
            // can tap it harmlessly.
            Button(action: {
                companionManager.unadvanceReviewQueue()
            }) {
                Text("←")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Button(action: {
                companionManager.skipCurrentReviewMoment()
            }) {
                Text("skip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            Button(action: {
                companionManager.endReview()
            }) {
                Text("end review")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private func optionButton(optionIndex: Int, optionLabel: String) -> some View {
        Button(action: {
            companionManager.approveOption(optionIndex: optionIndex)
        }) {
            HStack(spacing: 10) {
                Text("\(optionIndex + 1)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(red: 0.16, green: 0.07, blue: 0.02))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.92))
                    )

                Text(optionLabel.lowercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Distinct "type my own answer" affordance shown below the numbered
    /// options. Visually quieter than the option pills (no surface fill,
    /// no number badge) because the action is qualitatively different —
    /// it opens the composer instead of saving a pre-baked candidate.
    private var typeMyOwnAnswerButton: some View {
        Button(action: {
            customAnswerText = ""
            isComposingCustomAnswer = true
            DispatchQueue.main.async {
                isCustomAnswerFieldFocused = true
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                Text("type my own answer")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Persistent keyboard-shortcut hint shown only while the option list
    /// is visible. Hidden in compose mode because the shortcuts don't apply
    /// there — typed characters land in the text field instead. Uses
    /// tertiary-label color so it reads as ambient guidance, not chrome.
    private var keyboardHintChip: some View {
        Text("1-3 pick · 4 type · ↑ back · → skip · Esc end")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }

    /// Inline composer shown when the user picks "Something else." Lets
    /// them phrase a one-sentence principle in their own words. Submitting
    /// (Save or Return) writes through CompanionManager.approveCustomAnswer
    /// and advances the queue.
    private var customAnswerComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("phrase the note in your own words")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundColor(Color.white.opacity(0.50))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: $customAnswerText, prompt:
                Text("e.g. i like calm, spacious layouts")
                    .foregroundColor(Color.white.opacity(0.35))
            )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .focused($isCustomAnswerFieldFocused)
                .onSubmit {
                    submitCustomAnswerIfPossible()
                }

            HStack(spacing: 8) {
                Button(action: {
                    resetCustomAnswerCompositionState()
                }) {
                    Text("cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                Button(action: {
                    submitCustomAnswerIfPossible()
                }) {
                    Text("save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.16, green: 0.07, blue: 0.02))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(canSubmitCustomAnswer
                                      ? Color.white
                                      : Color.white.opacity(0.45))
                        )
                        .shadow(color: Color.black.opacity(canSubmitCustomAnswer ? 0.15 : 0.0), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(!canSubmitCustomAnswer)
            }
        }
    }

    private var canSubmitCustomAnswer: Bool {
        !customAnswerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitCustomAnswerIfPossible() {
        guard canSubmitCustomAnswer else { return }
        companionManager.approveCustomAnswer(customAnswerText)
        // The onChange watcher on the moment count will reset compose state
        // once the queue advances, but call it explicitly here too so the
        // last card in the queue (which collapses the whole view) clears
        // cleanly without relying on that fire path.
        resetCustomAnswerCompositionState()
    }

    private func resetCustomAnswerCompositionState() {
        isComposingCustomAnswer = false
        customAnswerText = ""
        isCustomAnswerFieldFocused = false

        // After cancelling or saving a custom answer, return focus to the
        // card so 1-4 / arrows / Esc keep working on the next card without
        // the user needing to click the panel.
        DispatchQueue.main.async {
            isCardKeyCatcherFocused = true
        }
    }

    /// Routes keyboard shortcuts on the option-list view. Number keys 1-4
    /// match the visible option buttons (4 enters custom-answer mode like
    /// clicking option 4 does). Right arrow skips the moment. Esc ends the
    /// whole review. All other keys are ignored so default panel behaviour
    /// (e.g. Cmd+W to close) still works.
    private func handleCardKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Suppress shortcuts while the user is composing a custom answer —
        // typed characters should land in the text field, not trigger
        // option-pick shortcuts. The text field is focused in that mode so
        // this branch is mostly defensive.
        guard !isComposingCustomAnswer else { return .ignored }

        if keyPress.key == .escape {
            companionManager.endReview()
            return .handled
        }

        if keyPress.key == .rightArrow {
            companionManager.skipCurrentReviewMoment()
            return .handled
        }

        if keyPress.key == .upArrow {
            // Up-arrow undoes the most recent answer or skip. Safe to call
            // even when the undo stack is empty — CompanionManager no-ops
            // in that case, so an early Up-press is harmless.
            companionManager.unadvanceReviewQueue()
            return .handled
        }

        // Match the digit keys 1 through 4 against the visible options.
        // Option 4 ("Something else") opens the compose flow rather than
        // approving the muted "Other" placeholder — same behaviour as
        // clicking the 4th button.
        let digitKeyToOptionIndex: [Character: Int] = [
            "1": 0, "2": 1, "3": 2, "4": 3
        ]
        if let typedCharacter = keyPress.characters.first,
           let optionIndex = digitKeyToOptionIndex[typedCharacter] {
            if optionIndex == 3 {
                customAnswerText = ""
                isComposingCustomAnswer = true
                DispatchQueue.main.async {
                    isCustomAnswerFieldFocused = true
                }
            } else {
                companionManager.approveOption(optionIndex: optionIndex)
            }
            return .handled
        }

        return .ignored
    }

    private var progressLabel: String {
        guard initialQueueSize > 0 else { return "" }
        let currentCardNumber = cardsAlreadyAnswered + 1
        return "\(currentCardNumber) / \(initialQueueSize)"
    }

    /// Pulls the JPEG bytes for a frame index and turns them into a SwiftUI
    /// Image. Returns nil if the frame data is missing or can't be decoded —
    /// the card just renders without a thumbnail in that case.
    private func thumbnailImage(for frameIndex: Int) -> Image? {
        guard let frameData = companionManager.reviewFrameData(at: frameIndex) else { return nil }
        guard let nsImage = NSImage(data: frameData) else { return nil }
        return Image(nsImage: nsImage)
    }
}
