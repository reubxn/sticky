//
//  DashboardChatsView.swift
//  leanring-buddy
//
//  "Chats" tab — every archived chat session, newest first. Tap one
//  to expand its transcript inline. Read from
//  DashboardChatHistoryStore (JSON-on-disk).
//
//  Like Recordings, this view is wired but the live ChatViewModel
//  doesn't yet flush sessions to disk on its own. The integration
//  point is documented in CompanionManager. The view renders fine
//  with zero archived chats today — the empty-state card teaches the
//  user how to make one.
//

import SwiftUI

struct DashboardChatsView: View {
    @State private var loadedChatSessions: [DashboardChatSession] = []
    @State private var expandedSessionId: String? = nil

    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "CHATS",
                title: "Your past conversations.",
                subtitle: "Every chat you've had with Sticky in the floating chat window. Tap a session to read the transcript."
            ) {
                Button(action: refreshChatSessions) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Refresh")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.96))
                .pointerCursor()
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }

            if loadedChatSessions.isEmpty {
                emptyStateCard
            } else {
                ForEach(loadedChatSessions) { session in
                    chatSessionCard(session)
                }
            }
        }
        .onAppear { refreshChatSessions() }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No archived chats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text("Open the chat window from the Sticky menu bar panel and ask anything. Once a chat ends, it'll show up here.")
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func chatSessionCard(_ session: DashboardChatSession) -> some View {
        let isExpanded = (expandedSessionId == session.id)
        return VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedSessionId = isExpanded ? nil : session.id
                }
            }) {
                HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ElevenLabsBrand.Colors.ink)
                            .lineLimit(1)
                        Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.messages.count) messages")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.99))
            .pointerCursor()

            if isExpanded {
                Divider().background(ElevenLabsBrand.Colors.hairline)

                VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                    ForEach(session.messages) { message in
                        chatMessageRow(message)
                    }

                    HStack {
                        Spacer()
                        Button(action: {
                            DashboardChatHistoryStore.deleteSession(id: session.id)
                            refreshChatSessions()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Delete chat")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        }
                        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
                        .pointerCursor()
                    }
                }
            }
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func chatMessageRow(_ message: DashboardChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == "user" ? "YOU" : "STICKY")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            Text(message.text)
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func refreshChatSessions() {
        loadedChatSessions = DashboardChatHistoryStore.loadAllSessions()
    }
}
