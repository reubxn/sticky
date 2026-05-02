//
//  ElevenLabsTTSClient.swift
//  leanring-buddy
//
//  Streams text-to-speech audio from ElevenLabs and plays it back
//  through the system audio output.
//
//  Calls ElevenLabs directly instead of via the Cloudflare Worker because
//  ElevenLabs' free tier blocks requests from datacenter / proxy IPs.
//  The API key + voice ID are read at runtime from a local secrets.plist
//  in Application Support, so they never ship in the repo or in the binary.
//

import AVFoundation
import Combine
import Foundation

/// One of ElevenLabs' free, publicly-available default voices. The IDs
/// here are stable across all ElevenLabs accounts (every free account
/// has access to these by default), so we can hardcode them without
/// per-user voice library lookups.
struct ElevenLabsFreeVoice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let descriptor: String
}

@MainActor
final class ElevenLabsTTSClient: ObservableObject {
    /// The curated set of free default voices users can pick between in
    /// the menu bar dropdown. Limited to ElevenLabs' free-tier defaults
    /// so any account can use them without buying voice clones.
    /// Pulled live from `GET /v2/voices` against the configured ElevenLabs
    /// key — limited to voices with `category == "premade"` (the free
    /// defaults every ElevenLabs account has access to). If you rotate
    /// keys to an account with a different premade roster, re-run that
    /// query and replace this list.
    static let freeVoices: [ElevenLabsFreeVoice] = [
        ElevenLabsFreeVoice(id: "pNInz6obpgDQGcFmaJgB", displayName: "Adam",    descriptor: "Dominant, Firm · American"),
        ElevenLabsFreeVoice(id: "Xb7hH8MSUJpSbSDYk0k2", displayName: "Alice",   descriptor: "Engaging · British"),
        ElevenLabsFreeVoice(id: "hpp4J3VqNfWAUOO0d1Us", displayName: "Bella",   descriptor: "Bright, Warm · American"),
        ElevenLabsFreeVoice(id: "pqHfZKP75CvOlQylNhV4", displayName: "Bill",    descriptor: "Wise, Mature · American"),
        ElevenLabsFreeVoice(id: "nPczCjzI2devNBz1zQrb", displayName: "Brian",   descriptor: "Deep, Comforting · American"),
        ElevenLabsFreeVoice(id: "N2lVS1w4EtoT3dr4eOWO", displayName: "Callum",  descriptor: "Husky · American"),
        ElevenLabsFreeVoice(id: "IKne3meq5aSn9XLyUdCD", displayName: "Charlie", descriptor: "Deep, Energetic · Australian"),
        ElevenLabsFreeVoice(id: "iP95p4xoKVk53GoZ742B", displayName: "Chris",   descriptor: "Charming · American"),
        ElevenLabsFreeVoice(id: "onwK4e9ZLuTAKqWW03F9", displayName: "Daniel",  descriptor: "Steady Broadcaster · British"),
        ElevenLabsFreeVoice(id: "cjVigY5qzO86Huf0OWal", displayName: "Eric",    descriptor: "Smooth, Trustworthy · American"),
        ElevenLabsFreeVoice(id: "JBFqnCBsd6RMkjVDRZzb", displayName: "George",  descriptor: "Warm Storyteller · British"),
        ElevenLabsFreeVoice(id: "SOYHLrjzK2X1ezoPC6cr", displayName: "Harry",   descriptor: "Fierce · American"),
        ElevenLabsFreeVoice(id: "cgSgspJ2msm6clMCkdW9", displayName: "Jessica", descriptor: "Playful, Warm · American"),
        ElevenLabsFreeVoice(id: "FGY2WhTYpPnrIDTdsKH5", displayName: "Laura",   descriptor: "Quirky · American"),
        ElevenLabsFreeVoice(id: "TX3LPaxmHKxFdv7VOQHJ", displayName: "Liam",    descriptor: "Energetic · American"),
        ElevenLabsFreeVoice(id: "pFZP5JQG7iQjIQuC4Bku", displayName: "Lily",    descriptor: "Velvety · British"),
        ElevenLabsFreeVoice(id: "XrExE9yKIg1WjnnlVkGX", displayName: "Matilda", descriptor: "Professional · American"),
        ElevenLabsFreeVoice(id: "SAz9YHcvj6GT2YYXdXww", displayName: "River",   descriptor: "Neutral · American"),
        ElevenLabsFreeVoice(id: "CwhRBWXzGAHq8TQ4Fs17", displayName: "Roger",   descriptor: "Laid-Back · American"),
        ElevenLabsFreeVoice(id: "EXAVITQu4vr4xnSDxMaL", displayName: "Sarah",   descriptor: "Mature, Confident · American"),
        ElevenLabsFreeVoice(id: "bIHbv24MWmeRgasZH58o", displayName: "Will",    descriptor: "Relaxed · American"),
    ]

    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the
    /// audio finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    /// Live audio output level of the currently playing TTS, normalized
    /// to roughly 0...1. Driven by polling `AVAudioPlayer.averagePower`
    /// while playback is active. Consumed by the overlay edge glow so
    /// the aurora reacts to the AI's voice the same way it reacts to
    /// the user's mic input. Zero whenever nothing is playing.
    @Published private(set) var currentPowerLevel: CGFloat = 0

    /// Polls the active player's metering at 50Hz (mirrors the effective
    /// rate the mic-side level is updated at). Invalidated as soon as
    /// playback stops so we don't keep the run loop awake unnecessarily.
    private var meteringTimer: Timer?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Sends `text` to ElevenLabs TTS and plays the resulting audio.
    /// Throws on network or decoding errors. Cancellation-safe.
    /// `overrideVoiceID` lets the menu bar dropdown switch the voice
    /// per-call without changing the bundled secrets.plist default; pass
    /// nil to fall back to the plist value.
    func speakText(_ text: String, overrideVoiceID: String? = nil) async throws {
        guard let apiKey = AppBundleConfiguration.stringValue(forKey: "ELEVENLABS_API_KEY") else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing ELEVENLABS_API_KEY in secrets.plist"])
        }

        let resolvedVoiceID = overrideVoiceID
            ?? AppBundleConfiguration.stringValue(forKey: "ELEVENLABS_VOICE_ID")

        guard let voiceId = resolvedVoiceID else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing ELEVENLABS_VOICE_ID in secrets.plist"])
        }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)") else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid ElevenLabs URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "TTS API error (\(httpResponse.statusCode)): \(errorBody)"])
        }

        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: data)
        // Metering must be enabled before play() — `averagePower` returns
        // -160dB until `updateMeters()` is called against an enabled
        // player, so we'd see a flat zero level otherwise.
        player.isMeteringEnabled = true
        self.audioPlayer = player
        player.play()
        startMeteringTimer()
        print("🔊 ElevenLabs TTS: playing \(data.count / 1024)KB audio")
    }

    /// Whether TTS audio is currently playing back.
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopMeteringTimer()
        currentPowerLevel = 0
    }

    /// Starts the 50Hz metering poll. Safe to call multiple times — any
    /// existing timer is invalidated first so we never run two in
    /// parallel for back-to-back utterances.
    private func startMeteringTimer() {
        stopMeteringTimer()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 50.0, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop because we schedule it
            // from the @MainActor; hop back onto the actor explicitly
            // to keep Swift concurrency happy.
            Task { @MainActor [weak self] in
                self?.updateCurrentPowerLevel()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    /// Reads the active player's current average power, converts the dB
    /// reading into a 0...1 amplitude, applies the same decay-smoothing
    /// the mic level uses, and publishes it. When playback stops, this
    /// also tears down the timer so we don't keep polling a dead player.
    private func updateCurrentPowerLevel() {
        guard let audioPlayer, audioPlayer.isPlaying else {
            // Decay quickly to zero so the aurora glides down rather
            // than snapping off at the end of an utterance.
            let decayedLevel = currentPowerLevel * 0.72
            currentPowerLevel = decayedLevel
            if decayedLevel < 0.01 {
                currentPowerLevel = 0
                stopMeteringTimer()
            }
            return
        }

        audioPlayer.updateMeters()
        let averagePowerInDecibels = audioPlayer.averagePower(forChannel: 0)
        // -60dB is roughly silence; 0dB is peak. Convert to a linear
        // amplitude in 0...1 using the standard pow(10, dB/20) curve,
        // then boost slightly so a typical speaking voice sits in the
        // upper half of the range (matches how the mic-side scaling
        // boosts RMS by 10.2x in BuddyDictationManager).
        let linearAmplitude = pow(10.0, Double(averagePowerInDecibels) / 20.0)
        let boostedLevel = min(max(CGFloat(linearAmplitude) * 1.6, 0), 1)
        // Same decay smoothing the mic uses so quiet pauses inside the
        // utterance don't make the aurora flicker.
        let smoothedLevel = max(boostedLevel, currentPowerLevel * 0.72)
        currentPowerLevel = smoothedLevel
    }
}
