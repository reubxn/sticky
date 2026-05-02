//
//  TeachSessionResultCard.swift
//  leanring-buddy
//
//  Pre-save review card shown in the menu bar panel after a teach session
//  finishes analyzing. Lets the user see what Sticky pulled out and choose
//  what to keep before anything hits disk. Until the user clicks Save,
//  taste-profile.json is untouched. Discard wipes the analyzer output
//  entirely with no disk write.
//

import SwiftUI

struct TeachSessionResultCard: View {
    @ObservedObject var companionManager: CompanionManager
    let pendingReview: PendingTeachSessionReview

    /// Which confident principle ids the user has currently checked. Defaults
    /// to all of them on appear so "Save selected" matches the implicit
    /// expectation that everything Claude was confident about gets kept
    /// unless the user explicitly opts out.
    @State private var selectedConfidentPrincipleIds: Set<String> = []

    /// True once we've initialized `selectedConfidentPrincipleIds` from the
    /// incoming pending result. Stops `onAppear` from re-checking everything
    /// every time SwiftUI re-evaluates the view body.
    @State private var hasInitializedSelectionForPendingReview: Bool = false

    private var confidentPrinciples: [TastePrinciple] {
        pendingReview.result.confident
    }

    private var ambiguousMomentCount: Int {
        pendingReview.result.ambiguous.count
    }

    /// True when the pending result has nothing actionable. Card collapses
    /// to a single "I couldn't pull anything out" message with one button.
    private var isResultEmpty: Bool {
        confidentPrinciples.isEmpty && ambiguousMomentCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            if isResultEmpty {
                emptyResultBody
            } else {
                if !confidentPrinciples.isEmpty {
                    confidentPrinciplesChecklist
                }
                if ambiguousMomentCount > 0 {
                    ambiguousFollowupHint
                }
                cardActions
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(WarmPalette.surfaceTint.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(WarmPalette.separator, lineWidth: 0.5)
        )
        .onAppear {
            if !hasInitializedSelectionForPendingReview {
                selectedConfidentPrincipleIds = Set(confidentPrinciples.map { $0.id })
                hasInitializedSelectionForPendingReview = true
            }
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            Text(isResultEmpty ? "Nothing landed" : "Here's what I learned")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(WarmPalette.textPrimary)

            Spacer()

            if !isResultEmpty {
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WarmPalette.textTertiary)
            }
        }
    }

    private var headerSubtitle: String {
        let confidentCount = confidentPrinciples.count
        switch (confidentCount, ambiguousMomentCount) {
        case (0, let ambiguous):
            return "\(ambiguous) to talk about"
        case (let confident, 0):
            return "\(confident) confident"
        case (let confident, let ambiguous):
            return "\(confident) confident · \(ambiguous) to talk about"
        }
    }

    // MARK: - Empty result

    private var emptyResultBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I couldn't pull anything out of that one. Try narrating more concretely — say WHY you're making each change.")
                .font(.system(size: 11))
                .foregroundColor(WarmPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                primaryActionButton(label: "OK") {
                    companionManager.discardTeachSessionResult()
                }
            }
        }
    }

    // MARK: - Confident principles checklist

    private var confidentPrinciplesChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(confidentPrinciples) { confidentPrinciple in
                confidentPrincipleRow(confidentPrinciple: confidentPrinciple)
            }
        }
    }

    private func confidentPrincipleRow(confidentPrinciple: TastePrinciple) -> some View {
        let isSelected = selectedConfidentPrincipleIds.contains(confidentPrinciple.id)
        return Button(action: {
            toggleSelection(forPrincipleId: confidentPrinciple.id)
        }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? WarmPalette.accent : WarmPalette.textTertiary)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(confidentPrinciple.domain.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(WarmPalette.textPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(WarmPalette.accent.opacity(0.35))
                            )

                        Text(confidentPrinciple.statement)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(WarmPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }

                    if let firstEvidenceLine = confidentPrinciple.evidence.first,
                       !firstEvidenceLine.isEmpty {
                        Text(firstEvidenceLine)
                            .font(.system(size: 10))
                            .foregroundColor(WarmPalette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(isSelected
                          ? WarmPalette.surfaceTintStrong
                          : WarmPalette.surfaceTint.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(WarmPalette.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func toggleSelection(forPrincipleId principleId: String) {
        if selectedConfidentPrincipleIds.contains(principleId) {
            selectedConfidentPrincipleIds.remove(principleId)
        } else {
            selectedConfidentPrincipleIds.insert(principleId)
        }
    }

    // MARK: - Ambiguous follow-up hint

    private var ambiguousFollowupHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(WarmPalette.textTertiary)
            Text("+ \(ambiguousMomentCount) moment\(ambiguousMomentCount == 1 ? "" : "s") I'm not sure about — I'll ask after you save.")
                .font(.system(size: 10))
                .foregroundColor(WarmPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
    }

    // MARK: - Actions

    private var cardActions: some View {
        HStack(spacing: 6) {
            Button(action: {
                companionManager.discardTeachSessionResult()
            }) {
                Text("Discard session")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WarmPalette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(WarmPalette.separator, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            primaryActionButton(label: saveButtonLabel) {
                companionManager.confirmTeachSessionSave(
                    selectedConfidentPrincipleIds: selectedConfidentPrincipleIds
                )
            }
            .opacity(isSaveButtonEnabled ? 1.0 : 0.5)
            .disabled(!isSaveButtonEnabled)
        }
        .padding(.top, 4)
    }

    /// Save is enabled whenever there's anything for it to do — at least one
    /// confident principle checked, or any ambiguous moments to promote
    /// into the review queue. Disabled when both are zero so the button
    /// doesn't lie about its effect.
    private var isSaveButtonEnabled: Bool {
        !selectedConfidentPrincipleIds.isEmpty || ambiguousMomentCount > 0
    }

    /// Label the Save button so the user knows what's about to happen.
    /// "Save N · review M" beats a generic "Save selected" because it
    /// previews the effect: persist now, then enter the MCQ flow.
    private var saveButtonLabel: String {
        let selectedCount = selectedConfidentPrincipleIds.count
        switch (selectedCount, ambiguousMomentCount) {
        case (0, 0):
            return "Save"
        case (let selected, 0):
            return "Save \(selected)"
        case (0, let ambiguous):
            return "Review \(ambiguous)"
        case (let selected, let ambiguous):
            return "Save \(selected) · review \(ambiguous)"
        }
    }

    private func primaryActionButton(
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(WarmPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WarmPalette.accent)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
