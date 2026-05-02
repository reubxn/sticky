//
//  DashboardRecordingHistoryStore.swift
//  leanring-buddy
//
//  Persists past teach-mode "recordings" — i.e. the spoken transcript
//  + extracted principle from each teach-mode press. Lets the
//  Dashboard's "Recordings" tab show a history of what the user has
//  taught Sticky and what was extracted.
//
//  Today the teach pipeline doesn't write its results anywhere durable
//  — `CompanionManager.lastTeachSessionResult` is in-memory only. This
//  store is the durable archive: a JSON file per teach session in
//  Application Support, decoded back when the dashboard opens.
//
//  File location:
//    ~/Library/Application Support/com.learning-buddy.clicky/
//      history/recordings/<recordingId>.json
//

import Foundation

/// One archived teach-mode recording. Mirrors the shape of what the
/// teach pipeline produces — a transcript, a principle, and timing.
struct DashboardRecording: Codable, Identifiable {
    let id: String
    let recordedAt: Date
    /// What the user said while holding push-to-talk in teach mode.
    let transcript: String
    /// The extracted taste principle. Optional because some teach
    /// presses produce nothing usable (Claude returned `{}`) — we
    /// still want to log that the user tried.
    let extractedPrinciple: TastePrinciple?
    /// Whether the user tapped "Remember" (and the principle made it
    /// into the taste profile) or "Skip".
    let wasApproved: Bool
}

@MainActor
enum DashboardRecordingHistoryStore {
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"
    private static let historyDirectoryName = "history"
    private static let recordingsDirectoryName = "recordings"

    /// Loads every archived recording, newest first.
    static func loadAllRecordings() -> [DashboardRecording] {
        guard let recordingsDirectoryURL = try? recordingsDirectoryURL() else { return [] }
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let loadedRecordings: [DashboardRecording] = fileURLs.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DashboardRecording.self, from: data)
        }

        return loadedRecordings.sorted(by: { $0.recordedAt > $1.recordedAt })
    }

    /// Appends a new recording to the archive.
    static func recordTeachMoment(
        transcript: String,
        extractedPrinciple: TastePrinciple?,
        wasApproved: Bool
    ) {
        let recording = DashboardRecording(
            id: UUID().uuidString,
            recordedAt: Date(),
            transcript: transcript,
            extractedPrinciple: extractedPrinciple,
            wasApproved: wasApproved
        )

        do {
            let recordingsDirectoryURL = try recordingsDirectoryURL()
            try FileManager.default.createDirectory(
                at: recordingsDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let fileURL = recordingsDirectoryURL.appendingPathComponent("\(recording.id).json", isDirectory: false)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recording)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("⚠️ DashboardRecordingHistoryStore: failed to record: \(error)")
        }
    }

    static func deleteRecording(id recordingId: String) {
        guard let recordingsDirectoryURL = try? recordingsDirectoryURL() else { return }
        let fileURL = recordingsDirectoryURL.appendingPathComponent("\(recordingId).json", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private static func recordingsDirectoryURL() throws -> URL {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(domain: "DashboardRecordingHistoryStore", code: -1)
        }
        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(historyDirectoryName, isDirectory: true)
            .appendingPathComponent(recordingsDirectoryName, isDirectory: true)
    }
}
