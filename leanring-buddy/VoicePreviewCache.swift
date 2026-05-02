//
//  VoicePreviewCache.swift
//  leanring-buddy
//
//  Disk cache for per-voice "Hey, it's Sticky!" preview clips so the
//  voice picker dropdown can play previews instantly without a roundtrip
//  to ElevenLabs every click. First click on an uncached voice downloads
//  + saves; every subsequent click on any device that runs this app is
//  free playback. The dropdown also calls `prefetchAll(...)` on first
//  open to warm the cache for voices the user hasn't tried yet.
//

import Foundation

@MainActor
final class VoicePreviewCache {
    /// The exact phrase used for every preview clip. Kept here so changing
    /// the script in one place invalidates and refetches every entry —
    /// see `previewScriptVersion`.
    static let previewScript: String = "Hey, it's Sticky!"

    /// Bumped whenever `previewScript` changes meaningfully so old cached
    /// clips on disk are ignored / re-downloaded with the new wording.
    private static let previewScriptVersion: Int = 1

    /// Filename used for the bundled default voice (no override). Distinct
    /// from any real voice ID so the two namespaces never collide.
    private static let defaultVoiceFilename: String = "__sticky_default__"

    /// `~/Library/Application Support/com.learning-buddy.clicky/voice-previews/v{N}/`.
    /// The `v{N}` segment is from `previewScriptVersion` so bumping the
    /// version cleanly opts every user into refetching without a manual
    /// cache wipe — old `vN-1` directories can sit harmlessly until the
    /// next install.
    private let cacheDirectoryURL: URL

    init() {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectoryURL = supportRoot
            .appendingPathComponent("com.learning-buddy.clicky", isDirectory: true)
            .appendingPathComponent("voice-previews", isDirectory: true)
            .appendingPathComponent("v\(Self.previewScriptVersion)", isDirectory: true)
    }

    /// Returns the on-disk URL for `voiceID`'s cached clip if present,
    /// otherwise nil. nil `voiceID` means "the default bundled voice".
    func cachedClipURL(forVoiceID voiceID: String?) -> URL? {
        let url = clipFileURL(forVoiceID: voiceID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns the cached clip URL if present, otherwise downloads the
    /// clip from ElevenLabs, writes it to disk, and returns the new URL.
    /// Safe to call concurrently for different voice IDs; concurrent calls
    /// for the *same* voice ID may both hit the network (no in-flight
    /// dedupe) — that's a couple wasted bytes, not a correctness issue.
    func cachedOrDownloadedClipURL(
        forVoiceID voiceID: String?,
        using ttsClient: ElevenLabsTTSClient
    ) async throws -> URL {
        if let existing = cachedClipURL(forVoiceID: voiceID) {
            return existing
        }
        return try await downloadAndCache(voiceID: voiceID, using: ttsClient)
    }

    /// Forces a fresh download of `voiceID`'s preview clip (even if a
    /// cached file already exists) and overwrites the on-disk copy.
    @discardableResult
    func downloadAndCache(
        voiceID: String?,
        using ttsClient: ElevenLabsTTSClient
    ) async throws -> URL {
        let audioData = try await ttsClient.fetchAudioData(
            Self.previewScript,
            overrideVoiceID: voiceID
        )
        try ensureCacheDirectoryExists()
        let destinationURL = clipFileURL(forVoiceID: voiceID)
        try audioData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    /// Walks every voice ID in `voiceIDs`, downloads any that aren't
    /// already cached, and writes them to disk. Spaces calls out by
    /// 200ms so we don't slam the ElevenLabs free-tier rate limiter
    /// when prefetching all 21 voices in a row. Errors on individual
    /// voices are logged but don't stop the rest of the prefetch.
    func prefetchAll(
        voiceIDs: [String?],
        using ttsClient: ElevenLabsTTSClient
    ) async {
        for voiceID in voiceIDs {
            if Task.isCancelled { return }
            if cachedClipURL(forVoiceID: voiceID) != nil { continue }

            do {
                _ = try await downloadAndCache(voiceID: voiceID, using: ttsClient)
            } catch {
                print("⚠️ Voice prefetch failed for \(voiceID ?? "default"): \(error)")
            }

            // Brief gap between calls — generous enough to stay well under
            // the free-tier rate limit even with 21 voices in a row.
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Builds the on-disk URL for a voice's clip. Uses the voice ID as
    /// the filename for real voices and a stable sentinel for the
    /// default voice.
    private func clipFileURL(forVoiceID voiceID: String?) -> URL {
        let basename = voiceID ?? Self.defaultVoiceFilename
        return cacheDirectoryURL.appendingPathComponent("\(basename).mp3")
    }

    /// Creates the cache directory tree on first write. No-op if it
    /// already exists. Safe to call multiple times.
    private func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
