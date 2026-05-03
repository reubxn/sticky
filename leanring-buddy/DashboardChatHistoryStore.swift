//
//  DashboardChatHistoryStore.swift
//  leanring-buddy
//
//  Persists past chat sessions to disk so the Dashboard's "Chats" tab
//  can browse them. The existing `ChatViewModel` keeps an in-memory
//  transcript that survives the chat window being closed, but it
//  evaporates on app quit. This store snapshots a session's messages
//  to JSON so they're recoverable across launches.
//
//  This is intentionally a *separate* file from the live ChatViewModel
//  — we don't want every keystroke to hit disk. The dashboard calls
//  `recordSession(messages:)` once when it wants to archive the
//  current transcript (or we can wire `ChatViewModel.startNewChat` to
//  flush the previous session here, in a later pass).
//
//  File location:
//    ~/Library/Application Support/com.learning-buddy.clicky/
//      history/chats/<sessionId>.json
//

import Foundation

/// Snapshot of one chat session that the Dashboard's Chats tab can
/// render. Mirrors `ChatMessage` but uses a flat string role so the
/// JSON stays simple to hand-edit if anyone wants to seed demo data.
///
/// `personaId` and `medium` were added when voice chats started getting
/// archived alongside text chats — both are optional in the JSON so
/// older session files (which were always text chats with no persona
/// tag) keep decoding cleanly. Defaults are applied at the call site.
struct DashboardChatSession: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    /// Short title derived from the first user message. Helps the
    /// dashboard list show useful labels without the user having to
    /// title chats manually.
    let title: String
    let messages: [DashboardChatMessage]
    /// Identifies which persona this conversation was had with — the
    /// special pseudo-ids `__me__` / `__team__` for the user's own /
    /// pooled-team modes, or a teammate id (e.g. `"leonard"`) for a
    /// borrowed persona. Optional so legacy archives (pre-persona,
    /// always Sticky) decode without re-writing.
    let personaId: String?
    /// Whether this session came from the floating chat window
    /// (`"text"`) or from push-to-talk voice exchanges (`"voice"`).
    /// Optional for the same backwards-compat reason as `personaId`;
    /// callers treat `nil` as `"text"` since that's all we used to have.
    let medium: String?
}

struct DashboardChatMessage: Codable, Identifiable {
    let id: String
    /// "user" or "assistant" — kept as a string so the JSON file is
    /// readable to humans poking at it.
    let role: String
    let text: String
    let createdAt: Date
}

@MainActor
enum DashboardChatHistoryStore {
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"
    private static let historyDirectoryName = "history"
    private static let chatsDirectoryName = "chats"

    /// Loads every saved chat session, newest first. Returns an empty
    /// array if the directory doesn't exist yet (first launch) or if
    /// there are no archived sessions.
    static func loadAllSessions() -> [DashboardChatSession] {
        guard let chatsDirectoryURL = try? chatsDirectoryURL() else { return [] }
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: chatsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let loadedSessions: [DashboardChatSession] = fileURLs.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DashboardChatSession.self, from: data)
        }

        return loadedSessions.sorted(by: { $0.startedAt > $1.startedAt })
    }

    /// Archives a list of chat messages as a session. Title is derived
    /// from the first user message (or "Untitled chat" if there isn't
    /// one). No-op if the message list is empty.
    ///
    /// Pass a stable `sessionId` to overwrite the same on-disk file as
    /// the chat grows — that's how `ChatViewModel` keeps a single
    /// session up-to-date across many sends. Pass nil to mint a new id
    /// (used for one-off archiving).
    @discardableResult
    static func recordSession(
        sessionId: String? = nil,
        messages: [DashboardChatMessage],
        personaId: String? = nil,
        medium: String? = nil
    ) -> String? {
        guard !messages.isEmpty else { return nil }

        let firstUserMessage = messages.first(where: { $0.role == "user" })
        let derivedTitle = firstUserMessage.map { firstFewWords(of: $0.text) } ?? "Untitled chat"

        let resolvedSessionId = sessionId ?? UUID().uuidString
        let session = DashboardChatSession(
            id: resolvedSessionId,
            startedAt: messages.first?.createdAt ?? Date(),
            endedAt: messages.last?.createdAt ?? Date(),
            title: derivedTitle,
            messages: messages,
            personaId: personaId,
            medium: medium
        )

        do {
            let chatsDirectoryURL = try chatsDirectoryURL()
            try FileManager.default.createDirectory(
                at: chatsDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let fileURL = chatsDirectoryURL.appendingPathComponent("\(session.id).json", isDirectory: false)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: [.atomic])
            return resolvedSessionId
        } catch {
            print("⚠️ DashboardChatHistoryStore: failed to record session: \(error)")
            return nil
        }
    }

    /// Deletes one archived session by id.
    static func deleteSession(id sessionId: String) {
        guard let chatsDirectoryURL = try? chatsDirectoryURL() else { return }
        let fileURL = chatsDirectoryURL.appendingPathComponent("\(sessionId).json", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private static func chatsDirectoryURL() throws -> URL {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(domain: "DashboardChatHistoryStore", code: -1)
        }
        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(historyDirectoryName, isDirectory: true)
            .appendingPathComponent(chatsDirectoryName, isDirectory: true)
    }

    /// Picks the first ~8 words of a message and ellipsises the rest.
    /// Used for chat-session titles so the dashboard list is scannable.
    private static func firstFewWords(of text: String) -> String {
        let words = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(8)
            .joined(separator: " ")
        return words.count >= 60 ? "\(words.prefix(57))…" : words
    }
}
