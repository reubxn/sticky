//
//  TeamContextStore.swift
//  leanring-buddy
//
//  Persists the team's shared context — a free-form brief about what the
//  team does, plus a list of attached files. Personas operating in team
//  mode (and teammate personas) get a brief overview of this material so
//  they can speak with awareness of what the team is working on, what
//  product they're shipping, what brand rules apply, etc.
//
//  By default Sticky only sees a short overview: the team brief plus a
//  catalog of attached files (filename + one-line summary). For small
//  text files the full contents are inlined so the model can actually
//  read them when relevant; larger or binary files only show up by
//  filename + summary so the prompt stays cheap. The user can add a
//  one-line summary per file in the dashboard so the model knows what's
//  inside without Sticky having to read it every turn.
//
//  Storage:
//    ~/Library/Application Support/com.learning-buddy.clicky/team-context.json
//    ~/Library/Application Support/com.learning-buddy.clicky/team-files/<filename>
//

import Foundation

/// One file the user has dropped into the team context. The original
/// bytes live next to the JSON in `team-files/`; this struct only
/// carries the lightweight metadata that gets injected into the prompt.
struct TeamContextAttachedFile: Codable, Identifiable, Equatable {
    /// Stable id used for SwiftUI list diffing and for deletion.
    let id: String

    /// Original filename as the user dropped it (e.g. "brand-guidelines.md").
    /// We keep the original name so the model has a meaningful label to
    /// refer to when the user asks "what's in the brand guidelines?".
    var filename: String

    /// User-supplied one-line summary of what's in the file. Always shown
    /// to the model; the file body itself is only inlined when small.
    /// Empty string is fine — the model will see "[no summary]".
    var summary: String

    /// Size in bytes of the stored copy. Used to decide whether to inline
    /// the body in the prompt or only mention the file by name.
    var sizeBytes: Int

    /// True when the file decoded as UTF-8 text on import. Binary files
    /// (images, PDFs) are stored on disk but never inlined in prompts.
    var isPlainText: Bool

    /// When the user added it. Surfaced in the dashboard list.
    var addedAt: Date
}

/// The whole on-disk shape. Codable so it round-trips cleanly.
struct TeamContextProfile: Codable, Equatable {
    /// Free-form text describing what the team does, who they're for,
    /// what they're working on right now. Prepended to the team-mode
    /// system prompt verbatim so the model speaks with shared context.
    /// Empty string is fine — the section gets skipped if blank.
    var brief: String

    /// Files the user has attached. Order is preserved so the dashboard
    /// list is stable across launches.
    var attachedFiles: [TeamContextAttachedFile]

    /// Bookkeeping — surfaced in logs only.
    var updatedAt: Date

    static let empty: TeamContextProfile = TeamContextProfile(
        brief: "",
        attachedFiles: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

/// Read/write/append API for the team context. Backed by a single
/// `team-context.json` plus a `team-files/` folder of attachments.
/// Errors are logged and turned into "empty profile" returns where it
/// makes sense — the team page should always render something even on
/// a fresh install.
enum TeamContextStore {
    /// Inline at most this many bytes of any single text file in the
    /// prompt. Files larger than this still get summarised by filename
    /// + user summary, but their full contents stay on disk.
    static let maxInlinedFileBytes: Int = 4_096

    /// Soft cap on the total inlined-file content across all files in a
    /// single prompt build. Once we hit this, remaining files only show
    /// their filename + summary. Keeps "20 files dropped in" from
    /// blowing up Claude calls.
    static let maxTotalInlinedBytes: Int = 16_384

    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"
    private static let teamContextFileName = "team-context.json"
    private static let teamFilesSubdirectoryName = "team-files"

    // MARK: - Public API

    /// Loads the saved team context, or returns `.empty` if the file
    /// doesn't exist / failed to decode. Never throws — this read is
    /// called at every system-prompt build, and a corrupt file
    /// shouldn't break voice or chat.
    static func loadProfile() -> TeamContextProfile {
        guard let teamContextFileURL = teamContextFileURL() else {
            return .empty
        }
        guard FileManager.default.fileExists(atPath: teamContextFileURL.path) else {
            return .empty
        }

        let teamContextFileData: Data
        do {
            teamContextFileData = try Data(contentsOf: teamContextFileURL)
        } catch {
            print("⚠️ TeamContextStore: failed to read \(teamContextFileURL.path): \(error)")
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(TeamContextProfile.self, from: teamContextFileData)
        } catch {
            print("⚠️ TeamContextStore: failed to decode \(teamContextFileURL.path): \(error)")
            return .empty
        }
    }

    /// Writes the whole profile back to disk. Called from the dashboard
    /// after the user edits the brief or adds/removes a file.
    static func saveProfile(_ profile: TeamContextProfile) throws {
        guard let teamContextFileURL = teamContextFileURL() else {
            throw NSError(
                domain: "TeamContextStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't resolve Application Support directory."]
            )
        }

        try ensureDirectoryExists(at: teamContextFileURL.deletingLastPathComponent())

        var profileToSave = profile
        profileToSave.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let teamContextFileData = try encoder.encode(profileToSave)
        try teamContextFileData.write(to: teamContextFileURL, options: [.atomic])
    }

    /// Imports a file from a source URL into the team-files directory and
    /// returns the metadata to merge into the profile. The caller is
    /// responsible for adding the returned `TeamContextAttachedFile` to
    /// the profile and saving — this function only handles disk I/O for
    /// the file body so the dashboard view doesn't need FileManager
    /// boilerplate.
    static func importFile(fromSourceURL sourceURL: URL) throws -> TeamContextAttachedFile {
        guard let teamFilesDirectoryURL = teamFilesDirectoryURL() else {
            throw NSError(
                domain: "TeamContextStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't resolve team-files directory."]
            )
        }
        try ensureDirectoryExists(at: teamFilesDirectoryURL)

        let originalFilename = sourceURL.lastPathComponent
        let storedFilename = uniqueFilename(originalFilename, inDirectory: teamFilesDirectoryURL)
        let destinationURL = teamFilesDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)

        let fileBodyData = try Data(contentsOf: sourceURL)
        try fileBodyData.write(to: destinationURL, options: [.atomic])

        // Best-effort UTF-8 sniff. We don't need to be clever about
        // encodings here — only "is this safe to inline as text in the
        // prompt or not". A failed decode just means we'll show the
        // filename + summary and skip the body.
        let decodesAsUtf8Text: Bool = (String(data: fileBodyData, encoding: .utf8) != nil)

        return TeamContextAttachedFile(
            id: UUID().uuidString,
            filename: storedFilename,
            summary: "",
            sizeBytes: fileBodyData.count,
            isPlainText: decodesAsUtf8Text,
            addedAt: Date()
        )
    }

    /// Removes the on-disk file body for an attachment. Safe to call
    /// even if the body is already gone (we just log and continue).
    /// The caller still needs to drop the `TeamContextAttachedFile`
    /// entry from the profile and persist.
    static func deleteFileBody(forAttachedFile attachedFile: TeamContextAttachedFile) {
        guard let teamFilesDirectoryURL = teamFilesDirectoryURL() else { return }
        let fileBodyURL = teamFilesDirectoryURL.appendingPathComponent(attachedFile.filename, isDirectory: false)
        do {
            if FileManager.default.fileExists(atPath: fileBodyURL.path) {
                try FileManager.default.removeItem(at: fileBodyURL)
            }
        } catch {
            print("⚠️ TeamContextStore: couldn't delete \(fileBodyURL.path): \(error)")
        }
    }

    /// Reads the body of an attached text file (for inlining into the
    /// prompt). Returns nil for binary files, missing files, or anything
    /// that doesn't decode as UTF-8. Truncates to `maxInlinedFileBytes`
    /// so a single huge file can't dominate the prompt.
    static func readInlinedTextBody(forAttachedFile attachedFile: TeamContextAttachedFile) -> String? {
        guard attachedFile.isPlainText else { return nil }
        guard let teamFilesDirectoryURL = teamFilesDirectoryURL() else { return nil }
        let fileBodyURL = teamFilesDirectoryURL.appendingPathComponent(attachedFile.filename, isDirectory: false)
        guard let fileBodyData = try? Data(contentsOf: fileBodyURL) else { return nil }

        let bytesToRead = min(fileBodyData.count, maxInlinedFileBytes)
        let truncatedData = fileBodyData.prefix(bytesToRead)
        guard let decodedString = String(data: truncatedData, encoding: .utf8) else { return nil }
        if fileBodyData.count > bytesToRead {
            return decodedString + "\n…[truncated, file is \(fileBodyData.count) bytes total]"
        }
        return decodedString
    }

    /// Where the JSON lives. Public for the dashboard's "show in finder"
    /// affordance and for log lines.
    static func profileFileLocation() -> String {
        return teamContextFileURL()?.path ?? "<unknown>"
    }

    // MARK: - Private helpers

    private static func teamContextFileURL() -> URL? {
        return applicationSupportDirectoryURL()?
            .appendingPathComponent(teamContextFileName, isDirectory: false)
    }

    private static func teamFilesDirectoryURL() -> URL? {
        return applicationSupportDirectoryURL()?
            .appendingPathComponent(teamFilesSubdirectoryName, isDirectory: true)
    }

    private static func applicationSupportDirectoryURL() -> URL? {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return baseURL.appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
    }

    private static func ensureDirectoryExists(at directoryURL: URL) throws {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
    }

    /// Avoids overwriting an existing file when the user drops two
    /// things called `notes.md`. Appends ` (2)`, ` (3)`, … before the
    /// extension until a free name is found.
    private static func uniqueFilename(
        _ desiredFilename: String,
        inDirectory directoryURL: URL
    ) -> String {
        let initialDestinationURL = directoryURL.appendingPathComponent(desiredFilename, isDirectory: false)
        if !FileManager.default.fileExists(atPath: initialDestinationURL.path) {
            return desiredFilename
        }

        let nameWithoutExtension = (desiredFilename as NSString).deletingPathExtension
        let fileExtension = (desiredFilename as NSString).pathExtension
        var nextSuffix = 2
        while nextSuffix < 1000 {
            let candidateFilename: String
            if fileExtension.isEmpty {
                candidateFilename = "\(nameWithoutExtension) (\(nextSuffix))"
            } else {
                candidateFilename = "\(nameWithoutExtension) (\(nextSuffix)).\(fileExtension)"
            }
            let candidateURL = directoryURL.appendingPathComponent(candidateFilename, isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateFilename
            }
            nextSuffix += 1
        }
        // Pathological: 1000+ collisions. Fall back to a uuid-prefixed name.
        return "\(UUID().uuidString)-\(desiredFilename)"
    }
}
