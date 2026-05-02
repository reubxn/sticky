//
//  TeamTasteProfileStore.swift
//  leanring-buddy
//
//  Read-only loader for the shared team taste profile. For the hackathon
//  MVP this file is hand-written by a teammate and dropped into the app's
//  Application Support directory — there is no live sync, no backend, no
//  conflict resolution. The "boss teaches, employee learns" demo just
//  swaps in a different JSON.
//
//  When the file is missing or malformed, callers get nil back and the
//  app falls back to personal-only taste context. Never throws on a
//  missing file — that's the expected first-launch state.
//

import Foundation

enum TeamTasteProfileStore {
    /// Same Application Support subdirectory as the personal profile —
    /// keeps everything Sticky-related in one place so a single demo
    /// reset can wipe both files together.
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"

    private static let teamProfileFileName = "team-profile.json"

    /// Loads the team profile if the file exists and decodes cleanly.
    /// Returns nil otherwise — the caller treats that as "no team taste,
    /// fall back to personal only" rather than an error.
    static func loadTeamProfile() -> TeamTasteProfile? {
        guard let teamProfileFileURL = profileFileURL() else { return nil }
        guard FileManager.default.fileExists(atPath: teamProfileFileURL.path) else { return nil }

        let teamProfileFileData: Data
        do {
            teamProfileFileData = try Data(contentsOf: teamProfileFileURL)
        } catch {
            print("⚠️ TeamTasteProfileStore: failed to read \(teamProfileFileURL.path): \(error)")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(TeamTasteProfile.self, from: teamProfileFileData)
        } catch {
            print("⚠️ TeamTasteProfileStore: failed to decode \(teamProfileFileURL.path): \(error)")
            return nil
        }
    }

    /// Path on disk where Sticky expects the team profile to live. Useful
    /// for logging so the user knows where to drop the file.
    static func profileFileLocation() -> String {
        return profileFileURL()?.path ?? "<unknown>"
    }

    private static func profileFileURL() -> URL? {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(teamProfileFileName, isDirectory: false)
    }
}
