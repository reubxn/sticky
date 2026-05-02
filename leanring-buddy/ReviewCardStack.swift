//
//  ReviewCardStack.swift
//  leanring-buddy
//
//  SwiftUI surface for the post-teach-session review queue. Shows one card
//  at a time with a frame thumbnail, the question Claude is asking, and four
//  numbered options. Picking an option saves a TastePrinciple to the central
//  mind and advances the queue. Skipping discards the moment.
//
//  Hackathon MVP: click-to-pick only. Keyboard 1-4 / arrows can be wired up
//  later — menu bar panels don't take key focus by default and adding a
//  global event monitor for this is more code than it's worth right now.
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

    var body: some View {
        if let momentToReview = currentMoment {
            cardContent(momentToReview: momentToReview)
                .onAppear {
                    if initialQueueSize == 0 {
                        initialQueueSize = companionManager.pendingAmbiguousMoments.count
                        cardsAlreadyAnswered = 0
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
                }
        }
    }

    @ViewBuilder
    private func cardContent(momentToReview: AmbiguousMoment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            if let frameThumbnail = thumbnailImage(for: momentToReview.frameIndex) {
                frameThumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }

            Text(momentToReview.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                ForEach(Array(momentToReview.options.enumerated()), id: \.offset) { optionIndex, optionLabel in
                    optionButton(
                        optionIndex: optionIndex,
                        optionLabel: optionLabel
                    )
                }
            }

            cardFooter
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private var cardHeader: some View {
        HStack {
            Text("Review what I noticed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))

            Spacer()

            Text(progressLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Button(action: {
                companionManager.skipCurrentReviewMoment()
            }) {
                Text("Skip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            Button(action: {
                companionManager.endReview()
            }) {
                Text("End review")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private func optionButton(optionIndex: Int, optionLabel: String) -> some View {
        // The 4th option is conventionally "Something else" — we keep that
        // visual but for hackathon MVP it just saves the 4th candidate
        // principle, which the analyzer prompt fills with a low-confidence
        // generic "Other" stub. Typing a custom answer is a follow-up.
        let isCustomOption = optionIndex == 3

        return Button(action: {
            companionManager.approveOption(optionIndex: optionIndex)
        }) {
            HStack(spacing: 8) {
                Text("\(optionIndex + 1)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isCustomOption
                                  ? Color(NSColor.tertiaryLabelColor)
                                  : Color.accentColor)
                    )

                Text(optionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
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
