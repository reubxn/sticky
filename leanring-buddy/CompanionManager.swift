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
import PostHog
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

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
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
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-sonnet-4-6"

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

    /// Plays a short "Hey, I'm Sticky!" preview through the given voice
    /// so the user can test it in the panel dropdown before committing.
    /// Cancels any in-flight preview first so rapid clicking through the
    /// list doesn't stack up overlapping playback. Does NOT change the
    /// persisted `selectedVoiceID` — selection is a separate action.
    func previewVoice(_ voiceID: String?) {
        voicePreviewTask?.cancel()
        elevenLabsTTSClient.stopPlayback()

        voicePreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.previewingVoiceID = voiceID ?? Self.defaultVoicePreviewSentinel
            do {
                try await self.elevenLabsTTSClient.speakText(
                    "Hey, I'm Sticky!",
                    overrideVoiceID: voiceID
                )
                // speakText returns once playback starts — poll until it
                // actually finishes so the panel UI keeps the stop icon
                // visible for the full duration of the clip.
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

    /// User preference for whether the Clicky cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isClickyCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isClickyCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isClickyCursorEnabled")

    // MARK: - Reverse Clicky: Taste Modes

    /// Which taste mode the app is in. .ask is the default Clicky behaviour.
    /// .teach captures Loom-style sessions for taste extraction. .apply prepends
    /// the saved taste profile to the system prompt for every voice question.
    /// Persisted to UserDefaults so the user's mode survives restarts.
    @Published var tasteMode: TasteMode = {
        if let rawTasteMode = UserDefaults.standard.string(forKey: "tasteMode"),
           let storedTasteMode = TasteMode(rawValue: rawTasteMode) {
            return storedTasteMode
        }
        return .ask
    }()

    func setTasteMode(_ newTasteMode: TasteMode) {
        tasteMode = newTasteMode
        UserDefaults.standard.set(newTasteMode.rawValue, forKey: "tasteMode")
    }

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

    /// Most recent count of confident principles auto-saved from a finished
    /// teach session. Drives the small "Saved N principle(s)" toast in the
    /// panel so the user gets feedback even when the session has no
    /// ambiguous moments to review.
    @Published private(set) var lastTeachSessionSavedPrincipleCount: Int = 0

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

    /// Whether the user has completed onboarding at least once. Persisted
    /// to UserDefaults so the Start button only appears on first launch.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has submitted their email during onboarding.
    @Published var hasSubmittedEmail: Bool = UserDefaults.standard.bool(forKey: "hasSubmittedEmail")

    /// Submits the user's email to FormSpark and identifies them in PostHog.
    func submitEmail(_ email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        hasSubmittedEmail = true
        UserDefaults.standard.set(true, forKey: "hasSubmittedEmail")

        // Identify user in PostHog
        PostHogSDK.shared.identify(trimmedEmail, userProperties: [
            "email": trimmedEmail
        ])

        // Submit to FormSpark
        Task {
            var request = URLRequest(url: URL(string: "https://submit-form.com/RWbGJxmIs")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmedEmail])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Clicky start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindTTSPowerLevel()
        bindShortcutTransitions()
        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = claudeAPI

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

        ClickyAnalytics.trackOnboardingStarted()

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
        ClickyAnalytics.trackOnboardingReplayed()
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
            print("⚠️ Clicky: ff.mp3 not found in bundle")
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
            print("⚠️ Clicky: Failed to play onboarding music: \(error)")
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

        Task { @MainActor [weak self] in
            do {
                let analysis = try await SessionAnalyzer.analyzeTeachSession(
                    transcript: trimmedTranscript,
                    frames: capturedFrames,
                    claudeAPI: analyzerClaudeAPI
                )
                self?.lastTeachSessionResult = analysis.result
                Self.printTeachSessionResultForDebugging(analysis.result)

                // Confident principles auto-save to the central mind on disk.
                let savedCount = self?.persistConfidentPrinciplesFromTeachSession(analysis.result) ?? 0
                self?.lastTeachSessionSavedPrincipleCount = savedCount

                // Ambiguous moments queue up as review cards. We hold onto
                // the analyzer's selected frames so each card can render a
                // thumbnail of the moment in question. Both queues are
                // cleared together when the user finishes (or ends) review.
                self?.pendingAmbiguousMoments = analysis.result.ambiguous
                self?.pendingReviewFrames = analysis.result.ambiguous.isEmpty
                    ? []
                    : analysis.selectedFrames

                self?.resetTeachSessionState()
            } catch {
                print("⚠️ Teach session analysis failed: \(error)")
                self?.resetTeachSessionState()
            }
        }
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

        do {
            try TasteProfileStore.appendApprovedPrinciples([chosenPrinciple])
            print("🧠 Review: approved principle — \(chosenPrinciple.statement)")
        } catch {
            print("⚠️ Review: failed to save approved principle: \(error)")
        }

        advanceReviewQueue()
    }

    /// Skips the current ambiguous moment without saving any principle.
    /// Used when the user doesn't want any of the suggested options and
    /// doesn't feel like typing a custom one.
    func skipCurrentReviewMoment() {
        guard !pendingAmbiguousMoments.isEmpty else { return }
        print("🧠 Review: skipped a moment")
        advanceReviewQueue()
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
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
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

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
            ClickyAnalytics.trackPermissionGranted(permission: "accessibility")
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
            ClickyAnalytics.trackPermissionGranted(permission: "screen_recording")
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
            ClickyAnalytics.trackPermissionGranted(permission: "microphone")
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
            ClickyAnalytics.trackAllPermissionsGranted()
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
                    ClickyAnalytics.trackPermissionGranted(permission: "screen_content")

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
    

            ClickyAnalytics.trackPushToTalkStarted()

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
                        ClickyAnalytics.trackUserMessageSent(transcript: finalTranscript)
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            ClickyAnalytics.trackPushToTalkReleased()
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're clicky, a friendly always-on companion that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    rules:
    - default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out — give a thorough, detailed explanation with no length limit.
    - all lowercase, casual, warm. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" — those are dead ends that force the user to just say yes.
    - instead, when it fits naturally, end by planting a seed — mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing:
    you have a small blue parallelogram cursor that can fly to and point at things on screen. use it whenever pointing would genuinely help the user — if they're asking how to do something, looking for a menu, trying to find a button, or need help navigating an app, point at the relevant element. err on the side of pointing rather than not pointing, because it makes your help way more useful and concrete.

    don't point at things when it would be pointless — like if the user asks a general knowledge question, or the conversation has nothing to do with what's on screen, or you'd just be pointing at something obvious they're already looking at. but if there's a specific UI element, menu, button, or area on screen that's relevant to what you're helping with, point at it.

    when you point, append a coordinate tag at the very end of your response, AFTER your spoken text. the screenshot images are labeled with their pixel dimensions. use those dimensions as the coordinate space. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward.

    format: [POINT:x,y:label] where x,y are integer pixel coordinates in the screenshot's coordinate space, and label is a short 1-3 word description of the element (like "search bar" or "save button"). if the element is on the cursor's screen you can omit the screen number. if the element is on a DIFFERENT screen, append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if pointing wouldn't help, append [POINT:none].

    examples:
    - user asks how to color grade in final cut: "you'll want to open the color inspector — it's right up in the top right area of the toolbar. click that and you'll get all the color wheels and curves. [POINT:1100,42:color inspector]"
    - user asks what html is: "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
    - user asks how to commit in xcode: "see that source control menu up top? click that and hit commit, or you can use command option c as a shortcut. [POINT:285,11:source control]"
    - element is on screen 2 (not where cursor is): "that's over on your other monitor — see the terminal window? [POINT:400,300:terminal:screen2]"
    """

    /// Builds the system prompt for the existing voice flow with the user's
    /// saved taste prepended as judgment context. Honors the active scope —
    /// personal-only or personal ∪ team. Falls back to the unmodified base
    /// prompt if the profile is empty or fails to load — Sticky should
    /// never break because of a taste-file issue.
    private func composeVoiceSystemPromptWithTaste() -> String {
        let basePrompt = Self.companionVoiceResponseSystemPrompt

        let loadedPersonalProfile: TasteProfile
        do {
            loadedPersonalProfile = try TasteProfileStore.loadProfile()
        } catch {
            print("⚠️ Couldn't load personal taste profile, using base prompt: \(error)")
            return basePrompt
        }

        // Team profile is best-effort. If it's missing or malformed we just
        // run with personal-only — no need to fail the whole prompt build.
        let loadedTeamProfile: TeamTasteProfile? = (tasteScope == .team)
            ? TeamTasteProfileStore.loadTeamProfile()
            : nil

        let tasteContextBlock = TastePromptBuilder.tasteContextBlock(
            personalProfile: loadedPersonalProfile,
            teamProfile: loadedTeamProfile,
            scope: tasteScope
        )
        guard !tasteContextBlock.isEmpty else {
            return basePrompt
        }

        let approvedPersonalCount = loadedPersonalProfile.principles.filter { $0.approved }.count
        let approvedTeamCount = loadedTeamProfile?.principles.filter { $0.approved }.count ?? 0
        switch tasteScope {
        case .personal:
            print("🧠 Applying \(approvedPersonalCount) personal taste principle(s) to voice prompt")
        case .team:
            print("🧠 Applying taste — \(approvedPersonalCount) personal + \(approvedTeamCount) team principle(s)")
        }

        return tasteContextBlock + "\n\n" + basePrompt
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

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Capture all connected screens so the AI has full context
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

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

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: composedSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { _ in
                        // No streaming text display — spinner stays until TTS plays
                    }
                )

                guard !Task.isCancelled else { return }

                // Parse the [POINT:...] tag from Claude's response
                let parseResult = Self.parsePointingCoordinates(from: fullResponseText)
                let spokenText = parseResult.spokenText

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
                    ClickyAnalytics.trackElementPointed(elementLabel: parseResult.elementLabel)
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

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")

                ClickyAnalytics.trackAIResponseReceived(response: spokenText)

                // Play the response via TTS. Keep the spinner (processing state)
                // until the audio actually starts playing, then switch to responding.
                if !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try await elevenLabsTTSClient.speakText(spokenText, overrideVoiceID: selectedVoiceID)
                        // speakText returns after player.play() — audio is now playing
                        voiceState = .responding
                    } catch {
                        ClickyAnalytics.trackTTSError(error: error.localizedDescription)
                        print("⚠️ ElevenLabs TTS error: \(error)")
                        speakCreditsErrorFallback()
                    }
                }
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch {
                ClickyAnalytics.trackResponseError(error: error.localizedDescription)
                print("⚠️ Companion response error: \(error)")
                speakCreditsErrorFallback()
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// If the cursor is in transient mode (user toggled "Show Clicky" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isClickyCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while elevenLabsTTSClient.isPlaying {
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

    /// Speaks a hardcoded error message using macOS system TTS when API
    /// credits run out. Uses NSSpeechSynthesizer so it works even when
    /// ElevenLabs is down.
    private func speakCreditsErrorFallback() {
        let utterance = "I'm all out of credits. Please DM Farza and tell him to bring me back to life."
        let synthesizer = NSSpeechSynthesizer()
        fallbackSpeechSynthesizer = synthesizer
        synthesizer.startSpeaking(utterance)
        voiceState = .responding
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
        // Clicky flies to something interesting on screen and comments on it
        let demoTriggerTime = CMTime(seconds: 40, preferredTimescale: 600)
        onboardingDemoTimeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: demoTriggerTime)],
            queue: .main
        ) { [weak self] in
            ClickyAnalytics.trackOnboardingDemoTriggered()
            self?.performOnboardingDemoInteraction()
        }

        // Fade out and clean up when the video finishes
        onboardingVideoEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            ClickyAnalytics.trackOnboardingVideoCompleted()
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
    you're clicky, a small blue cursor buddy living on the user's screen. you're showing off during onboarding — look at their screen and find ONE specific, concrete thing to point at. pick something with a clear name or identity: a specific app icon (say its name), a specific word or phrase of text you can read, a specific filename, a specific button label, a specific tab title, a specific image you can describe. do NOT point at vague things like "a window" or "some text" — be specific about exactly what you see.

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
