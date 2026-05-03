//
//  ChatHistorySidebar.swift
//  leanring-buddy
//
//  Left rail inside the Dashboard's Chat tab. Lists every archived chat
//  session (text + voice), newest first, so the user can browse old
//  conversations without leaving the live chat surface. Tapping a row
//  loads that session into the active ChatView; the live composer below
//  it then continues writing into the same on-disk archive.
//
//  Replaces the old standalone "Chat history" tab — chats now live next
//  to the live chat instead of being a separate dashboard section.
//

import SwiftUI

struct ChatHistorySidebar: View {
    /// The same ChatViewModel the live ChatView is bound to. The sidebar
    /// reads `currentChatHistorySessionId` from it to highlight the
    /// active row, calls `loadArchivedSession(_:)` on tap, and calls
    /// `startNewChat()` from the "New chat" button.
    @ObservedObject var chatViewModel: ChatViewModel

    /// CompanionManager backing the persona dropdown rendered at the top
    /// of the sidebar — switching in the dropdown calls
    /// `setPersonaSelection(...)` on this instance, and the live chat
    /// reads the same `personaSelection` when composing the next system
    /// prompt. Mirrors the `headerPersonaPicker` in the menu bar panel.
    @ObservedObject var companionManager: CompanionManager

    @State private var loadedChatSessions: [DashboardChatSession] = []

    /// Drives the persona popover anchored to the sidebar dropdown row.
    @State private var isPersonaPickerPresented: Bool = false

    /// Tracks hover over the persona dropdown row so its surface can lift
    /// the same way the menu-bar panel's picker does.
    @State private var isHoveringPersonaCard: Bool = false

    /// Sessions filtered to only those archived under the persona that's
    /// currently active. Switching persona narrows the list to that
    /// persona's conversation history — chats with different personas
    /// stay segregated so the sidebar always reflects "who you're
    /// talking to right now". Legacy sessions with no `personaId` are
    /// treated as `Me` chats since that was the only mode at the time.
    private var sessionsForActivePersona: [DashboardChatSession] {
        let activePersonaId = personaIdForCurrentSelection()
        return loadedChatSessions.filter { session in
            let resolvedPersonaId = session.personaId ?? PersonaStore.mePseudoPersona.id
            return resolvedPersonaId == activePersonaId
        }
    }

    private func personaIdForCurrentSelection() -> String {
        switch companionManager.personaSelection {
        case .me: return PersonaStore.mePseudoPersona.id
        case .team: return PersonaStore.teamPseudoPersona.id
        case .teammate(let id): return id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            personaPickerSection
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.top, ElevenLabsBrand.Spacing.lg)
                .padding(.bottom, ElevenLabsBrand.Spacing.sm)

            Divider().background(ElevenLabsBrand.Colors.hairline)

            sidebarHeader
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.top, ElevenLabsBrand.Spacing.md)
                .padding(.bottom, ElevenLabsBrand.Spacing.sm)

            Divider().background(ElevenLabsBrand.Colors.hairline)

            sessionListScrollArea
        }
        .background(ElevenLabsBrand.Colors.paperRecessed)
        .onAppear {
            refreshChatSessions()
        }
        // Re-archive happens on each finalized assistant message — refresh
        // the sidebar list whenever the active session id changes (new
        // chat) or the live message count changes (assistant just
        // finished a reply).
        .onChange(of: chatViewModel.currentChatHistorySessionId) { _ in
            refreshChatSessions()
        }
        .onChange(of: chatViewModel.messages.count) { _ in
            refreshChatSessions()
        }
    }

    // MARK: - Persona Picker

    /// Full-width dropdown row showing the active persona's avatar +
    /// name + chevron. Tapping opens a popover with the same Me / Team /
    /// Teammates structure used by the menu bar panel — switching here
    /// updates `companionManager.personaSelection`, which the live chat
    /// reads when composing the next system prompt.
    private var personaPickerSection: some View {
        let activePersonaBundle = PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)
            ?? PersonaStore.mePseudoPersona

        return Button(action: { isPersonaPickerPresented.toggle() }) {
            HStack(spacing: 8) {
                PersonaAvatarView(
                    avatar: activePersonaBundle.avatar,
                    diameter: 22
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(activePersonaBundle.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)
                    if let role = activePersonaBundle.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 10))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(
                        isHoveringPersonaCard
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isHoveringPersonaCard
                            ? ElevenLabsBrand.Colors.paperRecessed
                            : ElevenLabsBrand.Colors.card
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isHoveringPersonaCard
                            ? ElevenLabsBrand.Colors.inkTertiary.opacity(0.4)
                            : ElevenLabsBrand.Colors.hairline,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
        .onHover { hovering in isHoveringPersonaCard = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringPersonaCard)
        .help("Switch who you're chatting with")
        .popover(
            isPresented: $isPersonaPickerPresented,
            arrowEdge: .top
        ) {
            personaPickerPopoverContent(activePersonaID: activePersonaBundle.id)
        }
    }

    /// Body of the persona popover — Me / Team on top, then teammates
    /// under a `TEAMMATES` eyebrow. Mirrors `personaPickerContent` in
    /// CompanionPanelView so the two surfaces feel identical.
    @ViewBuilder
    private func personaPickerPopoverContent(activePersonaID: String) -> some View {
        let teammates = PersonaStore.availableTeammates

        VStack(alignment: .leading, spacing: 0) {
            sidebarPersonaPickerRow(
                persona: PersonaStore.mePseudoPersona,
                isSelected: activePersonaID == PersonaStore.mePseudoPersona.id
            )
            sidebarPersonaPickerRow(
                persona: PersonaStore.teamPseudoPersona,
                isSelected: activePersonaID == PersonaStore.teamPseudoPersona.id
            )

            if !teammates.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Text("TEAMMATES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                ForEach(teammates, id: \.id) { teammate in
                    sidebarPersonaPickerRow(
                        persona: teammate,
                        isSelected: activePersonaID == teammate.id
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(ElevenLabsBrand.Colors.card)
    }

    @ViewBuilder
    private func sidebarPersonaPickerRow(persona: PersonaBundle, isSelected: Bool) -> some View {
        SidebarPersonaPickerRow(
            persona: persona,
            isSelected: isSelected,
            onSelect: {
                companionManager.setPersonaSelection(
                    PersonaStore.selectionForWheelPersona(persona)
                )
                isPersonaPickerPresented = false
            }
        )
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHATS")
                .font(ElevenLabsBrand.Typography.eyebrow)
                .tracking(0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

            Button(action: {
                chatViewModel.startNewChat()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New chat")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ElevenLabsBrand.Colors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.98))
            .pointerCursor()
            .help("Start a fresh chat")
        }
    }

    // MARK: - Session list

    private var sessionListScrollArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                let visibleSessions = sessionsForActivePersona
                if visibleSessions.isEmpty {
                    emptyStatePlaceholder
                } else {
                    ForEach(visibleSessions) { session in
                        sessionRow(session)
                    }
                }
            }
            .padding(.vertical, ElevenLabsBrand.Spacing.sm)
        }
    }

    private var emptyStatePlaceholder: some View {
        Text("No past chats with this persona yet. Start a conversation below — it'll show up here once the first reply lands.")
            .font(.system(size: 11))
            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, ElevenLabsBrand.Spacing.sm)
    }

    private func sessionRow(_ session: DashboardChatSession) -> some View {
        let isActiveSession = (session.id == chatViewModel.currentChatHistorySessionId)
        let isVoiceSession = (session.medium == "voice")
        let previewSnippet = previewSnippetForSession(session)
        let metaLine = metaLineForSession(session, isVoice: isVoiceSession)
        return Button(action: {
            // Don't reload the session that's already loaded — would
            // wipe any unsent draft and re-build the message structs
            // for no reason.
            guard !isActiveSession else { return }
            chatViewModel.loadArchivedSession(session)
        }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 12.5, weight: isActiveSession ? .semibold : .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !previewSnippet.isEmpty {
                    Text(previewSnippet)
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(metaLine)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActiveSession ? ElevenLabsBrand.Colors.card : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.99))
        .pointerCursor()
        .contextMenu {
            Button(role: .destructive) {
                deleteSession(session)
            } label: {
                Label("Delete chat", systemImage: "trash")
            }
        }
    }

    /// One-line snippet of the most recent assistant reply (or last user
    /// message if the session never got a reply). Lets the user scan the
    /// list by content, not just title — the title is just the first
    /// user message and reads identically across many short follow-ups.
    private func previewSnippetForSession(_ session: DashboardChatSession) -> String {
        guard let lastMessage = session.messages.last else { return "" }
        let collapsedText = lastMessage.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedText.isEmpty else { return "" }
        let speakerPrefix = (lastMessage.role == "user") ? "You: " : ""
        return speakerPrefix + collapsedText
    }

    /// Bottom meta line — medium glyph + relative date. Persona name is
    /// dropped here because the list is already filtered to the active
    /// persona, so repeating it on every row would be redundant.
    private func metaLineForSession(_ session: DashboardChatSession, isVoice: Bool) -> String {
        let mediumLabel = isVoice ? "Voice" : "Chat"
        let relativeDate = session.startedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(mediumLabel) · \(relativeDate)"
    }

    // MARK: - Actions

    private func refreshChatSessions() {
        loadedChatSessions = DashboardChatHistoryStore.loadAllSessions()
    }

    private func deleteSession(_ session: DashboardChatSession) {
        DashboardChatHistoryStore.deleteSession(id: session.id)
        // If the user just deleted the session they were viewing, fall
        // back to a fresh chat so the composer doesn't keep writing into
        // a deleted archive file.
        if session.id == chatViewModel.currentChatHistorySessionId {
            chatViewModel.startNewChat()
        }
        refreshChatSessions()
    }
}

// MARK: - Sidebar Persona Picker Row

/// Single row inside the chat-sidebar persona popover. Mirrors the
/// `PersonaPickerRow` defined in CompanionPanelView but is duplicated
/// here so the sidebar isn't coupled to the menu-bar panel file.
private struct SidebarPersonaPickerRow: View {
    let persona: PersonaBundle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PersonaAvatarView(avatar: persona.avatar, diameter: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(persona.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)

                    if let role = persona.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                            .lineLimit(1)
                    }
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
