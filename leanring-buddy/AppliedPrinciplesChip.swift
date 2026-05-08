//
//  AppliedPrinciplesChip.swift
//  leanring-buddy
//
//  Transparency affordance for taste-grounded replies. Shows the user
//  which of their saved taste principles Sticky actually leaned on for
//  the most recent voice reply, so the taste profile is never invisible.
//  Without this chip the user has to take it on faith that their taste
//  influenced the answer at all.
//
//  The chip lives in the cursor overlay below Sticky's response bubble
//  and only renders when at least one principle was used. CompanionManager
//  gates visibility — when `lastAppliedPrinciples` is empty we hide the
//  chip rather than showing an empty state, so the now-default ask flow
//  doesn't surface a chip on every reply.
//

import SwiftUI

/// SwiftUI view bound to the most recent reply's applied principles.
/// Reads three CompanionManager properties: `lastAppliedPrinciples` (the
/// resolved list), `lastAppliedSourceWasTeam`, and `teamOriginPrincipleIds`
/// to render the right per-row Personal / Team pill.
struct AppliedPrinciplesChip: View {
    /// The principles Sticky's most recent reply actually leaned on, in
    /// the order Claude listed them. Caller is expected to gate render on
    /// non-empty — this view does not render its own empty state.
    let lastAppliedPrinciples: [TastePrinciple]

    /// True when at least one of `lastAppliedPrinciples` came from the
    /// team profile (vs the user's personal profile). Drives the per-row
    /// "Personal" / "Team" pill labels.
    let lastAppliedSourceWasTeam: Bool

    /// Set of principle ids that came from the team profile. Per-row check
    /// — used to render a "Team" pill on team-origin rows and "Personal"
    /// on personal-origin rows.
    let teamOriginPrincipleIds: Set<String>

    @State private var isExpanded: Bool = false

    var body: some View {
        populatedChip
    }

    // MARK: - Populated state

    /// Header pill (always visible) plus the optional expanded statement
    /// list. Clicking the header toggles expansion.
    private var populatedChip: some View {
        VStack(alignment: .leading, spacing: 6) {
            chipHeaderButton
            if isExpanded {
                expandedPrinciplesList
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(DS.Colors.surface2.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .stroke(DS.Colors.borderSubtle.opacity(0.5), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
        )
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    /// "✦ Used N of your principles ▾" — tapping it toggles `isExpanded`.
    /// Wrapped in a Button so SwiftUI handles hit testing; we use a
    /// PlainButtonStyle so the system blue tint doesn't bleed through.
    private var chipHeaderButton: some View {
        Button(action: {
            isExpanded.toggle()
        }) {
            HStack(spacing: 6) {
                Text("✦")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.accentText)
                Text(headerLabelText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Pluralized "used 1 of your principles" / "used 3 of your principles"
    /// — small thing but reads as more polished in the demo screenshot.
    private var headerLabelText: String {
        let principleCount = lastAppliedPrinciples.count
        let pluralizedNoun = principleCount == 1 ? "note" : "notes"
        return "used \(principleCount) of your \(pluralizedNoun)"
    }

    /// Vertical list of statements with a Personal / Team pill on each row.
    /// Pill color is meaningful — Personal uses the accent-text shade so
    /// the user's own taste reads as "yours"; Team uses textSecondary so
    /// inherited team principles read as ambient context.
    private var expandedPrinciplesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lastAppliedPrinciples) { appliedPrinciple in
                principleRow(for: appliedPrinciple)
            }
        }
    }

    private func principleRow(for appliedPrinciple: TastePrinciple) -> some View {
        let isTeamOrigin = teamOriginPrincipleIds.contains(appliedPrinciple.id)
        return HStack(alignment: .top, spacing: 6) {
            originPill(isTeamOrigin: isTeamOrigin)
            Text(appliedPrinciple.statement)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DS.Colors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func originPill(isTeamOrigin: Bool) -> some View {
        let pillLabel = isTeamOrigin ? "Team" : "Personal"
        let pillForegroundColor = isTeamOrigin
            ? DS.Colors.textSecondary
            : DS.Colors.accentText
        let pillBackgroundColor = isTeamOrigin
            ? DS.Colors.surface3
            : DS.Colors.accentSubtle
        return Text(pillLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(pillForegroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous)
                    .fill(pillBackgroundColor)
            )
            // Avoid the pill compressing while a long statement wraps —
            // it should always read as a discrete chip on the left.
            .fixedSize()
    }
}
