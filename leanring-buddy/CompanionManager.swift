//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    /// Live audio level of the AI's TTS playback, normalized to roughly
    /// 0...1. Drives the edge-glow aurora during the `.responding`
    /// state so the glow reacts to the AI's voice the way it reacts to
    /// the user's mic during `.listening`. Sourced from the polled
    /// `averagePower` of the ElevenLabs `AVAudioPlayer`.
    @Published private(set) var currentTTSPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from Claude's response;
    /// observed by BlueCursorView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so BlueCursorView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// Custom speech bubble text for the pointing animation. When set,
    /// BlueCursorView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?

    // MARK: - Onboarding Video State (shared across all screen overlays)

    @Published var onboardingVideoPlayer: AVPlayer?
    @Published var showOnboardingVideo: Bool = false
    @Published var onboardingVideoOpacity: Double = 0.0
    private var onboardingVideoEndObserver: NSObjectProtocol?
    private var onboardingDemoTimeObserver: Any?

    // MARK: - Onboarding Prompt Bubble

    /// Text streamed character-by-character on the cursor after the onboarding video ends.
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false

    // MARK: - Onboarding Music

    private var onboardingMusicPlayer: AVAudioPlayer?
    private var onboardingMusicFadeTimer: Timer?

    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()

    /// Listener for the persona-wheel hotkey (shift + cmd held). Lives
    /// alongside the push-to-talk monitor — the two are independent so
    /// the user can summon the wheel without cancelling a voice session
    /// and vice versa.
    let personaWheelHotkeyMonitor = PersonaWheelHotkeyMonitor()

    let overlayWindowManager = OverlayWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    private static let workerBaseURL = "https://clicky-proxy.reubanramsden.workers.dev"

    private lazy var claudeAPI: ClaudeAPI = {
        return ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: selectedModel)
    }()

    private lazy var elevenLabsTTSClient: ElevenLabsTTSClient = {
        return ElevenLabsTTSClient()
    }()

    /// On-disk cache of the per-voice "Hey, it's Sticky!" preview clips
    /// shown in the menu bar voice picker. Kept here (rather than as a
    /// global) so its lifetime is tied to the manager — and so we can
    /// hand it the same `elevenLabsTTSClient` for downloads.
    private let voicePreviewCache = VoicePreviewCache()

    /// Background prefetch of every voice's preview clip. Started the
    /// first time the user opens the voice picker dropdown, then never
    /// again for the rest of the session — subsequent launches reuse
    /// whatever the prefetch managed to write to disk.
    private var voicePrefetchTask: Task<Void, Never>?

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// Public mirror of "is there at least one completed exchange in the
    /// current voice session?". Drives whether the menu bar panel shows
    /// the "Start fresh voice chat" affordance — the row only makes sense
    /// once the user has actually said something to reset away from. Kept
    /// in sync with `conversationHistory` at the two mutation points
    /// (append after a completed exchange, and `beginFreshVoiceSession`).
    @Published private(set) var hasVoiceConversationHistory: Bool = false

    /// Stable id for the currently-active *voice* session. Each completed
    /// push-to-talk exchange overwrites the same on-disk file under this
    /// id, so the Dashboard's Chats tab shows one growing entry per
    /// conversation rather than a new one per utterance. Reset whenever
    /// `conversationHistory` resets (persona switch, idle timeout, or the
    /// user explicitly tapping "New voice chat") so the next press
    /// archives to a fresh file.
    private var activeVoiceSessionId: String = UUID().uuidString

    /// Mirror of `activeVoiceSessionId`'s archive on disk — kept in
    /// memory so the response handler can append the latest exchange to
    /// it without re-reading from disk every time. Reset alongside
    /// `activeVoiceSessionId`.
    private var activeVoiceSessionMessages: [DashboardChatMessage] = []

    /// Wall-clock time of the last completed push-to-talk exchange.
    /// Used by `startsFreshVoiceSessionIfIdleTooLong` to decide whether
    /// the next press should reuse the existing session or mint a new
    /// one. Nil before the first ever exchange of the launch.
    private var lastVoiceExchangeAt: Date? = nil

    /// True when the next push-to-talk exchange will start a fresh voice
    /// session (because persona changed, idle timeout elapsed, or the
    /// user tapped "New voice chat"). Read by the system-prompt
    /// composer so it can prepend a one-line note telling Sticky it may
    /// have spoken to the user before but doesn't currently remember.
    /// Cleared as soon as the upcoming exchange completes.
    private var voiceSessionIsFreshAfterReset: Bool = true

    /// Idle-timeout window after which the next voice press starts a
    /// fresh session. Six hours is long enough that a single workday
    /// won't accidentally split, short enough that yesterday's chat is
    /// reliably its own entry. Tweakable in one place.
    private static let voiceSessionIdleResetInterval: TimeInterval = 6 * 60 * 60

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    /// Screenshot capture started on push-to-talk key DOWN so it overlaps with
    /// the user speaking instead of running serially after release. The
    /// response pipeline awaits this task instead of issuing its own capture,
    /// shaving ~400-700ms off the perceived latency. Reset on every press so a
    /// new utterance always works against a fresh capture.
    private var preflightScreenCaptureTask: Task<[CompanionScreenCapture], Error>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var personaWheelHotkeyCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var ttsPowerCancellable: AnyCancellable?

    /// Retained so the system voice actually finishes speaking — a local
    /// NSSpeechSynthesizer gets deallocated before it ever utters a word.
    private var fallbackSpeechSynthesizer: NSSpeechSynthesizer?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when all three required permissions (accessibility, screen recording,
    /// microphone) are granted. Used by the panel to show a single "all good" state.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission && hasScreenContentPermission
    }

    /// Whether the blue cursor overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// The Claude model used for voice responses. Persisted to UserDefaults.
    /// Haiku is the default — its TTFT is roughly 2-3x faster than Sonnet,
    /// which dominates the response-pipeline latency budget for voice
    /// answers. Users can switch to Sonnet/Opus from the picker for higher-
    /// quality replies at the cost of perceived speed.
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-haiku-4-5-20251001"

    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedClaudeModel")
        claudeAPI.model = model
    }

    /// The ElevenLabs voice ID used for spoken responses. nil means
    /// "use the default bundled with the app" (read from secrets.plist
    /// inside ElevenLabsTTSClient). Persisted to UserDefaults so the
    /// user's chosen voice survives restarts.
    @Published var selectedVoiceID: String? = UserDefaults.standard.string(forKey: "selectedElevenLabsVoiceID")

    func setSelectedVoiceID(_ voiceID: String?) {
        selectedVoiceID = voiceID
        if let voiceID {
            UserDefaults.standard.set(voiceID, forKey: "selectedElevenLabsVoiceID")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedElevenLabsVoiceID")
        }
    }

    // MARK: - Voice Colors

    /// Color used everywhere "you" are visually represented — the bottom
    /// edge glow when you hold push-to-talk, the all-edges halo while a
    /// teach session is recording, etc. Defaults to the cursor blue so the
    /// user's voice has a stable identity across persona switches, but the
    /// hue list is user-tunable via `userVoiceColorHues` so the mic
    /// indicator can be personalized (or made multicolor) from the panel.
    static let defaultUserVoiceColor: Color = DS.Colors.overlayCursorBlue

    /// Ordered list of hues (0...360°, max 5) that drive the user's
    /// voice color. One hue → solid edge glow (the original behavior).
    /// Two-plus hues → aurora gradient across the bottom edge so the
    /// glow reads as several colors blending into one another. Persisted
    /// as a JSON array under `userVoiceColorHues`.
    @Published var userVoiceColorHues: [Double] = CompanionManager.loadPersistedUserVoiceColorHues()

    /// Default hue (in degrees) that reproduces `DS.Colors.overlayCursorBlue`
    /// when paired with `userVoiceColorSaturation` / `userVoiceColorBrightness`.
    static let defaultUserVoiceColorHue: Double = 217

    /// Hard cap on how many colors can stack in the aurora. Five lands
    /// on a comfortable visual variety without the gradient turning into
    /// soup once each color owns less than ~20% of the edge.
    static let maxUserVoiceColorHues: Int = 5

    /// Saturation + brightness used together with `userVoiceColorHues` to
    /// produce vivid colors in the same family as the original cursor blue.
    /// Keeping these fixed (and only exposing hue) keeps the picker simple
    /// while still landing on saturated, glow-friendly colors at any hue.
    private static let userVoiceColorSaturation: Double = 0.8
    private static let userVoiceColorBrightness: Double = 1.0

    private static let userVoiceColorHuesDefaultsKey = "userVoiceColorHues"
    /// Legacy single-hue key from the first iteration of this picker.
    /// Read once at launch when the new array key is missing so users
    /// who'd already tuned a color don't get reset back to default blue.
    private static let legacyUserVoiceColorHueDefaultsKey = "userVoiceColorHue"

    private static func loadPersistedUserVoiceColorHues() -> [Double] {
        if let storedData = UserDefaults.standard.data(forKey: userVoiceColorHuesDefaultsKey),
           let storedHues = try? JSONDecoder().decode([Double].self, from: storedData),
           !storedHues.isEmpty {
            return Array(storedHues.prefix(maxUserVoiceColorHues))
        }
        if let legacyHue = UserDefaults.standard.object(forKey: legacyUserVoiceColorHueDefaultsKey) as? Double {
            return [legacyHue]
        }
        return [defaultUserVoiceColorHue]
    }

    private func persistUserVoiceColorHues() {
        if let encoded = try? JSONEncoder().encode(userVoiceColorHues) {
            UserDefaults.standard.set(encoded, forKey: Self.userVoiceColorHuesDefaultsKey)
        }
    }

    /// Replaces the entire hue list (clamped to 0...360 each, capped at
    /// `maxUserVoiceColorHues`). Used when the picker is rebuilding the
    /// list wholesale rather than appending a single chip.
    func setUserVoiceColorHues(_ hues: [Double]) {
        let normalizedHues = hues.prefix(Self.maxUserVoiceColorHues).map { hue in
            max(0, min(360, hue))
        }
        userVoiceColorHues = Array(normalizedHues)
        persistUserVoiceColorHues()
    }

    /// Appends a hue to the list. No-op if the list is already full so
    /// the picker can keep calling this and rely on the cap being
    /// enforced here rather than at every call site.
    func addUserVoiceColorHue(_ hue: Double) {
        guard userVoiceColorHues.count < Self.maxUserVoiceColorHues else { return }
        let clampedHue = max(0, min(360, hue))
        userVoiceColorHues.append(clampedHue)
        persistUserVoiceColorHues()
    }

    /// Removes the chip at `index`. If removing leaves the list empty
    /// we don't auto-restore the default — the user voluntarily cleared
    /// it, so we let `userVoiceColor` fall back at read time instead.
    func removeUserVoiceColorHue(at index: Int) {
        guard userVoiceColorHues.indices.contains(index) else { return }
        userVoiceColorHues.remove(at: index)
        persistUserVoiceColorHues()
    }

    /// Single representative color — used by chrome that can only
    /// display one swatch (the small footer icon, conversation chrome
    /// that's not aurora-aware). Falls back to the original cursor blue
    /// when the user has cleared the list entirely.
    var userVoiceColor: Color {
        let primaryHue = userVoiceColorHues.first ?? Self.defaultUserVoiceColorHue
        return Self.color(forHue: primaryHue)
    }

    /// Full color list — used by `EdgeGlowView` to render the aurora.
    /// Always non-empty (falls back to a single default-blue entry) so
    /// the renderer never has to special-case the "user cleared all
    /// chips" state.
    var userVoiceAuroraColors: [Color] {
        if userVoiceColorHues.isEmpty {
            return [Self.color(forHue: Self.defaultUserVoiceColorHue)]
        }
        return userVoiceColorHues.map { Self.color(forHue: $0) }
    }

    private static func color(forHue hueDegrees: Double) -> Color {
        return Color(
            hue: max(0, min(360, hueDegrees)) / 360.0,
            saturation: userVoiceColorSaturation,
            brightness: userVoiceColorBrightness
        )
    }

    /// Color used everywhere Sticky is visually represented — the cursor
    /// itself, the response speech bubbles, the top edge glow while Sticky
    /// is talking back. Tracks the selected ElevenLabs voice via
    /// `voiceColorPalette` so swapping voices in the panel automatically
    /// re-tints all of Sticky's chrome. Falls back to amber when no voice
    /// is selected, which complements the user's blue.
    ///
    /// When a teammate persona is active, the bundle's `accentColor`
    /// takes over so the cursor halo / response bubble / top-edge glow
    /// all read as that person rather than as the user's default Sticky.
    var stickyVoiceColor: Color {
        if let teammate = activeTeammateBundle {
            return teammate.accentColor
        }
        return Self.voiceColor(forVoiceID: selectedVoiceID)
    }

    /// Color used specifically for the *top* edge glow when the persona
    /// is replying. Always sourced from the active persona's accent
    /// color — the same hex shown on that persona's spoke in the
    /// shift+cmd wheel — so switching persona on the wheel and seeing
    /// the reply glow are visually consistent. Distinct from
    /// `stickyVoiceColor` (cursor / bubble) so changing the persona
    /// doesn't recolor the cursor itself; only the reply-side edge
    /// glow shifts to identify *which persona* is talking.
    var personaReplyEdgeGlowColor: Color {
        if let activePersona = PersonaStore.wheelPersonaForSelection(personaSelection) {
            return activePersona.accentColor
        }
        return stickyVoiceColor
    }

    /// Default Sticky color used when no voice override is selected (i.e.
    /// the bundled default voice is in use). Amber complements the user's
    /// blue and matches the "warning" accent used elsewhere in the app.
    static let stickyDefaultVoiceColor: Color = DS.Colors.warning

    /// Hand-tuned palette mapping every free ElevenLabs voice to its own
    /// visual color. Picked so vocal "warmth" tracks color warmth (deep
    /// voices skew indigo/burnt-orange, bright voices skew coral/magenta,
    /// British voices skew muted/cool, etc). Used for both the voice
    /// picker orbs in the panel AND for everything Sticky-themed in the
    /// overlay (cursor, bubbles, top edge glow). Falls back to
    /// `stickyDefaultVoiceColor` if a new voice ID slips in unmapped.
    private static let voiceColorPalette: [String: Color] = [
        "pNInz6obpgDQGcFmaJgB": Color(red: 0.34, green: 0.30, blue: 0.74), // Adam      — deep indigo
        "Xb7hH8MSUJpSbSDYk0k2": Color(red: 0.18, green: 0.66, blue: 0.65), // Alice     — teal
        "hpp4J3VqNfWAUOO0d1Us": Color(red: 0.96, green: 0.50, blue: 0.55), // Bella     — coral pink
        "pqHfZKP75CvOlQylNhV4": Color(red: 0.78, green: 0.55, blue: 0.20), // Bill      — bronze
        "nPczCjzI2devNBz1zQrb": Color(red: 0.85, green: 0.45, blue: 0.20), // Brian     — burnt orange
        "N2lVS1w4EtoT3dr4eOWO": Color(red: 0.45, green: 0.60, blue: 0.32), // Callum    — moss green
        "IKne3meq5aSn9XLyUdCD": Color(red: 0.16, green: 0.66, blue: 0.45), // Charlie   — emerald
        "iP95p4xoKVk53GoZ742B": Color(red: 0.35, green: 0.66, blue: 0.92), // Chris     — sky blue
        "onwK4e9ZLuTAKqWW03F9": Color(red: 0.40, green: 0.50, blue: 0.65), // Daniel    — slate blue
        "cjVigY5qzO86Huf0OWal": Color(red: 0.18, green: 0.45, blue: 0.32), // Eric      — forest green
        "JBFqnCBsd6RMkjVDRZzb": Color(red: 0.82, green: 0.42, blue: 0.30), // George    — terracotta
        "SOYHLrjzK2X1ezoPC6cr": Color(red: 0.82, green: 0.20, blue: 0.25), // Harry     — crimson
        "cgSgspJ2msm6clMCkdW9": Color(red: 0.86, green: 0.32, blue: 0.62), // Jessica   — magenta
        "FGY2WhTYpPnrIDTdsKH5": Color(red: 0.62, green: 0.36, blue: 0.80), // Laura     — violet
        "TX3LPaxmHKxFdv7VOQHJ": Color(red: 0.95, green: 0.55, blue: 0.18), // Liam      — orange
        "pFZP5JQG7iQjIQuC4Bku": Color(red: 0.70, green: 0.55, blue: 0.78), // Lily      — lavender
        "XrExE9yKIg1WjnnlVkGX": Color(red: 0.88, green: 0.72, blue: 0.25), // Matilda   — mustard
        "SAz9YHcvj6GT2YYXdXww": Color(red: 0.55, green: 0.62, blue: 0.68), // River     — cool steel
        "CwhRBWXzGAHq8TQ4Fs17": Color(red: 0.55, green: 0.58, blue: 0.30), // Roger     — olive
        "EXAVITQu4vr4xnSDxMaL": Color(red: 0.92, green: 0.45, blue: 0.55), // Sarah     — rose
        "bIHbv24MWmeRgasZH58o": Color(red: 0.50, green: 0.65, blue: 0.50), // Will      — sage
    ]

    /// Public lookup. The panel's voice picker also uses this so the orb
    /// next to each row matches what the user will see in the overlay.
    static func voiceColor(forVoiceID voiceID: String?) -> Color {
        guard let voiceID, let color = voiceColorPalette[voiceID] else {
            return stickyDefaultVoiceColor
        }
        return color
    }

    // MARK: - Voice Preview

    /// The voice ID that's currently playing a preview clip in the panel,
    /// or nil if no preview is playing. Sentinel `defaultVoicePreviewSentinel`
    /// means the bundled default voice is being previewed (so the picker
    /// UI can show a stop icon on the Default row even when no override
    /// voice ID is set). Read by the panel to swap play ↔ stop icons.
    @Published private(set) var previewingVoiceID: String? = nil

    /// Sentinel used in `previewingVoiceID` to represent the bundled
    /// default voice (no override). Distinct from nil, which means
    /// "no preview is currently playing".
    static let defaultVoicePreviewSentinel: String = "__sticky_default_voice__"

    private var voicePreviewTask: Task<Void, Never>?

    /// Plays the cached "Hey, it's Sticky!" preview clip for the given
    /// voice. If the clip isn't on disk yet (e.g. user clicked play
    /// before the background prefetch reached this voice), it's
    /// downloaded inline first. Cancels any in-flight preview before
    /// starting so rapid clicking doesn't stack up overlapping playback.
    /// Does NOT change the persisted `selectedVoiceID` — selection is a
    /// separate action.
    func previewVoice(_ voiceID: String?) {
        voicePreviewTask?.cancel()
        elevenLabsTTSClient.stopPlayback()

        voicePreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.previewingVoiceID = voiceID ?? Self.defaultVoicePreviewSentinel
            do {
                let clipURL = try await self.voicePreviewCache.cachedOrDownloadedClipURL(
                    forVoiceID: voiceID,
                    using: self.elevenLabsTTSClient
                )
                try Task.checkCancellation()
                let audioData = try Data(contentsOf: clipURL)
                try Task.checkCancellation()
                try self.elevenLabsTTSClient.playAudioData(audioData)

                // playAudioData returns once playback starts — poll until
                // it actually finishes so the panel UI keeps the stop
                // icon visible for the full duration of the clip.
                while self.elevenLabsTTSClient.isPlaying {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                }
            } catch {
                print("⚠️ Voice preview error: \(error)")
            }
            if !Task.isCancelled {
                self.previewingVoiceID = nil
            }
        }
    }

    /// Cancels any in-flight preview clip immediately. Called when the
    /// user taps the stop icon on a row that's actively previewing.
    func stopVoicePreview() {
        voicePreviewTask?.cancel()
        voicePreviewTask = nil
        elevenLabsTTSClient.stopPlayback()
        previewingVoiceID = nil
    }

    /// Kicks off a background download of every free voice's preview
    /// clip the first time the user opens the voice picker. Subsequent
    /// calls within the same session are no-ops — the prefetch task
    /// runs once. Failures on individual voices are logged but don't
    /// abort the rest of the prefetch.
    func prefetchAllVoicePreviewsIfNeeded() {
        guard voicePrefetchTask == nil else { return }

        // Build the full list of voice IDs we want cached: the bundled
        // default (nil) first so it's ready before any specific override,
        // then every free voice in display order.
        let voiceIDs: [String?] = [nil] + ElevenLabsTTSClient.freeVoices.map { $0.id }

        voicePrefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.voicePreviewCache.prefetchAll(
                voiceIDs: voiceIDs,
                using: self.elevenLabsTTSClient
            )
        }
    }

    /// User preference for whether the Sticky cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isClickyCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isClickyCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isClickyCursorEnabled")

    // MARK: - Reverse Clicky: Taste Scope

    /// Personal vs. team scope for taste injection. Personal uses just the
    /// user's own principles; Team also unions in the shared team-profile.json
    /// (the boss/employee demo). Persisted to UserDefaults.
    @Published var tasteScope: TasteScope = {
        if let rawTasteScope = UserDefaults.standard.string(forKey: "tasteScope"),
           let storedTasteScope = TasteScope(rawValue: rawTasteScope) {
            return storedTasteScope
        }
        return .personal
    }()

    func setTasteScope(_ newTasteScope: TasteScope) {
        tasteScope = newTasteScope
        UserDefaults.standard.set(newTasteScope.rawValue, forKey: "tasteScope")
    }

    // MARK: - Reverse Clicky: Applied-Taste Transparency
    //
    // After every voice reply, Claude returns a `[USED:P1,T2]` tag listing
    // which principles it actually leaned on. We resolve those short
    // labels back into TastePrinciple objects via the mapping the
    // TasteContextBlock builder hands back, and stash them here so the
    // AppliedPrinciplesChip in the cursor overlay can render them.
    //
    // All three properties are transient — reset at the start of every
    // voice request.

    /// Principles Sticky's most recent reply genuinely leaned on, in the
    /// order Claude listed them. Empty when no reply yet or when Claude
    /// returned `[USED:none]`.
    @Published var lastAppliedPrinciples: [TastePrinciple] = []

    /// True if at least one principle in `lastAppliedPrinciples` came
    /// from the team profile (vs. the user's personal profile). Drives a
    /// trailing "Team" pill on the chip's expanded view.
    @Published var lastAppliedSourceWasTeam: Bool = false

    /// Per-principle origin lookup for the chip — the set of ids whose
    /// principle came from the team profile. Used to render the right
    /// "Personal" / "Team" pill on each expanded row.
    @Published var teamOriginPrincipleIds: Set<String> = []

    /// Whether the AppliedPrinciplesChip should currently render. Set to
    /// true once a reply that leaned on at least one principle is fully
    /// resolved (so the chip appears as the response settles), flipped
    /// back to false when the user starts the next push-to-talk request
    /// OR after the same fade window the response bubble would use.
    @Published var isShowingAppliedPrinciplesChip: Bool = false

    /// Cancellable that fades the chip out roughly when a response bubble
    /// would have faded. Kept here so a new request can cancel the
    /// previous fade-out before it fires (otherwise the chip from the
    /// new request would inherit a stale hide timer).
    private var appliedPrinciplesChipHideTask: Task<Void, Never>?

    /// Most recent `TasteContextBlock` for the in-flight voice request.
    /// Cached at prompt-build time so the response handler can resolve
    /// the `[USED:...]` short labels back to principles without
    /// re-reading the taste files. nil when the profile is empty.
    private var inFlightTasteContextBlock: TasteContextBlock?

    // MARK: - Reverse Clicky: Persona Selection

    /// Which identity Sticky is currently wearing.
    ///
    /// - `.me` (default) → the user's own configured experience: their
    ///   selected ElevenLabs voice, their saved personal TasteProfile,
    ///   the default colored orb cursor.
    /// - `.team` → same chrome as `.me` but the system prompt unions in
    ///   the team taste profile (Personal ∪ Team).
    /// - `.teammate(id)` → borrow another person's full persona bundle:
    ///   their soul.md, their voice, their taste, and their avatar take
    ///   over until the user picks something else from the wheel.
    ///
    /// Persisted across launches via UserDefaults using the persona's
    /// `persistenceKey`.
    @Published private(set) var personaSelection: PersonaSelection = {
        if let rawValue = UserDefaults.standard.string(forKey: "personaSelection"),
           let storedSelection = PersonaSelection.fromPersistenceKey(rawValue) {
            // If the stored selection points at a teammate that no longer
            // exists in the wheel (e.g. Reuban — who is now folded into
            // `.me` — or a teammate that's been removed since the
            // preference was written), fall back to `.me` so the user
            // doesn't end up with an inert persona on launch.
            if case .teammate(let id) = storedSelection,
               PersonaStore.teammate(withId: id) == nil {
                return .me
            }
            return storedSelection
        }
        return .me
    }()

    /// Updates the active persona and persists it. Also keeps `tasteScope`
    /// in sync for `.me` / `.team` so any code path still reading
    /// tasteScope directly (legacy panel rows, prompt composition,
    /// analytics) doesn't see a stale value. `.teammate` leaves
    /// tasteScope alone — the teammate's bundle replaces both scope and
    /// taste anyway.
    func setPersonaSelection(_ newSelection: PersonaSelection) {
        let isActuallyChangingPersona = (newSelection != personaSelection)

        personaSelection = newSelection
        UserDefaults.standard.set(newSelection.persistenceKey, forKey: "personaSelection")

        // Switching personas should feel like starting a fresh conversation
        // with a different person — the new persona should NOT see what the
        // previous one just said. Wipe the rolling voice conversation
        // history (and cancel any in-flight response from the old persona)
        // so the next push-to-talk press starts the new persona on a blank
        // slate.
        if isActuallyChangingPersona {
            conversationHistory.removeAll()
            currentResponseTask?.cancel()
            currentResponseTask = nil
            // Switching personas is a real conversational reset — start
            // a brand-new on-disk voice session so the next press doesn't
            // append the new persona's replies to the old persona's chat
            // entry in the dashboard.
            beginFreshVoiceSession(reason: "persona changed")
            print("🧠 Persona changed → cleared conversation history")
        }

        switch newSelection {
        case .me:
            if tasteScope != .personal {
                setTasteScope(.personal)
            }
        case .team:
            if tasteScope != .team {
                setTasteScope(.team)
            }
        case .teammate:
            break
        }
    }

    /// The active teammate's full persona bundle when persona is
    /// `.teammate(id)`, otherwise nil. Read by the prompt composer (to
    /// inject soul + taste), the TTS path (to override voice), and the
    /// cursor renderer (to swap in the avatar).
    var activeTeammateBundle: PersonaBundle? {
        if case .teammate(let id) = personaSelection {
            return PersonaStore.teammate(withId: id)
        }
        return nil
    }

    /// The avatar Sticky's cursor should render right now, or nil to
    /// keep the default colored orb. Returns the active teammate's
    /// avatar when one is active, and the pseudo-persona's SF Symbol
    /// avatar (`person.fill` / `person.2.fill`) for `.me` / `.team` so
    /// every persona selection shows a recognisable face on the cursor
    /// instead of a generic colored orb.
    var activePersonaAvatar: PersonaAvatar? {
        switch personaSelection {
        case .me:
            return PersonaStore.mePseudoPersona.avatar
        case .team:
            return PersonaStore.teamPseudoPersona.avatar
        case .teammate:
            return activeTeammateBundle?.avatar
        }
    }

    // MARK: - Reverse Clicky: Persona Wheel

    /// True while the radial wheel picker is being held open. The
    /// overlay reads this to decide whether to render the wheel layer.
    /// Toggled by the `PersonaWheelHotkeyMonitor` press / release events.
    @Published private(set) var isPersonaWheelVisible: Bool = false

    /// Where on screen the wheel is anchored — set to the cursor
    /// position at the moment the user pressed the hotkey, then frozen
    /// while held so the user can move OUT to a spoke instead of
    /// dragging the wheel along with the cursor. Coordinates are in
    /// AppKit screen space (origin bottom-left). Nil when not visible.
    @Published private(set) var personaWheelCenterScreenLocation: CGPoint? = nil

    /// Id of the persona currently being hovered toward in the wheel,
    /// or nil when the cursor is in the dead-zone in the middle. Updated
    /// every cursor-tracking frame by `BlueCursorView` while the wheel
    /// is visible. Read by `PersonaWheelView` to highlight the right
    /// spoke; consumed on release to commit the selection.
    @Published var hoveredWheelPersonaId: String? = nil

    /// Personas to show in the wheel, in clockwise display order
    /// starting at 12 o'clock. Convenience accessor so the overlay
    /// doesn't have to import PersonaStore directly.
    var allWheelPersonas: [PersonaBundle] {
        return PersonaStore.allWheelPersonas
    }

    /// Id of the currently-active persona in wheel-display terms (i.e.
    /// the special "__me__" / "__team__" id for the pseudo-personas, or
    /// the teammate's id). Used by the wheel to draw a "currently
    /// active" indicator on the right spoke so the user can tell which
    /// release-position is a no-op.
    var activeWheelPersonaId: String {
        return PersonaStore.wheelPersonaForSelection(personaSelection)?.id
            ?? PersonaStore.mePseudoPersona.id
    }

    /// Sets up the persona-wheel hotkey subscription. Mirrors
    /// `bindShortcutTransitions()` — kept as a separate method so the
    /// two listeners stay clearly independent in the call graph.
    private func bindPersonaWheelHotkeyTransitions() {
        personaWheelHotkeyCancellable = personaWheelHotkeyMonitor
            .hotkeyTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handlePersonaWheelHotkeyTransition(transition)
            }
    }

    /// Press → freeze the wheel center at the current cursor location
    /// and show the wheel. Release → read whatever spoke is hovered and
    /// commit it as the new persona selection (or no-op if the user
    /// released in the dead zone).
    private func handlePersonaWheelHotkeyTransition(_ transition: PersonaWheelHotkeyMonitor.HotkeyTransition) {
        switch transition {
        case .pressed:
            // Don't summon the wheel during onboarding video — the user
            // is being shown a focused tutorial moment and shouldn't
            // accidentally trigger picker chrome on top of it.
            guard !showOnboardingVideo else { return }

            // Bring the overlay back transiently if the user has Sticky
            // hidden — the wheel renders inside the overlay so it needs
            // to be on screen.
            if !isClickyCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            personaWheelCenterScreenLocation = NSEvent.mouseLocation
            hoveredWheelPersonaId = nil
            isPersonaWheelVisible = true

        case .released:
            commitPersonaWheelSelectionIfHovered()
            isPersonaWheelVisible = false
            personaWheelCenterScreenLocation = nil
            hoveredWheelPersonaId = nil
        }
    }

    /// Translates the currently-hovered wheel persona id back into a
    /// `PersonaSelection` and stores it. No-op when the user released
    /// in the dead zone or when the hovered id has been removed since.
    private func commitPersonaWheelSelectionIfHovered() {
        guard let hoveredId = hoveredWheelPersonaId else { return }
        guard let hoveredPersona = allWheelPersonas.first(where: { $0.id == hoveredId }) else { return }

        let newSelection = PersonaStore.selectionForWheelPersona(hoveredPersona)
        guard newSelection != personaSelection else { return }

        setPersonaSelection(newSelection)
        print("🎡 Persona wheel selected: \(hoveredPersona.displayName) (\(hoveredId))")
    }

    /// Current state of the in-progress teach session, if any. Independent
    /// of voiceState — the teach session has its own dictation pipeline.
    @Published private(set) var teachSessionState: TeachSessionState = .idle

    /// Seconds elapsed since the current teach session started. Drives the
    /// "Teaching — 0:42" label in the panel.
    @Published private(set) var teachSessionElapsedSeconds: Int = 0

    /// In-memory frame buffer for the current teach session. Each entry is a
    /// JPEG screenshot of the cursor screen taken during the session, paired
    /// with the seconds elapsed since session start. Cleared between sessions.
    private var teachSessionFrames: [(data: Data, timestamp: TimeInterval)] = []
    private var teachSessionStartedAt: Date?
    private var teachSessionScreenshotTimer: Timer?
    private var teachSessionElapsedTimer: Timer?
    /// Watchdog that resets the panel state to .idle if the dictation
    /// callback never fires after the user clicks Stop. Protects against
    /// the AssemblyAI websocket dying mid-session and leaving the UI hung.
    private var teachSessionTranscriptWatchdog: Task<Void, Never>?

    /// Most recent teach session result, for debugging.
    @Published private(set) var lastTeachSessionResult: TeachSessionResult?

    /// Ambiguous moments waiting for the user to resolve via the review-card
    /// stack. Each one becomes a card with a frame thumbnail and 4 options.
    /// When this is non-empty, the panel shows the review UI; when the user
    /// finishes (or skips/ends), it goes back to empty.
    @Published private(set) var pendingAmbiguousMoments: [AmbiguousMoment] = []

    /// The frames the analyzer actually used, kept in sync with the order
    /// Claude saw them. `AmbiguousMoment.frameIndex` indexes into this array.
    /// Cleared when the review queue is empty so we don't hold a few MB of
    /// JPEG data after every session.
    @Published private(set) var pendingReviewFrames: [(data: Data, timestamp: TimeInterval)] = []

    /// Lightweight undo stack for the review queue. Each entry captures the
    /// moment that was just answered or skipped plus the id of the principle
    /// (if any) that was written to disk. Bounded at 5 entries so we don't
    /// retain unbounded review history. `unadvanceReviewQueue()` pops the
    /// most recent entry, deletes the associated principle (if any), and
    /// re-prepends the moment to `pendingAmbiguousMoments` — making misclicks
    /// recoverable without reloading the entire review session.
    private var recentlyAdvancedMoments: [(moment: AmbiguousMoment, savedPrincipleId: String?)] = []
    private let recentlyAdvancedMomentsMaxDepth: Int = 5

    /// Most recent count of confident principles auto-saved from a finished
    /// teach session. Drives the small "Saved N principle(s)" toast in the
    /// panel so the user gets feedback even when the session has no
    /// ambiguous moments to review.
    @Published private(set) var lastTeachSessionSavedPrincipleCount: Int = 0

    /// Analyzer output that's waiting for the user to confirm before
    /// anything hits disk. When non-nil, the panel shows the
    /// TeachSessionResultCard with a checklist of confident principles, an
    /// "+ N moments to talk about" hint for ambiguous ones, and Save /
    /// Discard buttons. Until the user clicks Save, no principle has been
    /// written to taste-profile.json — Discard wipes everything cleanly.
    @Published private(set) var pendingTeachSessionResult: PendingTeachSessionReview?

    /// Human-readable status for what the analyzer is doing *right now* during
    /// the `.analyzing` phase of a teach session. Drives the granular pill
    /// text in CompanionPanelView so the user sees "Picking the best frames…"
    /// → "Asking Claude what stood out…" → "Pulling out principles…" instead
    /// of a single static loading message. Nil whenever teachSessionState is
    /// not `.analyzing`.
    @Published private(set) var teachAnalyzingStatus: String?

    func setClickyCursorEnabled(_ enabled: Bool) {
        isClickyCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isClickyCursorEnabled")
        transientHideTask?.cancel()
        transientHideTask = nil

        if enabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        } else {
            overlayWindowManager.hideOverlay()
            isOverlayVisible = false
        }
    }

    /// Onboarding is disabled — always treat the user as already onboarded so
    /// the Start button and intro video flow never appear.
    var hasCompletedOnboarding: Bool {
        get { true }
        set { /* no-op: onboarding is disabled */ }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Sticky start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindTTSPowerLevel()
        bindShortcutTransitions()
        bindPersonaWheelHotkeyTransitions()
        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = claudeAPI

        // Pre-fetch the AssemblyAI streaming token in the background so the
        // very first push-to-talk press doesn't pay the ~100-200ms HTTP
        // round-trip to the worker. Subsequent presses are kept hot from
        // BuddyDictationManager.finishCurrentDictationSessionIfNeeded.
        buddyDictationManager.prewarmTranscriptionCredentialsIfNeeded()

        // If the user already completed onboarding AND all permissions are
        // still granted, show the cursor overlay immediately. If permissions
        // were revoked (e.g. signing change), don't show the cursor — the
        // panel will show the permissions UI instead.
        if hasCompletedOnboarding && allPermissionsGranted && isClickyCursorEnabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }
    }

    /// Called by BlueCursorView after the buddy finishes its pointing
    /// animation and returns to cursor-following mode.
    /// Triggers the onboarding sequence — dismisses the panel and restarts
    /// the overlay so the welcome animation and intro video play.
    func triggerOnboarding() {
        // Post notification so the panel manager can dismiss the panel
        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true

        // Play Besaid theme at 60% volume, fade out after 1m 30s
        startOnboardingMusic()

        // Show the overlay for the first time — isFirstAppearance triggers
        // the welcome animation and onboarding video
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    /// Replays the onboarding experience from the "Watch Onboarding Again"
    /// footer link. Same flow as triggerOnboarding but the cursor overlay
    /// is already visible so we just restart the welcome animation and video.
    func replayOnboarding() {
        NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)
        startOnboardingMusic()
        // Tear down any existing overlays and recreate with isFirstAppearance = true
        overlayWindowManager.hasShownOverlayBefore = false
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    private func stopOnboardingMusic() {
        onboardingMusicFadeTimer?.invalidate()
        onboardingMusicFadeTimer = nil
        onboardingMusicPlayer?.stop()
        onboardingMusicPlayer = nil
    }

    private func startOnboardingMusic() {
        stopOnboardingMusic()
        guard let musicURL = Bundle.main.url(forResource: "ff", withExtension: "mp3") else {
            print("⚠️ Sticky: ff.mp3 not found in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: musicURL)
            player.volume = 0.3
            player.play()
            self.onboardingMusicPlayer = player

            // After 1m 30s, fade the music out over 3s
            onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { [weak self] _ in
                self?.fadeOutOnboardingMusic()
            }
        } catch {
            print("⚠️ Sticky: Failed to play onboarding music: \(error)")
        }
    }

    private func fadeOutOnboardingMusic() {
        guard let player = onboardingMusicPlayer else { return }

        let fadeSteps = 30
        let fadeDuration: Double = 3.0
        let stepInterval = fadeDuration / Double(fadeSteps)
        let volumeDecrement = player.volume / Float(fadeSteps)
        var stepsRemaining = fadeSteps

        onboardingMusicFadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            stepsRemaining -= 1
            player.volume -= volumeDecrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.stop()
                self?.onboardingMusicPlayer = nil
                self?.onboardingMusicFadeTimer = nil
            }
        }
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementBubbleText = nil
    }

    // MARK: - Teach Session

    /// The menu bar panel's click-outside dismiss handler should consult this
    /// before dismissing. Returns true when there's transient teach-flow state
    /// the user could lose (mid-recording, mid-analysis, mid-review-queue, or
    /// looking at a pre-save result card). Idle ask state returns false
    /// so normal panel behavior is preserved.
    var shouldKeepPanelOpenForActiveTeachState: Bool {
        if teachSessionState != .idle { return true }
        if !pendingAmbiguousMoments.isEmpty { return true }
        if pendingTeachSessionResult != nil { return true }
        return false
    }

    /// Maximum length of a teach session before we auto-stop it. Keeps the
    /// frame count and transcript size manageable for the analyzer call.
    private static let teachSessionMaxLengthSeconds: Int = 5 * 60

    /// Interval between automatic screenshots during a teach session.
    private static let teachSessionScreenshotIntervalSeconds: TimeInterval = 4.0

    /// How long to wait for a final transcript after the user clicks Stop
    /// before giving up and resetting state. Bigger than the AssemblyAI
    /// fallback delay so we don't race the dictation manager.
    private static let teachSessionTranscriptTimeoutSeconds: TimeInterval = 6.0

    /// Begins a Reverse Clicky teach session: opens continuous dictation,
    /// starts a periodic screenshot timer, and starts the elapsed-time clock.
    /// Idempotent — does nothing if a session is already running.
    func startTeachSession() {
        guard teachSessionState == .idle else { return }

        // Don't tangle teach sessions with an in-flight push-to-talk response.
        // Cancel any ongoing AI work so the mic is free.
        currentResponseTask?.cancel()
        currentResponseTask = nil
        elevenLabsTTSClient.stopPlayback()

        teachSessionFrames.removeAll()
        teachSessionStartedAt = Date()
        teachSessionElapsedSeconds = 0
        teachSessionState = .recording

        // Clear the previous session's "Saved N principles" toast and any
        // leftover review queue so the panel only shows the current session
        // once we're done analyzing.
        lastTeachSessionSavedPrincipleCount = 0
        pendingAmbiguousMoments.removeAll()
        pendingReviewFrames.removeAll()

        // Capture an initial frame at t=0 immediately, then on every tick.
        Task { @MainActor [weak self] in
            await self?.captureTeachSessionFrame()
        }

        teachSessionScreenshotTimer = Timer.scheduledTimer(
            withTimeInterval: Self.teachSessionScreenshotIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureTeachSessionFrame()
            }
        }

        teachSessionElapsedTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTeachSessionElapsedClock()
            }
        }

        Task { [weak self] in
            await self?.buddyDictationManager.startTeachSession { [weak self] finalTranscript in
                Task { @MainActor [weak self] in
                    self?.handleTeachSessionFinalTranscript(finalTranscript)
                }
            }
        }

        print("🎓 Teach session started")
    }

    /// Stops the current teach session, kicks off analysis with whatever
    /// transcript and frames we collected, and arms a watchdog so the UI
    /// resets even if the dictation manager never delivers a transcript.
    func stopTeachSession() {
        guard teachSessionState == .recording else { return }

        teachSessionScreenshotTimer?.invalidate()
        teachSessionScreenshotTimer = nil
        teachSessionElapsedTimer?.invalidate()
        teachSessionElapsedTimer = nil
        teachSessionState = .analyzing

        buddyDictationManager.stopTeachSession()

        teachSessionTranscriptWatchdog?.cancel()
        teachSessionTranscriptWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(Self.teachSessionTranscriptTimeoutSeconds)
            )
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.teachSessionState == .analyzing else { return }
            print("⚠️ Teach session: transcript watchdog fired — resetting state")
            self.resetTeachSessionState()
        }

        print("🎓 Teach session stopping — frames captured: \(teachSessionFrames.count)")
    }

    private func tickTeachSessionElapsedClock() {
        guard teachSessionState == .recording else { return }
        guard let startedAt = teachSessionStartedAt else { return }

        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        teachSessionElapsedSeconds = elapsedSeconds

        // Hard cap so the user doesn't accidentally leave a session running
        // forever and overwhelm the analyzer with hundreds of frames.
        if elapsedSeconds >= Self.teachSessionMaxLengthSeconds {
            print("🎓 Teach session: hit max length, auto-stopping")
            stopTeachSession()
        }
    }

    private func captureTeachSessionFrame() async {
        guard teachSessionState == .recording else { return }
        guard let startedAt = teachSessionStartedAt else { return }

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            // Prefer the cursor screen so the frame timeline tracks the user's
            // active workspace. Fall back to the first screen if no cursor
            // screen was identified for some reason.
            let cursorScreenCapture = screenCaptures.first(where: { $0.isCursorScreen })
                ?? screenCaptures.first
            guard let frameCapture = cursorScreenCapture else { return }

            let elapsedSecondsAtCapture = Date().timeIntervalSince(startedAt)
            teachSessionFrames.append((
                data: frameCapture.imageData,
                timestamp: elapsedSecondsAtCapture
            ))
        } catch {
            print("⚠️ Teach session screenshot failed: \(error)")
        }
    }

    private func handleTeachSessionFinalTranscript(_ finalTranscript: String) {
        teachSessionTranscriptWatchdog?.cancel()
        teachSessionTranscriptWatchdog = nil

        let trimmedTranscript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranscript.isEmpty else {
            print("⚠️ Teach session: empty transcript — nothing to analyze")
            resetTeachSessionState()
            return
        }

        guard !teachSessionFrames.isEmpty else {
            print("⚠️ Teach session: no frames captured — nothing to analyze")
            resetTeachSessionState()
            return
        }

        print("🎓 Teach session transcript: \(trimmedTranscript)")
        print("🎓 Teach session frames: \(teachSessionFrames.count)")

        let capturedFrames = teachSessionFrames
        teachSessionFrames.removeAll()

        let analyzerClaudeAPI = claudeAPI
        let frameCount = capturedFrames.count

        // Kick off the staged status message right before the analyzer call.
        // The first stage is fast (frame picking happens synchronously inside
        // analyzeTeachSession), so the user sees this for a beat before the
        // longer "Asking Claude…" stage takes over.
        teachAnalyzingStatus = "Reviewing \(frameCount) frame\(frameCount == 1 ? "" : "s") from your session…"

        Task { @MainActor [weak self] in
            do {
                // Switch to the longer-running stage on the next runloop tick
                // so the first message has a chance to render. Most of the
                // analyzing wall-clock time is spent inside this call waiting
                // on Claude's vision response, so this message dominates.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self else { return }
                    guard self.teachSessionState == .analyzing else { return }
                    self.teachAnalyzingStatus = "Looking for what stood out…"
                }

                let analysis = try await SessionAnalyzer.analyzeTeachSession(
                    transcript: trimmedTranscript,
                    frames: capturedFrames,
                    claudeAPI: analyzerClaudeAPI
                )

                self?.teachAnalyzingStatus = "Pulling out principles…"
                self?.lastTeachSessionResult = analysis.result
                Self.printTeachSessionResultForDebugging(analysis.result)

                // Don't auto-save anything yet — surface the result to the
                // user via TeachSessionResultCard so they can uncheck
                // principles or discard the whole session before any disk
                // write happens. Save fires confirmTeachSessionSave; discard
                // fires discardTeachSessionResult.
                self?.lastTeachSessionSavedPrincipleCount = 0
                self?.pendingAmbiguousMoments.removeAll()
                self?.pendingReviewFrames.removeAll()
                self?.pendingTeachSessionResult = PendingTeachSessionReview(
                    result: analysis.result,
                    selectedFrames: analysis.selectedFrames
                )

                self?.resetTeachSessionState()
            } catch {
                print("⚠️ Teach session analysis failed: \(error)")
                self?.resetTeachSessionState()
            }
        }
    }

    // MARK: - Teach Session Result Confirmation

    /// User clicked Save on the result card. Persists the subset of
    /// confident principles whose ids are in `selectedConfidentPrincipleIds`,
    /// then promotes any ambiguous moments into the existing review queue
    /// so the MCQ cards take over. Clears the pending result either way.
    func confirmTeachSessionSave(selectedConfidentPrincipleIds: Set<String>) {
        guard let pendingReview = pendingTeachSessionResult else { return }

        let principlesToPersist = pendingReview.result.confident.filter { candidatePrinciple in
            selectedConfidentPrincipleIds.contains(candidatePrinciple.id)
        }

        // Stamp approval + freshen timestamps so the on-disk profile shows
        // when the user actually accepted them, not when Claude generated.
        let approvalDate = Date()
        let stampedPrinciplesToPersist: [TastePrinciple] = principlesToPersist.map { rawPrinciple in
            var stampedPrinciple = rawPrinciple
            stampedPrinciple.approved = true
            stampedPrinciple.createdAt = approvalDate
            stampedPrinciple.updatedAt = approvalDate
            return stampedPrinciple
        }

        var savedPrincipleCount = 0
        if !stampedPrinciplesToPersist.isEmpty {
            do {
                savedPrincipleCount = try TasteProfileStore.appendApprovedPrinciples(stampedPrinciplesToPersist)
                print("🧠 Teach session: saved \(savedPrincipleCount) principle(s) to \(TasteProfileStore.profileFileLocation())")
                mirrorPrinciplesToOwnerTasteFile(stampedPrinciplesToPersist)
            } catch {
                print("⚠️ Teach session: failed to save principles: \(error)")
            }
        }
        lastTeachSessionSavedPrincipleCount = savedPrincipleCount

        // Mirror each saved principle into the dashboard's recordings
        // archive so the mini panel's recent-activity feed can show
        // "you taught Sticky X" entries.
        for savedPrinciple in stampedPrinciplesToPersist {
            DashboardRecordingHistoryStore.recordTeachMoment(
                transcript: savedPrinciple.evidence.first ?? savedPrinciple.statement,
                extractedPrinciple: savedPrinciple,
                wasApproved: true
            )
        }

        // Promote ambiguous moments into the review queue so the existing
        // ReviewCardStack picks up where the result card leaves off. Frames
        // are only worth keeping if there's something to review.
        let ambiguousMomentsToReview = pendingReview.result.ambiguous
        pendingAmbiguousMoments = ambiguousMomentsToReview
        pendingReviewFrames = ambiguousMomentsToReview.isEmpty
            ? []
            : pendingReview.selectedFrames

        pendingTeachSessionResult = nil
    }

    /// User clicked Discard. Throws away the analyzer output without
    /// touching disk. Also clears the saved-toast counter so a stale
    /// "Saved 3" toast from an earlier session doesn't reappear.
    func discardTeachSessionResult() {
        guard let discardedReview = pendingTeachSessionResult else { return }
        print("🧠 Teach session: discarded by user — nothing saved")
        // Log the discarded session in the activity archive so the
        // recent-activity feed shows "you skipped X".
        for skippedPrinciple in discardedReview.result.confident {
            DashboardRecordingHistoryStore.recordTeachMoment(
                transcript: skippedPrinciple.evidence.first ?? skippedPrinciple.statement,
                extractedPrinciple: skippedPrinciple,
                wasApproved: false
            )
        }
        pendingTeachSessionResult = nil
        lastTeachSessionSavedPrincipleCount = 0
        pendingAmbiguousMoments.removeAll()
        pendingReviewFrames.removeAll()
    }

    /// Appends every confident principle from the analyzer result to the
    /// user's personal taste profile on disk. Logs the count saved and the
    /// file location so the user can find it during the demo. Errors are
    /// caught and logged — a write failure shouldn't break the panel.
    /// Returns the number of principles actually written (after dedup).
    @discardableResult
    private func persistConfidentPrinciplesFromTeachSession(_ result: TeachSessionResult) -> Int {
        guard !result.confident.isEmpty else {
            print("🧠 Teach session: no confident principles to save")
            return 0
        }

        do {
            let savedCount = try TasteProfileStore.appendApprovedPrinciples(result.confident)
            print("🧠 Teach session: saved \(savedCount) principle(s) to \(TasteProfileStore.profileFileLocation())")
            mirrorPrinciplesToOwnerTasteFile(result.confident)
            return savedCount
        } catch {
            print("⚠️ Teach session: failed to save principles: \(error)")
            return 0
        }
    }

    // MARK: - Teach Session Review Actions

    /// Picks one of the four candidate principles for the current ambiguous
    /// moment, persists it to the central mind, and advances the queue. If
    /// the queue is now empty, the panel will collapse the review UI.
    func approveOption(optionIndex: Int) {
        guard let currentMoment = pendingAmbiguousMoments.first else { return }
        guard optionIndex >= 0 else { return }
        guard optionIndex < currentMoment.principleByOption.count else { return }

        var chosenPrinciple = currentMoment.principleByOption[optionIndex]
        // Stamp the principle as approved at the moment the user picks it,
        // and freshen the timestamps so the on-disk profile shows when it
        // landed (not when Claude generated it).
        chosenPrinciple.approved = true
        let approvalDate = Date()
        chosenPrinciple.createdAt = approvalDate
        chosenPrinciple.updatedAt = approvalDate

        var savedPrincipleIdForUndo: String? = nil
        do {
            try TasteProfileStore.appendApprovedPrinciples([chosenPrinciple])
            savedPrincipleIdForUndo = chosenPrinciple.id
            print("🧠 Review: approved principle — \(chosenPrinciple.statement)")
            mirrorPrinciplesToOwnerTasteFile([chosenPrinciple])
            DashboardRecordingHistoryStore.recordTeachMoment(
                transcript: chosenPrinciple.evidence.first ?? chosenPrinciple.statement,
                extractedPrinciple: chosenPrinciple,
                wasApproved: true
            )
        } catch {
            print("⚠️ Review: failed to save approved principle: \(error)")
        }

        // Capture the moment + saved-principle id for undo BEFORE advancing,
        // so the user can back-arrow to recover from a misclick.
        pushRecentlyAdvancedMoment(currentMoment, savedPrincipleId: savedPrincipleIdForUndo)
        advanceReviewQueue()
    }

    /// Saves a free-text answer the user typed for the current ambiguous
    /// moment, then advances the queue. Used when none of the four
    /// suggested options fits and the user wants to phrase the principle
    /// themselves. The new principle inherits the domain of the 4th
    /// candidate (the "Something else" stub) so domain bookkeeping stays
    /// consistent — falls back to `.general` if no candidate is available.
    func approveCustomAnswer(_ rawAnswer: String) {
        let trimmedAnswer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return }
        guard let currentMoment = pendingAmbiguousMoments.first else { return }

        let inheritedDomain = currentMoment.principleByOption.last?.domain ?? .general
        let approvalDate = Date()

        let customPrinciple = TastePrinciple(
            id: UUID().uuidString,
            domain: inheritedDomain,
            statement: trimmedAnswer,
            confidence: 0.75,
            evidence: ["User-typed during teach-session review."],
            tags: ["custom"],
            approved: true,
            authorId: "local-user",
            createdAt: approvalDate,
            updatedAt: approvalDate
        )

        var savedPrincipleIdForUndo: String? = nil
        do {
            try TasteProfileStore.appendApprovedPrinciples([customPrinciple])
            savedPrincipleIdForUndo = customPrinciple.id
            print("🧠 Review: approved custom principle — \(trimmedAnswer)")
            mirrorPrinciplesToOwnerTasteFile([customPrinciple])
            DashboardRecordingHistoryStore.recordTeachMoment(
                transcript: trimmedAnswer,
                extractedPrinciple: customPrinciple,
                wasApproved: true
            )
        } catch {
            print("⚠️ Review: failed to save custom principle: \(error)")
        }

        pushRecentlyAdvancedMoment(currentMoment, savedPrincipleId: savedPrincipleIdForUndo)
        advanceReviewQueue()
    }

    /// Skips the current ambiguous moment without saving any principle.
    /// Used when the user doesn't want any of the suggested options and
    /// doesn't feel like typing a custom one.
    func skipCurrentReviewMoment() {
        guard let currentMoment = pendingAmbiguousMoments.first else { return }
        print("🧠 Review: skipped a moment")
        // Skipped moments push onto the undo stack with a nil principle id —
        // back-arrow recovers the question without anything to delete.
        pushRecentlyAdvancedMoment(currentMoment, savedPrincipleId: nil)
        advanceReviewQueue()
    }

    /// Pops the most recently advanced moment off the undo stack and
    /// re-prepends it to the review queue. If a principle was saved when
    /// the moment was originally answered, that principle is also deleted
    /// from the on-disk taste profile so the round-trip is clean. No-op if
    /// the stack is empty (e.g. the user just opened the review).
    func unadvanceReviewQueue() {
        guard let mostRecentlyAdvanced = recentlyAdvancedMoments.popLast() else { return }

        if let principleIdToDelete = mostRecentlyAdvanced.savedPrincipleId {
            do {
                try TasteProfileStore.deletePrinciple(id: principleIdToDelete)
                print("🧠 Review: undone — deleted principle \(principleIdToDelete) and restored moment")
            } catch {
                // Even if deletion fails we still restore the moment so the
                // user isn't stuck — the orphan can be cleaned up later via
                // the upcoming Library view.
                print("⚠️ Review: undo failed to delete principle \(principleIdToDelete): \(error)")
            }
        } else {
            print("🧠 Review: undone — restored skipped moment")
        }

        pendingAmbiguousMoments.insert(mostRecentlyAdvanced.moment, at: 0)
    }

    /// Inserts a moment into the bounded undo stack, dropping the oldest
    /// entry if we'd exceed `recentlyAdvancedMomentsMaxDepth`. The bound
    /// keeps memory predictable across long review sessions.
    private func pushRecentlyAdvancedMoment(_ moment: AmbiguousMoment, savedPrincipleId: String?) {
        recentlyAdvancedMoments.append((moment: moment, savedPrincipleId: savedPrincipleId))
        if recentlyAdvancedMoments.count > recentlyAdvancedMomentsMaxDepth {
            recentlyAdvancedMoments.removeFirst(recentlyAdvancedMoments.count - recentlyAdvancedMomentsMaxDepth)
        }
    }

    /// Ends the review entirely, dropping any remaining ambiguous moments.
    /// Anything already approved before this is kept.
    func endReview() {
        let remainingMomentCount = pendingAmbiguousMoments.count
        if remainingMomentCount > 0 {
            print("🧠 Review: ended with \(remainingMomentCount) moment(s) remaining")
        }
        pendingAmbiguousMoments.removeAll()
        pendingReviewFrames.removeAll()
        // Explicit end means the user is walking away — stop offering undo
        // for prior answers so we don't dangle a re-prepend onto an empty
        // queue if they open another review.
        recentlyAdvancedMoments.removeAll()
    }

    private func advanceReviewQueue() {
        guard !pendingAmbiguousMoments.isEmpty else { return }
        pendingAmbiguousMoments.removeFirst()

        // Drop the heavy frame buffer once we're done with all moments —
        // no point holding onto JPEG data we won't render again.
        if pendingAmbiguousMoments.isEmpty {
            pendingReviewFrames.removeAll()
        }
    }

    /// Looks up the JPEG data for a given frame index in the current review
    /// queue. Returns nil if the index is out of range — the review card
    /// view should handle that gracefully (no thumbnail).
    func reviewFrameData(at frameIndex: Int) -> Data? {
        guard frameIndex >= 0 && frameIndex < pendingReviewFrames.count else { return nil }
        return pendingReviewFrames[frameIndex].data
    }

    private func resetTeachSessionState() {
        teachSessionScreenshotTimer?.invalidate()
        teachSessionScreenshotTimer = nil
        teachSessionElapsedTimer?.invalidate()
        teachSessionElapsedTimer = nil
        teachSessionTranscriptWatchdog?.cancel()
        teachSessionTranscriptWatchdog = nil
        teachSessionStartedAt = nil
        teachSessionElapsedSeconds = 0
        teachSessionFrames.removeAll()
        teachAnalyzingStatus = nil
        teachSessionState = .idle
    }

    /// Pretty-prints the analyzer output to the Xcode console. Item #2 will
    /// replace this with a real review-card surface in the panel.
    private static func printTeachSessionResultForDebugging(_ result: TeachSessionResult) {
        print("🎓 Teach session result")
        print("   Confident principles: \(result.confident.count)")
        for confidentPrinciple in result.confident {
            print("     • [\(confidentPrinciple.domain.rawValue)] \(confidentPrinciple.statement) (conf=\(String(format: "%.2f", confidentPrinciple.confidence)))")
        }
        print("   Ambiguous moments: \(result.ambiguous.count)")
        for ambiguousMoment in result.ambiguous {
            print("     ? frame \(ambiguousMoment.frameIndex): \(ambiguousMoment.question)")
            for (optionIndex, optionLabel) in ambiguousMoment.options.enumerated() {
                print("         \(optionIndex + 1). \(optionLabel)")
            }
        }
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        personaWheelHotkeyMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()

        // Tear down any in-progress teach session so its timers don't keep
        // firing after the app shuts down.
        teachSessionScreenshotTimer?.invalidate()
        teachSessionScreenshotTimer = nil
        teachSessionElapsedTimer?.invalidate()
        teachSessionElapsedTimer = nil
        teachSessionTranscriptWatchdog?.cancel()
        teachSessionTranscriptWatchdog = nil

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        personaWheelHotkeyCancellable?.cancel()
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        ttsPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
            personaWheelHotkeyMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
            personaWheelHotkeyMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")

                    // If onboarding was already completed, show the cursor overlay now
                    if hasCompletedOnboarding && allPermissionsGranted && !isOverlayVisible && isClickyCursorEnabled {
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentAudioPowerLevel = powerLevel
            }
    }

    /// Mirror the TTS client's published audio level onto the manager so
    /// the overlay's edge-glow can react to the AI's voice the same way
    /// it reacts to the user's mic. Touching `elevenLabsTTSClient` here
    /// triggers its lazy init — that's intentional, we want the
    /// publisher live before the first response arrives.
    private func bindTTSPowerLevel() {
        ttsPowerCancellable = elevenLabsTTSClient.$currentPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentTTSPowerLevel = powerLevel
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            guard !buddyDictationManager.isDictationInProgress else { return }
            // Don't register push-to-talk while the onboarding video is playing
            guard !showOnboardingVideo else { return }

            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isClickyCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .clickyDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            elevenLabsTTSClient.stopPlayback()
            clearDetectedElementLocation()

            // Kick off the screenshot capture immediately on key-down so it
            // overlaps with the user speaking. By the time they release and
            // we have a transcript, the screenshots are already encoded and
            // sitting in memory. The previous task (if any) is cancelled so
            // a new utterance always works against a fresh capture.
            preflightScreenCaptureTask?.cancel()
            preflightScreenCaptureTask = Task {
                try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            }

            // Dismiss the onboarding prompt if it's showing
            if showOnboardingPrompt {
                withAnimation(.easeOut(duration: 0.3)) {
                    onboardingPromptOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showOnboardingPrompt = false
                    self.onboardingPromptText = ""
                }
            }


            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're sticky, a sharp coworker that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    you are not a neutral summarizer or a cheerleader. you are a colleague who shows up with a point of view: you listen to how the user actually talks, mirror their rhythm and vocabulary lightly where it helps rapport, and still say what you think — including when you disagree, see a weak argument, or would ship something different. warmth without flattery. never flatten into "great question" / "that's a valid perspective" boilerplate.

    default to having an opinion. when the user asks for options, tradeoffs, or "what would you do?", give a ranked or preferred answer and say why — not a fence-sitting list. criticize constructively: name the flaw (logic, taste, risk, clarity, feasibility), tie it to something concrete you see on screen or that they said, and offer a sharper alternative or question — not vague negativity. if you lack enough context to criticize fairly, say what's missing in one sentence, then give your best partial take with explicit uncertainty. don't perform false uncertainty to sound humble.

    contextual lenses — actively pick (or combine) one based on context, and name it in one clause when it changes the answer ("reading this as a shipping decision, not a research exercise"):
    - product / user: who suffers if this is wrong?
    - craft / quality: what would embarrass us if we shipped this?
    - strategy / leverage: what actually moves the outcome?
    - risk / trust: what could blow up later?
    - taste / aesthetics / narrative: what does this feel like, and is that intentional?
    - execution / timeline: what's the smallest honest version?

    when two lenses conflict, surface the tension instead of hiding it.

    about the product:
    sticky is a macos companion that learns the user's taste — their judgment about design, writing, and code — and uses it to help them work. it has three modes the user picks from a menu bar panel:
    - ask (you are here right now by default): the user asks a question about what's on their screen, you answer and can fly your blue thumbtack cursor to point at things.
    - teach: the user holds the same shortcut, narrates a creative decision out loud while looking at their work (e.g. "i made the logo bigger because brand presence matters"), and a separate path extracts that into a saved taste principle. you don't handle teach mode — a different system prompt does.
    - apply: same as ask, except the user's saved taste principles get prepended to your system prompt as judgment context. when you see a "current taste context" block above, treat those principles as the user's preferences — use them to ground critique, suggestions, and rankings, but they're judgment context, not rigid rules. say so if evidence is weak or conflicting.

    rules:
    - **be conversational and concise. one or two sentences is the default. three at the absolute most.** you are talking, not writing. the user can always ask a follow-up if they want more — short answers earn follow-ups, long answers kill the conversation.
    - lead with the useful takeaway. one beat, then stop. if a fix is the answer, say the fix and stop. don't preamble. don't summarise the brand. don't list every angle. don't justify the take three different ways.
    - **answer the words the user actually said, not the screen.** a check-in like "what's up", "hey", "you there?", "working on xcode are we?", "how's it going" gets a short conversational reply — confirm what you can see in a single phrase if it fits and hand the turn back. only describe what's on screen when the user asked a question that genuinely needs that detail (a critique, a how-do-i, a what-is-this, a where's-x).
    - never narrate the screen unprompted. don't open with "i can see…" or "you've got x open with y and z". if the user wants a screen tour they'll ask for one.
    - the only time you can go longer is if the user explicitly asks you to explain more, go deeper, or elaborate. otherwise: short.
    - all lowercase, casual, warm. no emojis. no exclamation marks unless the persona explicitly calls for them.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see — names, positions, exact words. specifics earn the take.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, design critique, general knowledge, brainstorming.
    - never say "simply" or "just". no "great question", no "valid perspective", no generic assistant filler.
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - end when you're done. don't end with dead-end yes/no questions like "want me to explain more?" or "should i show you?". one concrete next step is fine if it fits — but most replies should just end on the take.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.
    - if the user asks for something harmful, unethical, or deceptive, refuse briefly and redirect.

    element pointing:
    you have a small glowing blue orb cursor that can fly to and point at things on screen. **use it aggressively.** the pointing is one of the best parts of this product — every time you reference something specific on screen, point at it. err *heavily* on the side of pointing. if you can name the thing, you can point at the thing.

    **most importantly: when you critique something, suggest a change, or recommend a fix, point at the exact thing you're talking about.** this is non-negotiable. if you say "the headline is too long," point at the headline. if you say "crop the feet," point at the feet. if you say "the logo needs to be bigger," point at the logo. if you say "the brand should feel more swedish," point at the empty area where the flag or *Made in Sweden* should go. the cursor on the thing is what makes the feedback land — words alone are noise, words plus the cursor on the actual pixel is craft.

    when to point:
    - critiquing or suggesting a change to a specific element on screen → point at that element. always.
    - referencing a specific button, menu, image, region, headline, color, body part, crop edge, or piece of type → point at it.
    - explaining how to do something in an app → point at the relevant control.
    - flagging what's missing → point at the empty area where it should go.

    when *not* to point:
    - the user asked a pure general-knowledge question with nothing on screen attached.
    - the conversation has nothing to do with what's on screen.
    - the thing you'd point at takes up most of the visible area (no signal in pointing at the whole screen).

    when you point, append a coordinate tag at the very end of your response, AFTER your spoken text. the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward. aim for the visual center of the element you're naming — not a corner.

    format: [POINT:x,y:label] where x,y are integer pixel coordinates in the screenshot's coordinate space, and label is a short 1-3 word description of the element (like "search bar", "feet", "headline", "missing flag"). if the element is on the cursor's screen you can omit the screen number. if the element is on a DIFFERENT screen, append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if pointing genuinely wouldn't help, append [POINT:none] — but use this sparingly. when in doubt, point.

    examples:
    - user asks how to color grade in final cut: "you'll want to open the color inspector — it's right up in the top right area of the toolbar. click that and you'll get all the color wheels and curves. [POINT:1100,42:color inspector]"
    - user asks what html is: "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
    - user asks how to commit in xcode: "see that source control menu up top? click that and hit commit, or you can use command option c as a shortcut. [POINT:285,11:source control]"
    - element is on screen 2 (not where cursor is): "that's over on your other monitor — see the terminal window? [POINT:400,300:terminal:screen2]"
    - critique on a poster: "the feet are throwing me off — crop them above the ankles or shoot from a higher angle. [POINT:640,1180:feet]"
    - flagging what's missing: "this could be any sauna company. it needs *Made in Sweden* and the flag, somewhere down here in the empty space under the headline. [POINT:520,940:empty space below headline]"
    - recommending a specific change: "the logo is too small — needs to be at least double this size to earn the brand presence. [POINT:120,80:logo]"
    """

    /// Builds the system prompt for the existing voice flow with the user's
    /// saved taste prepended as judgment context. Honors the active scope —
    /// personal-only or personal ∪ team. Falls back to the unmodified base
    /// prompt if the profile is empty or fails to load — Sticky should
    /// never break because of a taste-file issue.
    ///
    /// When a teammate persona is active, this branches into the teammate
    /// path: their soul.md is prepended (so Claude is told who it's
    /// playing) followed by their bundled taste principles, and the user's
    /// own taste profile + team profile are NOT used. The teammate's
    /// identity replaces Sticky's defaults wholesale.
    private func composeVoiceSystemPromptWithTaste() -> String {
        let basePrompt = Self.companionVoiceResponseSystemPrompt

        if let teammateBundle = activeTeammateBundle {
            // Teammate persona path doesn't drive the AppliedPrinciplesChip
            // — the chip is for the user's own / team taste, not for a
            // borrowed persona. Clear the in-flight cache so a stale
            // mapping from the previous request can't bleed into the
            // [USED:...] resolver.
            inFlightTasteContextBlock = nil
            return prependFreshVoiceSessionHintIfNeeded(
                composeSystemPromptForTeammatePersona(
                    teammateBundle: teammateBundle,
                    basePrompt: basePrompt
                )
            )
        }

        // Phase 2: prefer the owner's TASTE.md (the new source of
        // truth) so teach-mode appends become visible in apply mode
        // without a restart. Falls back to the legacy JSON store when
        // the markdown file isn't reachable — once everything reads
        // TASTE.md cleanly, the JSON store can go away.
        let loadedPersonalProfile: TasteProfile
        if let ownerBundle = PersonaStore.myCurrentBundle() {
            loadedPersonalProfile = ownerBundle.taste
            print("📄 Personal taste loaded from \(PersonaStore.myPersonaId)/TASTE.md (\(loadedPersonalProfile.principles.count) principle(s))")
        } else {
            do {
                loadedPersonalProfile = try TasteProfileStore.loadProfile()
            } catch {
                print("⚠️ Couldn't load personal taste profile, using base prompt: \(error)")
                inFlightTasteContextBlock = nil
                return prependFreshVoiceSessionHintIfNeeded(basePrompt)
            }
        }

        // Team profile is best-effort. If it's missing or malformed we just
        // run with personal-only — no need to fail the whole prompt build.
        let loadedTeamProfile: TeamTasteProfile? = (tasteScope == .team)
            ? TeamTasteProfileStore.loadTeamProfile()
            : nil

        let builtTasteContextBlock = TastePromptBuilder.buildTasteContextBlock(
            personalProfile: loadedPersonalProfile,
            teamProfile: loadedTeamProfile,
            scope: tasteScope
        )

        // Team context (brief + dropped files) is only injected in team
        // scope — when the user is "speaking on behalf of the team" the
        // persona needs to know what the team's working on. Personal
        // scope stays clean of team material.
        let teamContextOverviewBlock: String = (tasteScope == .team)
            ? TeamContextPromptBuilder.teamContextBlock(profile: TeamContextStore.loadProfile())
            : ""

        guard !builtTasteContextBlock.promptText.isEmpty || !teamContextOverviewBlock.isEmpty else {
            inFlightTasteContextBlock = nil
            return prependFreshVoiceSessionHintIfNeeded(basePrompt)
        }

        let approvedPersonalCount = loadedPersonalProfile.principles.filter { $0.approved }.count
        let approvedTeamCount = loadedTeamProfile?.principles.filter { $0.approved }.count ?? 0
        switch tasteScope {
        case .personal:
            print("🧠 Applying \(approvedPersonalCount) personal taste principle(s) to voice prompt")
        case .team:
            print("🧠 Applying taste — \(approvedPersonalCount) personal + \(approvedTeamCount) team principle(s)")
            if !teamContextOverviewBlock.isEmpty {
                print("📎 Injecting team context block (\(teamContextOverviewBlock.utf8.count) bytes)")
            }
        }

        // Cache the block so the response handler can resolve Claude's
        // trailing [USED:...] tag back into TastePrinciple objects.
        // Ask mode now always injects taste, so the chip always has a
        // mapping available. Teach mode follows a separate code path.
        inFlightTasteContextBlock = builtTasteContextBlock

        let assembledPromptSections: [String] = [
            teamContextOverviewBlock,
            builtTasteContextBlock.promptText,
            basePrompt
        ].filter { !$0.isEmpty }

        return prependFreshVoiceSessionHintIfNeeded(
            assembledPromptSections.joined(separator: "\n\n")
        )
    }

    /// One-line hint prepended to every system prompt on the first
    /// exchange after a voice session reset (persona switch, idle
    /// timeout, or "New voice chat" tap). Tells Sticky / the active
    /// persona that they may have spoken to this user before but don't
    /// currently remember the prior context, so they should ask for a
    /// quick recap if the user references something they shouldn't
    /// know about. Returns the prompt unchanged when no reset just
    /// happened — most exchanges within a session are pure continuations
    /// and don't need the hint.
    private func prependFreshVoiceSessionHintIfNeeded(_ prompt: String) -> String {
        guard voiceSessionIsFreshAfterReset else { return prompt }
        let hint = """
        important context for this turn: this is the start of a fresh chat session. you may well have spoken with this user before in earlier sessions, but you do not currently have access to those past conversations — your memory of them has been reset for privacy. if the user references a previous chat, a decision you made together, or something they "told you last time," gently acknowledge that you may have spoken before but don't remember the specifics, and ask them to give you a quick recap so you can be useful again. don't pretend to remember things you don't, and don't be apologetic about it — treat it as natural ("i've forgotten the details, give me a quick recap?"). this hint applies to this turn only; once the user has caught you up, treat the conversation as in-progress.
        """
        return hint + "\n\n" + prompt
    }

    /// Builds the system prompt when the user is wearing a teammate's
    /// persona. A roleplay framing header goes first (so Claude knows it
    /// is fully impersonating this person — name, role, tone, quirks —
    /// and that "who are you" must be answered in-character), then the
    /// teammate's `soul` (their personality prose), then their bundled
    /// taste principles framed as judgment context, and finally the
    /// rules/format portion of the base Sticky prompt with the
    /// "you're sticky" identity paragraph stripped out so it doesn't
    /// fight the persona. Personal/team taste from disk is intentionally
    /// NOT mixed in — when you pick a teammate you want to hear from
    /// them, not a blend of you and them.
    private func composeSystemPromptForTeammatePersona(
        teammateBundle: PersonaBundle,
        basePrompt: String
    ) -> String {
        let teammateTasteContextBlock = TastePromptBuilder.tasteContextBlock(
            personalProfile: teammateBundle.taste,
            teamProfile: nil,
            scope: .personal
        )

        print("🎭 Wearing persona: \(teammateBundle.displayName) (\(teammateBundle.id)) — \(teammateBundle.taste.principles.filter { $0.approved }.count) approved principle(s)")

        // The base prompt opens with "you're sticky, a friendly always-on
        // companion..." — that identity line directly contradicts the
        // teammate roleplay and the model will revert to "sticky" the
        // moment it reads it. Strip the first paragraph (everything up
        // to the first blank line) and keep only the rules / element-
        // pointing / format portion, which is identity-agnostic.
        let basePromptWithoutIdentityParagraph: String = {
            if let firstBlankLineRange = basePrompt.range(of: "\n\n") {
                return String(basePrompt[firstBlankLineRange.upperBound...])
            }
            return basePrompt
        }()

        let roleplayFramingHeader = """
        you are roleplaying as \(teammateBundle.displayName) — \(teammateBundle.role). this is not a character you reference, it's the identity you fully inhabit for this entire conversation.

        embody them completely: their tone, cadence, vocabulary, opinions, areas of expertise, blind spots, and quirks. speak as them in the first person. when the user asks who you are, who they're talking to, what your name is, or what you do, answer in-character — give your name (\(teammateBundle.displayName)), your role (\(teammateBundle.role)), and a sentence or two of context that fits the personality below. do not say you are sticky, do not say you are an ai, do not break character. if asked something \(teammateBundle.displayName) wouldn't know about, react the way they would — curious, dismissive, deflecting to their own expertise — rather than refusing.

        you are not a neutral assistant in costume — you are this person, and this person has opinions. when the user shows you work and asks what you think, give a real take with one or two specific, concrete suggestions tied to exactly what's on screen (the headline, the crop, the colors, a specific element you can name). do not hedge. do not list every possibility. pick the one or two changes \(teammateBundle.displayName) would actually push for and say what they'd be — name the thing, name the fix. specifics earn the opinion.

        **when you critique or suggest a change, always point at the thing you're talking about using the [POINT:x,y:label] tag described later in this prompt.** if you say "crop the feet," point at the feet. if you say "the brand needs to feel swedish," point at the empty area where the flag belongs. if you say "the logo is too small," point at the logo. the cursor on the actual pixel is what turns a quote into craft. critique without pointing is a missed beat.

        pick the lens \(teammateBundle.displayName) naturally reaches for from this list and use it implicitly (you don't have to label it out loud unless it sharpens the point): product / user, craft / quality, strategy / leverage, risk / trust, taste / aesthetics / narrative, execution / timeline. brand and identity work usually pulls the taste lens or the strategy lens — pick whichever \(teammateBundle.displayName) would.

        the personality, voice, and values you should emulate are described next.
        """

        var promptSections: [String] = [roleplayFramingHeader]

        if !teammateBundle.soul.isEmpty {
            promptSections.append(teammateBundle.soul)
        }

        if !teammateTasteContextBlock.isEmpty {
            promptSections.append(teammateTasteContextBlock)
        }

        // Every teammate persona is part of the same team, so they all
        // get the team brief + dropped files as background context. The
        // overview is intentionally light — filenames + summaries +
        // small text bodies — so this doesn't crowd out the persona's
        // own voice. Empty when the user hasn't filled the team page in.
        let teamContextOverviewBlock = TeamContextPromptBuilder
            .teamContextBlock(profile: TeamContextStore.loadProfile())
        if !teamContextOverviewBlock.isEmpty {
            promptSections.append(teamContextOverviewBlock)
        }

        // Final reminder right before the format rules so the model
        // doesn't drop the persona when it sees the response-format
        // instructions below.
        promptSections.append("stay fully in character as \(teammateBundle.displayName) for every reply. the rules below are about response format (length, tone register, pointing tags) — apply them through \(teammateBundle.displayName)'s voice, not by reverting to a generic assistant.")

        promptSections.append(basePromptWithoutIdentityParagraph)

        return promptSections.joined(separator: "\n\n")
    }

    /// Phase 2 — mirrors freshly-saved teach-mode principles into the
    /// local owner's TASTE.md so they show up to teammates who borrow
    /// this persona. Best-effort: failures are logged but don't block
    /// the primary JSON save (which the rest of the app — TasteLibrary,
    /// review queue, undo — still reads from). Eventually we'll cut
    /// the JSON store; until then both writes happen in lockstep.
    private func mirrorPrinciplesToOwnerTasteFile(_ principles: [TastePrinciple]) {
        guard !principles.isEmpty else { return }
        for principle in principles {
            do {
                try PersonaTasteFileStore.appendPrinciple(
                    principle,
                    toPersonaId: PersonaStore.myPersonaId
                )
            } catch {
                print("⚠️ TASTE.md mirror failed for \(PersonaStore.myPersonaId): \(error)")
            }
        }
        print("📄 Mirrored \(principles.count) principle(s) to \(PersonaStore.myPersonaId)/TASTE.md")
    }

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to Claude,
    /// and plays the response aloud via ElevenLabs TTS. The cursor stays in
    /// the spinner/processing state until TTS audio begins playing.
    /// Claude's response may include a [POINT:x,y:label] tag which triggers
    /// the buddy to fly to that element on screen.
    private func sendTranscriptToClaudeWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        elevenLabsTTSClient.stopPlayback()

        // Idle-rollover happens *before* we read the system prompt below,
        // so a fresh-session hint can be included on the very first
        // exchange after a long gap (instead of waiting for the next one).
        startsFreshVoiceSessionIfIdleTooLong()

        // Hand the in-flight preflight capture to the response task. We clear
        // the property up front so a stray release-then-press while we're
        // mid-response doesn't kick the same task around twice.
        let preflightCaptureTaskForThisResponse = preflightScreenCaptureTask
        preflightScreenCaptureTask = nil

        // Reset applied-taste transparency state up front for every
        // request. The chip in the cursor overlay reads these properties
        // — clearing them here means the previous reply's applied-
        // principles list disappears the moment the user holds push-to-
        // talk again, so the chip never displays stale info while a new
        // request is in flight.
        lastAppliedPrinciples = []
        lastAppliedSourceWasTeam = false
        teamOriginPrincipleIds = []
        inFlightTasteContextBlock = nil
        // Hide the chip immediately on a new request and cancel any
        // pending fade — otherwise a fade-out scheduled by the previous
        // reply could fire mid-stream and yank the new chip away.
        isShowingAppliedPrinciplesChip = false
        appliedPrinciplesChipHideTask?.cancel()
        appliedPrinciplesChipHideTask = nil

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Prefer the preflight capture (started on key-down so it
                // overlaps with speaking). If for any reason it failed or
                // wasn't kicked off, fall back to capturing inline so the
                // pipeline still works.
                let screenCaptures: [CompanionScreenCapture]
                if let preflightCaptureTaskForThisResponse {
                    do {
                        screenCaptures = try await preflightCaptureTaskForThisResponse.value
                    } catch {
                        print("⚠️ Preflight screenshot failed (\(error)); recapturing inline")
                        screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
                    }
                } else {
                    screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
                }

                guard !Task.isCancelled else { return }

                // Build image labels with the actual screenshot pixel dimensions
                // so Claude's coordinate space matches the image it sees. We
                // scale from screenshot pixels to display points ourselves.
                let labeledImages = screenCaptures.map { capture in
                    let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                    return (data: capture.imageData, label: capture.label + dimensionInfo)
                }

                // Pass conversation history so Claude remembers prior exchanges
                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                // Pull the user's saved taste from disk and prepend it to
                // the system prompt so every voice answer is grounded in
                // what the user has taught Sticky. On first launch (empty
                // profile) this is a no-op and the base prompt is used.
                let composedSystemPrompt = composeVoiceSystemPromptWithTaste()

                // Sentence-streamed TTS: as Claude streams the reply, dispatch
                // each completed sentence to ElevenLabs in parallel and play
                // them back in order via the chained playback queue. The
                // first sentence begins playing while Claude is still
                // generating later ones, which is the single biggest
                // perceived-latency win in the response pipeline.
                // When a teammate persona is active, their bundle voice
                // takes precedence over the user's own selectedVoiceID —
                // the whole point of switching personas is to hear them
                // speak in their voice. Falls back to the user's voice
                // (or the bundled default) when persona is .me / .team.
                let effectiveTTSVoiceID = activeTeammateBundle?.voiceId ?? selectedVoiceID
                let streamingResponseState = StreamingResponseState(
                    ttsClient: elevenLabsTTSClient,
                    overrideVoiceID: effectiveTTSVoiceID
                )
                streamingResponseState.beginNewChain()

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: composedSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { accumulatedStreamedText in
                        streamingResponseState.handleStreamedText(accumulatedStreamedText)
                    }
                )

                guard !Task.isCancelled else { return }

                // Strip the trailing [USED:...] tag FIRST so the existing
                // [POINT:...] parser (which anchors to end-of-string) still
                // matches correctly. The taste-context block tells Claude
                // to put [USED:...] AFTER any [POINT:...] tag, so the order
                // is:
                //   <reply text> <[POINT:...]?> <[USED:...]>
                // We unwrap the inner [POINT:...] from the cleaned text
                // below, after the USED tag has been removed.
                let usedTagParseResult = TastePromptBuilder.parseUsedTag(from: fullResponseText)
                let responseTextWithoutUsedTag = usedTagParseResult.cleanText
                let usedShortLabels = usedTagParseResult.usedShortLabels

                // Parse the [POINT:...] tag from Claude's response
                let parseResult = Self.parsePointingCoordinates(from: responseTextWithoutUsedTag)
                let spokenText = parseResult.spokenText

                // Resolve [USED:...] short labels back into TastePrinciple
                // objects via the cached TasteContextBlock mapping. Only
                // populated when there were principles to inject — empty
                // profiles leave inFlightTasteContextBlock nil and the
                // chip never appears.
                if let cachedTasteContextBlock = inFlightTasteContextBlock {
                    var resolvedPrinciples: [TastePrinciple] = []
                    var resolvedTeamOriginIds: Set<String> = []
                    for shortLabel in usedShortLabels {
                        // Tolerant to Claude making up a label that doesn't
                        // exist (e.g. [USED:P99]) — silently skip the bad
                        // label, keep the rest. Better than dropping the
                        // whole list because of one stray.
                        guard let resolvedPrinciple = cachedTasteContextBlock.principlesByShortLabel[shortLabel] else {
                            print("⚠️ Apply transparency: ignoring unknown short label \"\(shortLabel)\"")
                            continue
                        }
                        resolvedPrinciples.append(resolvedPrinciple)
                        if cachedTasteContextBlock.teamShortLabels.contains(shortLabel) {
                            resolvedTeamOriginIds.insert(resolvedPrinciple.id)
                        }
                    }
                    lastAppliedPrinciples = resolvedPrinciples
                    teamOriginPrincipleIds = resolvedTeamOriginIds
                    lastAppliedSourceWasTeam = !resolvedTeamOriginIds.isEmpty
                    print("✦ Apply transparency: resolved \(resolvedPrinciples.count) principle(s) from [USED:\(usedShortLabels.joined(separator: ","))]")
                }
                // Clear the cached context block so a stale mapping can't
                // bleed into the next request's USED resolution.
                inFlightTasteContextBlock = nil

                // Reveal the AppliedPrinciplesChip when Claude actually
                // leaned on at least one principle. Unlike the old
                // Apply-mode behaviour we don't show an empty-state chip
                // on every reply — that would be noise on the now-default
                // ask flow when the user hasn't taught Sticky anything
                // yet, or when their question simply didn't intersect
                // with their taste.
                if !lastAppliedPrinciples.isEmpty {
                    isShowingAppliedPrinciplesChip = true
                    scheduleAppliedPrinciplesChipFadeOut()
                }

                // Dispatch any spoken text that wasn't sent during streaming
                // (e.g. a final clause without trailing punctuation, or text
                // held back when "[POINT:" appeared). For most multi-sentence
                // responses this is a no-op because every sentence already
                // went out during streaming.
                streamingResponseState.dispatchAnyTrailingText(of: spokenText)

                // Handle element pointing if Claude returned coordinates.
                // Switch to idle BEFORE setting the location so the triangle
                // becomes visible and can fly to the target. Without this, the
                // spinner hides the triangle and the flight animation is invisible.
                let hasPointCoordinate = parseResult.coordinate != nil
                if hasPointCoordinate {
                    voiceState = .idle
                }

                // Pick the screen capture matching Claude's screen number,
                // falling back to the cursor screen if not specified.
                let targetScreenCapture: CompanionScreenCapture? = {
                    if let screenNumber = parseResult.screenNumber,
                       screenNumber >= 1 && screenNumber <= screenCaptures.count {
                        return screenCaptures[screenNumber - 1]
                    }
                    return screenCaptures.first(where: { $0.isCursorScreen })
                }()

                if let pointCoordinate = parseResult.coordinate,
                   let targetScreenCapture {
                    // Claude's coordinates are in the screenshot's pixel space
                    // (top-left origin, e.g. 1280x831). Scale to the display's
                    // point space (e.g. 1512x982), then convert to AppKit global coords.
                    let screenshotWidth = CGFloat(targetScreenCapture.screenshotWidthInPixels)
                    let screenshotHeight = CGFloat(targetScreenCapture.screenshotHeightInPixels)
                    let displayWidth = CGFloat(targetScreenCapture.displayWidthInPoints)
                    let displayHeight = CGFloat(targetScreenCapture.displayHeightInPoints)
                    let displayFrame = targetScreenCapture.displayFrame

                    // Clamp to screenshot coordinate space
                    let clampedX = max(0, min(pointCoordinate.x, screenshotWidth))
                    let clampedY = max(0, min(pointCoordinate.y, screenshotHeight))

                    // Scale from screenshot pixels to display points
                    let displayLocalX = clampedX * (displayWidth / screenshotWidth)
                    let displayLocalY = clampedY * (displayHeight / screenshotHeight)

                    // Convert from top-left origin (screenshot) to bottom-left origin (AppKit)
                    let appKitY = displayHeight - displayLocalY

                    // Convert display-local coords to global screen coords
                    let globalLocation = CGPoint(
                        x: displayLocalX + displayFrame.origin.x,
                        y: appKitY + displayFrame.origin.y
                    )

                    detectedElementScreenLocation = globalLocation
                    detectedElementDisplayFrame = displayFrame
                    print("🎯 Element pointing: (\(Int(pointCoordinate.x)), \(Int(pointCoordinate.y))) → \"\(parseResult.elementLabel ?? "element")\"")
                } else {
                    print("🎯 Element pointing: \(parseResult.elementLabel ?? "no element")")
                }

                // Save this exchange to conversation history (with the point tag
                // stripped so it doesn't confuse future context)
                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: spokenText
                ))

                // Keep only the last 10 exchanges to avoid unbounded context growth
                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                hasVoiceConversationHistory = !conversationHistory.isEmpty

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")

                // Mirror the exchange into the on-disk voice chat archive
                // so the dashboard's Chats tab can show it. This intentionally
                // archives *every* completed exchange, even when the spoken
                // text is empty, so the user's transcript still surfaces.
                archiveVoiceExchangeToDisk(transcript: transcript, assistantResponse: spokenText)

                // Sentences were already enqueued during streaming + via the
                // trailing-text dispatch above. Audio is fetching and will
                // start playing as the first segment arrives. Set
                // voiceState=.responding briefly so the dictation observer
                // doesn't yank it back to idle/processing during the
                // transition (the trailing block immediately flips it to
                // .idle, mirroring the prior speakText path).
                if !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    voiceState = .responding
                }
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch {
                print("⚠️ Companion response error: \(error)")
                speakCreditsErrorFallback()
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// Schedules the AppliedPrinciplesChip to fade out roughly when the
    /// response bubble would have. We wait for the TTS chain to drain
    /// (so the chip stays up while Sticky is still speaking) then hold
    /// for a few extra seconds so the user has time to read the matched
    /// principles. Cancelled by the next request so a stale fade-out
    /// can't yank the new chip away.
    private func scheduleAppliedPrinciplesChipFadeOut() {
        appliedPrinciplesChipHideTask?.cancel()
        appliedPrinciplesChipHideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait for TTS to finish so the chip persists alongside the
            // entire spoken reply, not just until the first sentence
            // begins. `isProducingAudio` covers in-flight chained
            // sentences, mirroring scheduleTransientHideIfNeeded above.
            while self.elevenLabsTTSClient.isProducingAudio {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }
            // Hold for ~6 seconds after speech ends — same window the
            // CompanionResponseOverlay uses for the (currently dormant)
            // response bubble fade. Long enough to read 2-3 principles.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self.isShowingAppliedPrinciplesChip = false
        }
    }

    /// If the cursor is in transient mode (user toggled "Show Sticky" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isClickyCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for the entire TTS chain to drain — `isProducingAudio`
            // covers in-flight chained sentences, not just the currently
            // playing one. Without this the overlay would fade out during
            // the brief gap between sentence-streamed segments.
            while elevenLabsTTSClient.isProducingAudio {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    // MARK: - Voice Session Lifecycle

    /// Resets the rolling voice session: clears `conversationHistory`,
    /// mints a new on-disk archive id, drops the in-memory message
    /// mirror, and flags the next exchange as "fresh" so the system
    /// prompt can include a "you may have spoken before but don't
    /// currently remember" hint. Called from persona switches, the idle
    /// timeout, and the explicit "New voice chat" button. Safe to call
    /// when no voice session is in flight — it just reseeds the ids.
    private func beginFreshVoiceSession(reason: String) {
        conversationHistory.removeAll()
        hasVoiceConversationHistory = false
        activeVoiceSessionId = UUID().uuidString
        activeVoiceSessionMessages = []
        voiceSessionIsFreshAfterReset = true
        lastVoiceExchangeAt = nil
        print("🧠 New voice session (\(reason)) → id \(activeVoiceSessionId.prefix(8))")
    }

    /// Public entry point for the "New voice chat" button in the menu
    /// bar panel. Cancels any in-flight response and starts a brand-new
    /// voice session so the user gets the same fresh-start behaviour as
    /// switching personas — the prompt note will tell Sticky it doesn't
    /// remember the previous chat.
    func beginNewVoiceChat() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        beginFreshVoiceSession(reason: "user tapped New voice chat")
    }

    /// Inspects how long it's been since the last completed voice
    /// exchange. If the gap exceeds `voiceSessionIdleResetInterval`,
    /// rolls over to a fresh voice session before the upcoming press is
    /// processed. Called at the *start* of the response pipeline (just
    /// before `composeVoiceSystemPromptWithTaste` reads
    /// `voiceSessionIsFreshAfterReset`) so the prompt note is included
    /// on the first press of a new conversation, not the second.
    private func startsFreshVoiceSessionIfIdleTooLong() {
        guard let lastVoiceExchangeAt else { return }
        let elapsed = Date().timeIntervalSince(lastVoiceExchangeAt)
        guard elapsed > Self.voiceSessionIdleResetInterval else { return }
        beginFreshVoiceSession(reason: "idle for \(Int(elapsed / 3600))h")
    }

    /// Appends the just-completed voice exchange to the in-memory
    /// session mirror and writes the whole session back to disk under
    /// the active session id. Called once per push-to-talk exchange,
    /// right after `conversationHistory.append`.
    private func archiveVoiceExchangeToDisk(transcript: String, assistantResponse: String) {
        let now = Date()
        let userMessage = DashboardChatMessage(
            id: UUID().uuidString,
            role: "user",
            text: transcript,
            createdAt: now
        )
        let assistantMessage = DashboardChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            text: assistantResponse,
            createdAt: now
        )
        activeVoiceSessionMessages.append(userMessage)
        activeVoiceSessionMessages.append(assistantMessage)

        let personaIdForArchive: String = {
            switch personaSelection {
            case .me: return PersonaStore.mePseudoPersona.id
            case .team: return PersonaStore.teamPseudoPersona.id
            case .teammate(let id): return id
            }
        }()

        DashboardChatHistoryStore.recordSession(
            sessionId: activeVoiceSessionId,
            messages: activeVoiceSessionMessages,
            personaId: personaIdForArchive,
            medium: "voice"
        )

        lastVoiceExchangeAt = now
        // The fresh-session prompt hint only applies to the first
        // exchange after a reset — clear it now that the user has
        // actually said something the model can hear.
        voiceSessionIsFreshAfterReset = false
    }

    /// Speaks a hardcoded error message using macOS system TTS when API
    /// credits run out. Uses NSSpeechSynthesizer so it works even when
    /// ElevenLabs is down.
    private func speakCreditsErrorFallback() {
        let utterance = "I'm all out of credits."
        let synthesizer = NSSpeechSynthesizer()
        fallbackSpeechSynthesizer = synthesizer
        synthesizer.startSpeaking(utterance)
        voiceState = .responding
    }

    // MARK: - Streaming Response Dispatcher

    /// Drives sentence-by-sentence TTS dispatch as Claude's reply streams in.
    ///
    /// Each call to `handleStreamedText` looks at what's been received so
    /// far, finds completed sentences past the dispatch cursor, and fires
    /// an ElevenLabs fetch for each one in parallel. The fetches finish in
    /// arbitrary order, but the per-sentence enqueue is chained so audio
    /// always plays back in the original order — matching what the user
    /// would hear if Claude had returned all the text at once.
    ///
    /// The whole point: the first sentence's audio starts playing while
    /// Claude is still generating the rest of the response, which cuts
    /// 1.5–3 seconds of perceived latency on multi-sentence answers.
    @MainActor
    final class StreamingResponseState {
        private weak var ttsClient: ElevenLabsTTSClient?
        private let overrideVoiceID: String?

        /// Number of Characters of `accumulatedText` we've already dispatched
        /// to TTS. Each new chunk only sees text past this cursor.
        private var dispatchedCharacterCount: Int = 0

        /// Goes true the first time we observe EITHER a "[POINT:" or
        /// "[USED:" tag start in the stream. Once set, no further streaming
        /// dispatch happens — both tags are un-spoken markers (POINT drives
        /// the cursor flight, USED drives the Apply-transparency chip)
        /// and neither should reach ElevenLabs. Anything spoken before
        /// the tag has already been dispatched.
        private var hasSeenPointTagStart: Bool = false

        /// Epoch returned by `ElevenLabsTTSClient.resetPlaybackChain`. Each
        /// enqueue passes this so a stale fetch from the previous response
        /// (the user pressed PTT again) can't slip into the new chain.
        private var playbackChainEpoch: Int = 0

        /// Tail of the serialized enqueue chain. Each sentence's enqueue
        /// Task awaits the previous one so audio segments arrive in the
        /// player's queue in the same order they came out of Claude, even
        /// when the underlying ElevenLabs fetches finish out of order.
        private var previousEnqueueTask: Task<Void, Never> = Task {}

        init(ttsClient: ElevenLabsTTSClient, overrideVoiceID: String?) {
            self.ttsClient = ttsClient
            self.overrideVoiceID = overrideVoiceID
        }

        /// Resets the playback queue and remembers the new epoch. Must be
        /// called once before streaming begins.
        func beginNewChain() {
            guard let ttsClient else { return }
            playbackChainEpoch = ttsClient.resetPlaybackChain(onFirstPlaybackStart: { })
            dispatchedCharacterCount = 0
            hasSeenPointTagStart = false
            previousEnqueueTask = Task {}
        }

        /// Called on each Claude SSE delta with the FULL accumulated reply.
        /// Finds sentence boundaries past the dispatch cursor and ships each
        /// completed sentence off to ElevenLabs.
        func handleStreamedText(_ accumulatedStreamedText: String) {
            guard !hasSeenPointTagStart else { return }

            let dispatchCursorIndex = accumulatedStreamedText.index(
                accumulatedStreamedText.startIndex,
                offsetBy: min(dispatchedCharacterCount, accumulatedStreamedText.count)
            )
            let pendingText = String(accumulatedStreamedText[dispatchCursorIndex...])

            // If either "[POINT:" or "[USED:" appears in the new text,
            // dispatch the spoken portion (everything before the earliest
            // tag) immediately and stop streaming further dispatches —
            // both tags are un-spoken markers and neither should reach
            // ElevenLabs. We pick whichever tag opens earliest so we
            // don't miss the cutoff when Claude emits BOTH tags
            // back-to-back at the end of the response.
            let pointTagStartRange = pendingText.range(of: "[POINT:")
            let usedTagStartRange = pendingText.range(of: "[USED:")
            let earliestTagStartRange: Range<String.Index>?
            switch (pointTagStartRange, usedTagStartRange) {
            case (nil, nil):
                earliestTagStartRange = nil
            case (let pointRange?, nil):
                earliestTagStartRange = pointRange
            case (nil, let usedRange?):
                earliestTagStartRange = usedRange
            case (let pointRange?, let usedRange?):
                earliestTagStartRange = pointRange.lowerBound < usedRange.lowerBound
                    ? pointRange
                    : usedRange
            }
            if let earliestTagStartRange {
                let spokenPortion = pendingText[..<earliestTagStartRange.lowerBound]
                let trimmedSpokenPortion = String(spokenPortion).trimmingCharacters(in: .whitespacesAndNewlines)
                let charactersConsumed = pendingText.distance(
                    from: pendingText.startIndex,
                    to: earliestTagStartRange.lowerBound
                )
                dispatchedCharacterCount += charactersConsumed
                hasSeenPointTagStart = true
                if !trimmedSpokenPortion.isEmpty {
                    enqueueSpeechSegment(trimmedSpokenPortion)
                }
                return
            }

            // No tag yet — dispatch everything up to the latest sentence
            // boundary in the pending text. We dispatch as much as possible
            // per chunk so multi-sentence chunks aren't artificially split
            // across multiple ElevenLabs round-trips.
            guard let latestSentenceEndIndex = Self.indexAfterLatestSentenceBoundary(in: pendingText) else {
                return
            }
            let segmentToDispatch = String(pendingText[..<latestSentenceEndIndex])
            dispatchedCharacterCount += segmentToDispatch.count
            enqueueSpeechSegment(segmentToDispatch)
        }

        /// Called once Claude's stream is fully complete. Dispatches any
        /// remaining un-spoken text — typically a final fragment without
        /// trailing punctuation, or all of `cleanSpokenText` if the response
        /// happened to be a single short clause with no period.
        func dispatchAnyTrailingText(of cleanSpokenText: String) {
            let alreadyDispatchedCount = min(dispatchedCharacterCount, cleanSpokenText.count)
            let trailingStartIndex = cleanSpokenText.index(
                cleanSpokenText.startIndex,
                offsetBy: alreadyDispatchedCount
            )
            let trailingText = String(cleanSpokenText[trailingStartIndex...])
            let trimmedTrailingText = trailingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTrailingText.isEmpty else { return }
            dispatchedCharacterCount = cleanSpokenText.count
            enqueueSpeechSegment(trimmedTrailingText)
        }

        private func enqueueSpeechSegment(_ speechSegment: String) {
            guard let ttsClient else { return }
            let trimmedSpeechSegment = speechSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSpeechSegment.isEmpty else { return }

            let voiceIDForFetch = overrideVoiceID
            let epochForEnqueue = playbackChainEpoch

            // Kick off the ElevenLabs fetch right now so multiple sentences'
            // audio is fetched in parallel.
            let audioFetchTask = Task<Data, Error> { @MainActor [weak ttsClient] in
                guard let ttsClient else {
                    throw CancellationError()
                }
                return try await ttsClient.fetchAudioData(trimmedSpeechSegment, overrideVoiceID: voiceIDForFetch)
            }

            // Serialize the enqueue behind the prior segment so playback
            // order matches Claude's output order.
            let priorEnqueueTask = previousEnqueueTask
            previousEnqueueTask = Task { @MainActor [weak ttsClient] in
                _ = await priorEnqueueTask.value
                do {
                    let audioData = try await audioFetchTask.value
                    ttsClient?.enqueueAudioData(audioData, forEpoch: epochForEnqueue)
                } catch {
                    print("⚠️ TTS sentence fetch failed (segment dropped): \(error)")
                }
            }
        }

        /// Scans a string for the rightmost ".", "!", or "?" that's followed
        /// by whitespace, and returns the String.Index just past that
        /// trailing whitespace. Returning the position past the whitespace
        /// (rather than at the punctuation) means the next dispatched
        /// segment doesn't start with a stray space.
        ///
        /// Returns nil if no completed sentence boundary is present yet.
        private static func indexAfterLatestSentenceBoundary(in text: String) -> String.Index? {
            var latestBoundaryEndIndex: String.Index? = nil
            var currentIndex = text.startIndex
            while currentIndex < text.endIndex {
                let nextIndex = text.index(after: currentIndex)
                let currentCharacter = text[currentIndex]
                let isSentenceEndingPunctuation = currentCharacter == "."
                    || currentCharacter == "!"
                    || currentCharacter == "?"
                if isSentenceEndingPunctuation
                    && nextIndex < text.endIndex
                    && text[nextIndex].isWhitespace {
                    // Boundary ends just past the trailing whitespace
                    latestBoundaryEndIndex = text.index(after: nextIndex)
                }
                currentIndex = nextIndex
            }
            return latestBoundaryEndIndex
        }
    }

    // MARK: - Point Tag Parsing

    /// Result of parsing a [POINT:...] tag from Claude's response.
    struct PointingParseResult {
        /// The response text with the [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The parsed pixel coordinate, or nil if Claude said "none" or no tag was found.
        let coordinate: CGPoint?
        /// Short label describing the element (e.g. "run button"), or "none".
        let elementLabel: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// Parses a [POINT:x,y:label:screenN] or [POINT:none] tag from the end of Claude's response.
    /// Returns the spoken text (tag removed) and the optional coordinate + label + screen number.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2]
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            // No tag found at all
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        // Remove the tag from the spoken text
        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's [POINT:none]
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
        }

        var elementLabel: String? = nil
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int? = nil
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return PointingParseResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }

    // MARK: - Onboarding Video

    /// Sets up the onboarding video player, starts playback, and schedules
    /// the demo interaction at 40s. Called by BlueCursorView when onboarding starts.
    func setupOnboardingVideo() {
        guard let videoURL = URL(string: "https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8") else { return }

        let player = AVPlayer(url: videoURL)
        player.isMuted = false
        player.volume = 0.0
        self.onboardingVideoPlayer = player
        self.showOnboardingVideo = true
        self.onboardingVideoOpacity = 0.0

        // Start playback immediately — the video plays while invisible,
        // then we fade in both the visual and audio over 1s.
        player.play()

        // Wait for SwiftUI to mount the view, then set opacity to 1.
        // The .animation modifier on the view handles the actual animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onboardingVideoOpacity = 1.0
            // Fade audio volume from 0 → 1 over 2s to match visual fade
            self.fadeInVideoAudio(player: player, targetVolume: 1.0, duration: 2.0)
        }

        // At 40 seconds into the video, trigger the onboarding demo where
        // Sticky flies to something interesting on screen and comments on it
        let demoTriggerTime = CMTime(seconds: 40, preferredTimescale: 600)
        onboardingDemoTimeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: demoTriggerTime)],
            queue: .main
        ) { [weak self] in
            self?.performOnboardingDemoInteraction()
        }

        // Fade out and clean up when the video finishes
        onboardingVideoEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onboardingVideoOpacity = 0.0
            // Wait for the 2s fade-out animation to complete before tearing down
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.tearDownOnboardingVideo()
                // After the video disappears, stream in the prompt to try talking
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.startOnboardingPromptStream()
                }
            }
        }
    }

    func tearDownOnboardingVideo() {
        showOnboardingVideo = false
        if let timeObserver = onboardingDemoTimeObserver {
            onboardingVideoPlayer?.removeTimeObserver(timeObserver)
            onboardingDemoTimeObserver = nil
        }
        onboardingVideoPlayer?.pause()
        onboardingVideoPlayer = nil
        if let observer = onboardingVideoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingVideoEndObserver = nil
        }
    }

    private func startOnboardingPromptStream() {
        let message = "press control + option and introduce yourself"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }

    /// Gradually raises an AVPlayer's volume from its current level to the
    /// target over the specified duration, creating a smooth audio fade-in.
    private func fadeInVideoAudio(player: AVPlayer, targetVolume: Float, duration: Double) {
        let steps = 20
        let stepInterval = duration / Double(steps)
        let volumeIncrement = (targetVolume - player.volume) / Float(steps)
        var stepsRemaining = steps

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { timer in
            stepsRemaining -= 1
            player.volume += volumeIncrement

            if stepsRemaining <= 0 {
                timer.invalidate()
                player.volume = targetVolume
            }
        }
    }

    // MARK: - Onboarding Demo Interaction

    private static let onboardingDemoSystemPrompt = """
    you're sticky, a small blue cursor buddy living on the user's screen. you're showing off during onboarding — look at their screen and find ONE specific, concrete thing to point at. pick something with a clear name or identity: a specific app icon (say its name), a specific word or phrase of text you can read, a specific filename, a specific button label, a specific tab title, a specific image you can describe. do NOT point at vague things like "a window" or "some text" — be specific about exactly what you see.

    make a short quirky 3-6 word observation about the specific thing you picked — something fun, playful, or curious that shows you actually read/recognized it. no emojis ever. NEVER quote or repeat text you see on screen — just react to it. keep it to 6 words max, no exceptions.

    CRITICAL COORDINATE RULE: you MUST only pick elements near the CENTER of the screen. your x coordinate must be between 20%-80% of the image width. your y coordinate must be between 20%-80% of the image height. do NOT pick anything in the top 20%, bottom 20%, left 20%, or right 20% of the screen. no menu bar items, no dock icons, no sidebar items, no items near any edge. only things clearly in the middle area of the screen. if the only interesting things are near the edges, pick something boring in the center instead.

    respond with ONLY your short comment followed by the coordinate tag. nothing else. all lowercase.

    format: your comment [POINT:x,y:label]

    the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. origin (0,0) is top-left. x increases rightward, y increases downward.
    """

    /// Captures a screenshot and asks Claude to find something interesting to
    /// point at, then triggers the buddy's flight animation. Used during
    /// onboarding to demo the pointing feature while the intro video plays.
    func performOnboardingDemoInteraction() {
        // Don't interrupt an active voice response
        guard voiceState == .idle || voiceState == .responding else { return }

        Task {
            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                // Only send the cursor screen so Claude can't pick something
                // on a different monitor that we can't point at.
                guard let cursorScreenCapture = screenCaptures.first(where: { $0.isCursorScreen }) else {
                    print("🎯 Onboarding demo: no cursor screen found")
                    return
                }

                let dimensionInfo = " (image dimensions: \(cursorScreenCapture.screenshotWidthInPixels)x\(cursorScreenCapture.screenshotHeightInPixels) pixels)"
                let labeledImages = [(data: cursorScreenCapture.imageData, label: cursorScreenCapture.label + dimensionInfo)]

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.onboardingDemoSystemPrompt,
                    userPrompt: "look around my screen and find something interesting to point at",
                    onTextChunk: { _ in }
                )

                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)

                guard let pointCoordinate = parseResult.coordinate else {
                    print("🎯 Onboarding demo: no element to point at")
                    return
                }

                let screenshotWidth = CGFloat(cursorScreenCapture.screenshotWidthInPixels)
                let screenshotHeight = CGFloat(cursorScreenCapture.screenshotHeightInPixels)
                let displayWidth = CGFloat(cursorScreenCapture.displayWidthInPoints)
                let displayHeight = CGFloat(cursorScreenCapture.displayHeightInPoints)
                let displayFrame = cursorScreenCapture.displayFrame

                let clampedX = max(0, min(pointCoordinate.x, screenshotWidth))
                let clampedY = max(0, min(pointCoordinate.y, screenshotHeight))
                let displayLocalX = clampedX * (displayWidth / screenshotWidth)
                let displayLocalY = clampedY * (displayHeight / screenshotHeight)
                let appKitY = displayHeight - displayLocalY
                let globalLocation = CGPoint(
                    x: displayLocalX + displayFrame.origin.x,
                    y: appKitY + displayFrame.origin.y
                )

                // Set custom bubble text so the pointing animation uses Claude's
                // comment instead of a random phrase
                detectedElementBubbleText = parseResult.spokenText
                detectedElementScreenLocation = globalLocation
                detectedElementDisplayFrame = displayFrame
                print("🎯 Onboarding demo: pointing at \"\(parseResult.elementLabel ?? "element")\" — \"\(parseResult.spokenText)\"")
            } catch {
                print("⚠️ Onboarding demo error: \(error)")
            }
        }
    }
}
