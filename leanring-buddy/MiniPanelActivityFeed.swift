//
//  MiniPanelActivityFeed.swift
//  leanring-buddy
//
//  Compact "Recent activity" section rendered inside the menu bar
//  panel. Pulls the latest few teach moments from
//  DashboardRecordingHistoryStore + the latest chat sessions from
//  DashboardChatHistoryStore, merges them by timestamp, and shows
//  the top N as a tidy list. Lets the user see at a glance that
//  Sticky is actually learning from teach mode and that their chats
//  are being archived — without leaving the menu bar.
//
//  Each row tells you what kind of activity it was, when it
//  happened, and a one-line summary. Tap a row to open the
//  Dashboard pinned to either Recordings or Chats.
//

import SwiftUI

/// Unified activity row — abstracts over recordings and chats so the
/// merged feed can render them with the same UI affordance. Both
/// types collapse to (kind, time, summary) and a routing hint.
private struct MiniPanelActivityRow: Identifiable {
    enum Kind {
        case teach(wasApproved: Bool)
        case chat
    }

    let id: String
    let kind: Kind
    let occurredAt: Date
    let summary: String
}

struct MiniPanelActivityFeed: View {
    /// Most recent N activity entries (teach + chat) merged by time.
    /// Re-loaded each time the panel becomes visible.
    @State private var recentActivityRows: [MiniPanelActivityRow] = []

    /// How many rows to show. 3 strikes the right balance between
    /// "useful" and "doesn't dominate the panel". The dashboard's
    /// Recordings/Chats tabs are the place to see the long tail.
    private static let maxRowsShown = 3

    /// Hover state for the "See all" link in the section header. The
    /// row hovers below get their own state inside `MiniPanelActivityRowView`.
    @State private var isHoveringSeeAllButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("RECENT ACTIVITY")
                    .font(ElevenLabsBrand.Typography.eyebrow)
                    .tracking(0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

                Spacer()

                Button(action: openDashboardForFullHistory) {
                    HStack(spacing: 3) {
                        Text("See all")
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .offset(
                                x: isHoveringSeeAllButton ? 1 : 0,
                                y: isHoveringSeeAllButton ? -1 : 0
                            )
                    }
                    .foregroundColor(
                        isHoveringSeeAllButton
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.94))
                .pointerCursor()
                .onHover { hovering in isHoveringSeeAllButton = hovering }
                .animation(.easeOut(duration: 0.15), value: isHoveringSeeAllButton)
            }

            if recentActivityRows.isEmpty {
                emptyStateRow
            } else {
                VStack(spacing: 4) {
                    ForEach(recentActivityRows) { activityRow in
                        activityRowView(activityRow)
                    }
                }
                .padding(8)
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
        .onAppear { reloadActivity() }
    }

    private var emptyStateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

            Text("Use teach mode or open chat to start filling this in.")
                .font(.system(size: 11))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
    }

    @ViewBuilder
    private func activityRowView(_ row: MiniPanelActivityRow) -> some View {
        MiniPanelActivityRowView(
            kindLabel: activityKindLabel(row.kind),
            kindAccentColor: activityKindAccentColor(row.kind),
            iconSymbol: iconSymbolForActivityKind(row.kind),
            iconFontSize: iconFontSizeForActivityKind(row.kind),
            relativeTime: relativeTimeString(forDate: row.occurredAt),
            summary: row.summary,
            onTap: { openDashboardForActivityKind(row.kind) }
        )
    }

    private func iconSymbolForActivityKind(_ kind: MiniPanelActivityRow.Kind) -> String {
        switch kind {
        case .teach(let wasApproved):
            return wasApproved ? "brain.head.profile" : "rectangle.portrait.slash"
        case .chat:
            return "bubble.left.and.bubble.right.fill"
        }
    }

    private func iconFontSizeForActivityKind(_ kind: MiniPanelActivityRow.Kind) -> CGFloat {
        switch kind {
        case .teach: return 12
        case .chat:  return 11
        }
    }

    @ViewBuilder
    private func activityKindIcon(_ kind: MiniPanelActivityRow.Kind) -> some View {
        switch kind {
        case .teach(let wasApproved):
            Image(systemName: wasApproved ? "brain.head.profile" : "rectangle.portrait.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(activityKindAccentColor(kind))
        case .chat:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(activityKindAccentColor(kind))
        }
    }

    private func activityKindLabel(_ kind: MiniPanelActivityRow.Kind) -> String {
        switch kind {
        case .teach(let wasApproved): return wasApproved ? "TAUGHT" : "SKIPPED"
        case .chat:                   return "CHAT"
        }
    }

    private func activityKindAccentColor(_ kind: MiniPanelActivityRow.Kind) -> Color {
        switch kind {
        case .teach(let wasApproved):
            return wasApproved
                ? ElevenLabsBrand.Colors.ink
                : ElevenLabsBrand.Colors.inkTertiary
        case .chat:
            return ElevenLabsBrand.Colors.inkSecondary
        }
    }

    /// Short "12s ago / 4m ago / 2h ago / 3d ago" string for each
    /// row. Keeps the feed scannable without absolute timestamps
    /// (the dashboard shows those).
    private func relativeTimeString(forDate date: Date) -> String {
        let secondsAgo = Date().timeIntervalSince(date)
        if secondsAgo < 60 { return "just now" }
        if secondsAgo < 3600 { return "\(Int(secondsAgo / 60))m ago" }
        if secondsAgo < 86400 { return "\(Int(secondsAgo / 3600))h ago" }
        return "\(Int(secondsAgo / 86400))d ago"
    }

    // MARK: - Routing

    private func openDashboardForActivityKind(_ kind: MiniPanelActivityRow.Kind) {
        switch kind {
        case .teach:
            DashboardNavigationState.shared.selectedSection = .recordings
        case .chat:
            DashboardNavigationState.shared.selectedSection = .chats
        }
        MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
    }

    private func openDashboardForFullHistory() {
        DashboardNavigationState.shared.selectedSection = .recordings
        MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
    }

    // MARK: - Loading

    /// Pulls both archives off disk, projects them onto a unified
    /// activity row shape, sorts by date desc, and clamps to the top
    /// few. Cheap to run on every panel re-open since the archives
    /// are small JSON files.
    private func reloadActivity() {
        let recordingRows: [MiniPanelActivityRow] = DashboardRecordingHistoryStore
            .loadAllRecordings()
            .map { recording in
                MiniPanelActivityRow(
                    id: "rec-\(recording.id)",
                    kind: .teach(wasApproved: recording.wasApproved),
                    occurredAt: recording.recordedAt,
                    summary: summaryForTeachRecording(recording)
                )
            }

        let chatRows: [MiniPanelActivityRow] = DashboardChatHistoryStore
            .loadAllSessions()
            .map { chatSession in
                MiniPanelActivityRow(
                    id: "chat-\(chatSession.id)",
                    kind: .chat,
                    occurredAt: chatSession.endedAt,
                    summary: chatSession.title
                )
            }

        let mergedRowsSortedByDate = (recordingRows + chatRows)
            .sorted(by: { $0.occurredAt > $1.occurredAt })

        recentActivityRows = Array(mergedRowsSortedByDate.prefix(Self.maxRowsShown))
    }

    /// Picks the most useful one-liner from a recording — the saved
    /// principle's statement when one exists, otherwise the
    /// transcript itself.
    private func summaryForTeachRecording(_ recording: DashboardRecording) -> String {
        if let principle = recording.extractedPrinciple, !principle.statement.isEmpty {
            return principle.statement
        }
        return recording.transcript
    }
}

// MARK: - Activity Row View
//
// Single tappable activity entry. Owns its own hover state so each
// row in the list can independently highlight as the cursor moves
// across them. On hover the row gets a recessed wash, the trailing
// arrow brightens and nudges up-and-right (same micro-direction it
// will travel when tapped), and the whole row scales up imperceptibly.
private struct MiniPanelActivityRowView: View {
    let kindLabel: String
    let kindAccentColor: Color
    let iconSymbol: String
    let iconFontSize: CGFloat
    let relativeTime: String
    let summary: String
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: iconSymbol)
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundColor(kindAccentColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(kindLabel)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.3)
                            .foregroundColor(kindAccentColor)

                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

                        Text(relativeTime)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    }

                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(
                        isHovering
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
                    .offset(
                        x: isHovering ? 1 : 0,
                        y: isHovering ? -1 : 0
                    )
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isHovering
                            ? ElevenLabsBrand.Colors.paperRecessed
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.97))
        .pointerCursor()
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
