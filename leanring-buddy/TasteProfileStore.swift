//
//  TasteProfileStore.swift
//  leanring-buddy
//
//  Local JSON persistence for the user's taste profile — the "centralised
//  mind" that teach mode writes to and ask mode reads from. Stored in the
//  app's Application Support directory so it survives reinstalls placed
//  in the same user account.
//
//  Hackathon MVP: synchronous load/save, no migrations, no backups. The
//  file is small enough (a few hundred principles at most) that this is
//  fine for the demo and for the foreseeable future.
//

import Foundation

enum TasteProfileStoreError: Error, LocalizedError {
    case applicationSupportDirectoryUnavailable
    case readFailed(underlying: Error)
    case writeFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case encodeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Couldn't find the Application Support directory."
        case .readFailed(let underlying):
            return "Couldn't read the taste profile: \(underlying.localizedDescription)"
        case .writeFailed(let underlying):
            return "Couldn't write the taste profile: \(underlying.localizedDescription)"
        case .decodeFailed(let underlying):
            return "Couldn't decode the taste profile: \(underlying.localizedDescription)"
        case .encodeFailed(let underlying):
            return "Couldn't encode the taste profile: \(underlying.localizedDescription)"
        }
    }
}

enum TasteProfileStore {
    /// Subdirectory inside Application Support where Sticky stores its data.
    /// Matches the bundle id convention so other Sticky-related files can
    /// live here without colliding with other apps.
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"

    private static let personalProfileFileName = "taste-profile.json"

    private static let localUserId = "local-user"

    /// Loads the user's personal taste profile. Returns an empty profile if the
    /// file doesn't exist yet — this is the expected first-launch state, not
    /// an error. Throws only on real read or decode failures.
    static func loadProfile() throws -> TasteProfile {
        let profileFileURL = try profileFileURL()

        guard FileManager.default.fileExists(atPath: profileFileURL.path) else {
            return TasteProfile(
                userId: localUserId,
                principles: [],
                updatedAt: Date()
            )
        }

        let profileFileData: Data
        do {
            profileFileData = try Data(contentsOf: profileFileURL)
        } catch {
            throw TasteProfileStoreError.readFailed(underlying: error)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(TasteProfile.self, from: profileFileData)
        } catch {
            throw TasteProfileStoreError.decodeFailed(underlying: error)
        }
    }

    /// Saves the given profile to disk, overwriting any existing file. Stamps
    /// `updatedAt` to the current time. Creates the parent directory on first
    /// write.
    static func saveProfile(_ profile: TasteProfile) throws {
        try ensureApplicationSupportDirectoryExists()

        var profileToSave = profile
        profileToSave.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let profileData: Data
        do {
            profileData = try encoder.encode(profileToSave)
        } catch {
            throw TasteProfileStoreError.encodeFailed(underlying: error)
        }

        let profileFileURL = try profileFileURL()
        do {
            try profileData.write(to: profileFileURL, options: [.atomic])
        } catch {
            throw TasteProfileStoreError.writeFailed(underlying: error)
        }
    }

    /// Appends the given principles to the user's profile in one atomic
    /// write. Skips principles whose `id` already exists in the profile so
    /// rapid double-saves don't duplicate. Returns the number of principles
    /// actually added (after dedup).
    @discardableResult
    static func appendApprovedPrinciples(_ newPrinciples: [TastePrinciple]) throws -> Int {
        guard !newPrinciples.isEmpty else { return 0 }

        var profile = try loadProfile()
        let existingPrincipleIds = Set(profile.principles.map { $0.id })

        var addedCount = 0
        for newPrinciple in newPrinciples {
            guard !existingPrincipleIds.contains(newPrinciple.id) else { continue }
            profile.principles.append(newPrinciple)
            addedCount += 1
        }

        guard addedCount > 0 else { return 0 }

        try saveProfile(profile)
        return addedCount
    }

    /// Where the personal profile file lives on disk. Useful for logging so
    /// the user can find it during the demo.
    static func profileFileLocation() -> String {
        if let url = try? profileFileURL() {
            return url.path
        }
        return "<unknown>"
    }

    // MARK: - Filesystem helpers

    private static func profileFileURL() throws -> URL {
        try applicationSupportSubdirectoryURL()
            .appendingPathComponent(personalProfileFileName, isDirectory: false)
    }

    private static func applicationSupportSubdirectoryURL() throws -> URL {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw TasteProfileStoreError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
    }

    private static func ensureApplicationSupportDirectoryExists() throws {
        let directoryURL = try applicationSupportSubdirectoryURL()

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw TasteProfileStoreError.writeFailed(underlying: error)
            }
        }
    }
}
