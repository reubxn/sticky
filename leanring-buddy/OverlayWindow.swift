//
//  OverlayWindow.swift
//  leanring-buddy
//
//  System-wide transparent overlay window for blue glowing cursor.
//  One OverlayWindow is created per screen so the cursor buddy
//  seamlessly follows the cursor across multiple monitors.
//

import AppKit
import AVFoundation
import SwiftUI

class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        // Create window covering entire screen
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Make window transparent and non-interactive
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver  // Always on top, above submenus and popups
        self.ignoresMouseEvents = true  // Click-through
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hasShadow = false

        // Important: Allow the window to appear even when app is not active
        self.hidesOnDeactivate = false

        // Cover the entire screen
        self.setFrame(screen.frame, display: true)

        // Make sure it's on the right screen
        if let screenForWindow = NSScreen.screens.first(where: { $0.frame == screen.frame }) {
            self.setFrameOrigin(screenForWindow.frame.origin)
        }
    }

    // Prevent window from becoming key (no focus stealing)
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }
}

// PreferenceKey for tracking bubble size
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct NavigationBubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// The buddy's behavioral mode. Controls whether it follows the cursor,
/// is flying toward a detected UI element, or is pointing at an element.
enum BuddyNavigationMode {
    /// Default — buddy follows the mouse cursor with spring animation
    case followingCursor
    /// Buddy is animating toward a detected UI element location
    case navigatingToTarget
    /// Buddy has arrived at the target and is pointing at it with a speech bubble
    case pointingAtTarget
}

// SwiftUI view for the blue glowing cursor pointer.
// Each screen gets its own BlueCursorView. The view checks whether
// the cursor is currently on THIS screen and only shows the buddy
// triangle when it is. During voice interaction, the triangle is
// replaced by a waveform (listening), spinner (processing), or
// streaming text bubble (responding).
struct BlueCursorView: View {
    let screenFrame: CGRect
    let isFirstAppearance: Bool
    @ObservedObject var companionManager: CompanionManager

    @State private var cursorPosition: CGPoint
    @State private var isCursorOnThisScreen: Bool

    init(screenFrame: CGRect, isFirstAppearance: Bool, companionManager: CompanionManager) {
        self.screenFrame = screenFrame
        self.isFirstAppearance = isFirstAppearance
        self.companionManager = companionManager

        // Seed the cursor position from the current mouse location so the
        // buddy doesn't flash at (0,0) before onAppear fires.
        let mouseLocation = NSEvent.mouseLocation
        let localX = mouseLocation.x - screenFrame.origin.x
        let localY = screenFrame.height - (mouseLocation.y - screenFrame.origin.y)
        _cursorPosition = State(initialValue: CGPoint(x: localX + 35, y: localY + 25))
        _isCursorOnThisScreen = State(initialValue: screenFrame.contains(mouseLocation))
    }
    @State private var timer: Timer?
    @State private var welcomeText: String = ""
    @State private var showWelcome: Bool = true
    @State private var bubbleSize: CGSize = .zero
    @State private var bubbleOpacity: Double = 1.0
    @State private var cursorOpacity: Double = 0.0

    // MARK: - Buddy Navigation State

    /// The buddy's current behavioral mode (following cursor, navigating, or pointing).
    @State private var buddyNavigationMode: BuddyNavigationMode = .followingCursor

    /// The rotation angle of the triangle in degrees. Default is -35° (cursor-like).
    /// Changes to face the direction of travel when navigating to a target.
    @State private var triangleRotationDegrees: Double = -35.0

    /// Speech bubble text shown when pointing at a detected element.
    @State private var navigationBubbleText: String = ""
    @State private var navigationBubbleOpacity: Double = 0.0
    @State private var navigationBubbleSize: CGSize = .zero

    /// The cursor position at the moment navigation started, used to detect
    /// if the user moves the cursor enough to cancel the navigation.
    @State private var cursorPositionWhenNavigationStarted: CGPoint = .zero

    /// The final destination of the current navigation, in this screen's
    /// SwiftUI coordinates. Set when navigation starts and cleared when the
    /// buddy returns to cursor-following. Drives the edge-glow gravity
    /// effect so the aurora visibly pulls toward the element being
    /// pointed at — non-nil through both `.navigatingToTarget` and
    /// `.pointingAtTarget` so the pull stays anchored on the destination
    /// throughout the flight and the dwell.
    @State private var navigationTargetPosition: CGPoint?

    /// Timer driving the frame-by-frame bezier arc flight animation.
    /// Invalidated when the flight completes, is canceled, or the view disappears.
    @State private var navigationAnimationTimer: Timer?

    /// Scale factor applied to the buddy triangle during flight. Grows to ~1.3x
    /// at the midpoint of the arc and shrinks back to 1.0x on landing, creating
    /// an energetic "swooping" feel.
    @State private var buddyFlightScale: CGFloat = 1.0

    /// Scale factor for the navigation speech bubble's pop-in entrance.
    /// Starts at 0.5 and springs to 1.0 when the first character appears.
    @State private var navigationBubbleScale: CGFloat = 1.0

    /// True when the buddy is flying BACK to the cursor after pointing.
    /// Only during the return flight can cursor movement cancel the animation.
    @State private var isReturningToCursor: Bool = false

    // MARK: - Onboarding Video Layout

    private let onboardingVideoPlayerWidth: CGFloat = 330
    private let onboardingVideoPlayerHeight: CGFloat = 186

    private let fullWelcomeMessage = "hey! i'm sticky"

    private let navigationPointerPhrases = [
        "right here!",
        "this one!",
        "over here!",
        "click this!",
        "here it is!",
        "found it!"
    ]

    // MARK: - Orb & edge glow visibility

    /// True when the orb itself should be on-screen. The orb no longer
    /// follows the cursor: it appears only when Sticky is "showing the
    /// user something" — i.e. flying to or pointing at a detected element.
    /// Idle, listening, and processing all show nothing on this screen
    /// except (during listening) the audio-reactive edge glow.
    private var orbShouldBeVisible: Bool {
        guard buddyIsVisibleOnThisScreen else { return false }
        return buddyNavigationMode == .navigatingToTarget
            || buddyNavigationMode == .pointingAtTarget
    }

    // MARK: - Persona Wheel Render

    /// Draws the radial persona picker centered on whatever point the
    /// user's cursor was at when they pressed the wheel hotkey. Only
    /// rendered on the screen containing the anchor — overlays on other
    /// screens return EmptyView so the wheel doesn't ghost across all
    /// displays. The wheel scales/fades in via SwiftUI transition when
    /// `isPersonaWheelVisible` flips true.
    @ViewBuilder
    private var personaWheelOverlay: some View {
        if companionManager.isPersonaWheelVisible,
           let wheelCenterScreenLocation = companionManager.personaWheelCenterScreenLocation,
           screenFrame.contains(wheelCenterScreenLocation) {

            let wheelCenterInSwiftUI = convertScreenPointToSwiftUICoordinates(wheelCenterScreenLocation)

            PersonaWheelView(
                personas: companionManager.allWheelPersonas,
                hoveredPersonaId: companionManager.hoveredWheelPersonaId,
                activePersonaId: companionManager.activeWheelPersonaId
            )
                .position(wheelCenterInSwiftUI)
                .transition(
                    .scale(scale: 0.7, anchor: .center)
                        .combined(with: .opacity)
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.78),
                           value: companionManager.isPersonaWheelVisible)
                .allowsHitTesting(false)
        }
    }

    /// True when the screen-edge glow should be on this screen. Visible
    /// across the entire active arc of an interaction — listening (user
    /// speaking), processing (waiting for the AI), and responding (AI
    /// speaking back) — so the user always has a luminous indication
    /// that Sticky is engaged. Also visible while a Reverse Clicky teach
    /// session is recording, so the user knows the mic is open even
    /// when the panel is dismissed. Hidden only when idle and no teach
    /// session is running.
    private var edgeGlowShouldBeVisible: Bool {
        guard buddyIsVisibleOnThisScreen else { return false }
        if companionManager.teachSessionState == .recording { return true }
        switch companionManager.voiceState {
        case .listening, .processing, .responding:
            return true
        case .idle:
            return false
        }
    }

    /// Maps the current voice / teach-session state to the visual mode
    /// the EdgeGlowView should render in. Each mode picks its own anchor
    /// (which edges glow) and the caller supplies the matching color +
    /// audio source. Teach-session recording takes priority over voice
    /// state because the user might still be holding push-to-talk while
    /// a session is recording — the four-edge halo is the more
    /// important indicator to show in that overlap.
    private var edgeGlowMode: EdgeGlowMode {
        if companionManager.teachSessionState == .recording {
            return .teachRecording
        }
        switch companionManager.voiceState {
        case .listening: return .listeningToUser
        case .processing: return .processingThinking
        case .responding: return .respondingWithAI
        case .idle: return .listeningToUser  // unused — view is hidden
        }
    }

    /// Picks which audio source drives the glow's intensity for the
    /// current mode. Listening / teach-recording use the live mic level
    /// (the user is talking); responding uses the TTS playback level
    /// (Sticky is talking); processing feeds 0 because the EdgeGlowView
    /// synthesizes its own breathing pulse in that mode.
    private var edgeGlowAudioPowerLevel: CGFloat {
        if companionManager.teachSessionState == .recording {
            return companionManager.currentAudioPowerLevel
        }
        switch companionManager.voiceState {
        case .listening: return companionManager.currentAudioPowerLevel
        case .responding: return companionManager.currentTTSPowerLevel
        case .processing, .idle: return 0
        }
    }

    /// Picks the color of the glow based on whose turn it is in the
    /// conversation. The user's voice (listening / processing /
    /// teach-recording) always glows in the fixed user color (blue) so
    /// the speaking-side identity is stable across persona switches.
    /// The persona's reply (responding) glows in the active persona's
    /// accent color — the same hex shown on its spoke in the shift+cmd
    /// wheel — so swapping persona on the wheel and seeing the reply
    /// glow are visually consistent.
    private var edgeGlowColor: Color {
        switch edgeGlowMode {
        case .respondingWithAI:
            return companionManager.personaReplyEdgeGlowColor
        case .listeningToUser, .processingThinking, .teachRecording:
            return companionManager.userVoiceColor
        }
    }

    var body: some View {
        ZStack {
            // Nearly transparent background (helps with compositing)
            Color.black.opacity(0.001)

            // Screen-edge glow — visible while the user is holding
            // push-to-talk. This is the only ambient indicator now;
            // it replaces the old cursor-anchored waveform/orb mic
            // indicator. Sits at the back of the ZStack so all other
            // UI (bubbles, orb) renders cleanly on top.
            EdgeGlowView(
                audioPowerLevel: edgeGlowAudioPowerLevel,
                mode: edgeGlowMode,
                color: edgeGlowColor
            )
                .opacity(edgeGlowShouldBeVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: companionManager.voiceState)
                .animation(.easeInOut(duration: 0.4), value: companionManager.teachSessionState)
                .animation(.linear(duration: 0.08), value: edgeGlowAudioPowerLevel)

            // Welcome speech bubble (first launch only)
            if isCursorOnThisScreen && showWelcome && !welcomeText.isEmpty {
                Text(welcomeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(companionManager.stickyVoiceColor)
                            .shadow(color: companionManager.stickyVoiceColor.opacity(0.5), radius: 6, x: 0, y: 0)
                    )
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: SizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .opacity(bubbleOpacity)
                    .position(x: cursorPosition.x + 10 + (bubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.easeOut(duration: 0.5), value: bubbleOpacity)
                    .onPreferenceChange(SizePreferenceKey.self) { newSize in
                        bubbleSize = newSize
                    }
            }

            // Onboarding video — always in the view tree so opacity animation works
            // reliably. When no player exists or opacity is 0, nothing is visible.
            // allowsHitTesting(false) prevents it from intercepting clicks.
            OnboardingVideoPlayerView(player: companionManager.onboardingVideoPlayer)
                .frame(width: onboardingVideoPlayerWidth, height: onboardingVideoPlayerHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.4 * companionManager.onboardingVideoOpacity), radius: 12, x: 0, y: 6)
                .opacity(isCursorOnThisScreen ? companionManager.onboardingVideoOpacity : 0)
                .position(
                    x: cursorPosition.x + 10 + (onboardingVideoPlayerWidth / 2),
                    y: cursorPosition.y + 18 + (onboardingVideoPlayerHeight / 2)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeInOut(duration: 2.0), value: companionManager.onboardingVideoOpacity)
                .allowsHitTesting(false)

            // Onboarding prompt — "press control + option and say hi" streamed after video ends
            if isCursorOnThisScreen && companionManager.showOnboardingPrompt && !companionManager.onboardingPromptText.isEmpty {
                Text(companionManager.onboardingPromptText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(companionManager.stickyVoiceColor)
                            .shadow(color: companionManager.stickyVoiceColor.opacity(0.5), radius: 6, x: 0, y: 0)
                    )
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: SizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .opacity(companionManager.onboardingPromptOpacity)
                    .position(x: cursorPosition.x + 10 + (bubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.easeOut(duration: 0.4), value: companionManager.onboardingPromptOpacity)
                    .onPreferenceChange(SizePreferenceKey.self) { newSize in
                        bubbleSize = newSize
                    }
            }

            // Navigation pointer bubble — shown when buddy arrives at a detected element.
            // Pops in with a scale-bounce (0.5x → 1.0x spring) and a bright initial
            // glow that settles, creating a "materializing" effect.
            if buddyNavigationMode == .pointingAtTarget && !navigationBubbleText.isEmpty {
                Text(navigationBubbleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.leading, 14)  // extra room on the left for the tail
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
                    .background(
                        ChatBubbleShape(cornerRadius: 8)
                            .fill(companionManager.stickyVoiceColor)
                            .shadow(
                                color: companionManager.stickyVoiceColor.opacity(0.5 + (1.0 - navigationBubbleScale) * 1.0),
                                radius: 6 + (1.0 - navigationBubbleScale) * 16,
                                x: 0, y: 0
                            )
                    )
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: NavigationBubbleSizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .scaleEffect(navigationBubbleScale)
                    .opacity(navigationBubbleOpacity)
                    .position(x: cursorPosition.x + 10 + (navigationBubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: navigationBubbleScale)
                    .animation(.easeOut(duration: 0.5), value: navigationBubbleOpacity)
                    .onPreferenceChange(NavigationBubbleSizePreferenceKey.self) { newSize in
                        navigationBubbleSize = newSize
                    }
            }

            // Applied-taste transparency chip — appears below the cursor
            // after a voice reply that actually leaned on the user's
            // saved principles, listing which ones Sticky used. Drawn
            // ONLY on the screen the cursor is currently on so the chip
            // doesn't duplicate across multiple monitors. Visibility is
            // gated on `isShowingAppliedPrinciplesChip` — CompanionManager
            // only flips that flag on when at least one principle was
            // applied, so we don't need a separate empty-state branch here.
            if isCursorOnThisScreen
                && companionManager.isShowingAppliedPrinciplesChip {
                AppliedPrinciplesChip(
                    lastAppliedPrinciples: companionManager.lastAppliedPrinciples,
                    lastAppliedSourceWasTeam: companionManager.lastAppliedSourceWasTeam,
                    teamOriginPrincipleIds: companionManager.teamOriginPrincipleIds
                )
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                // Anchor the chip a bit further below the cursor than the
                // navigation bubble so they don't visually collide if a
                // [POINT:...] tag was also returned in the same reply.
                .position(x: cursorPosition.x + 170, y: cursorPosition.y + 60)
                .animation(.easeInOut(duration: 0.25), value: companionManager.isShowingAppliedPrinciplesChip)
                .animation(.easeInOut(duration: 0.2), value: companionManager.lastAppliedPrinciples)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Mystical orb — only visible when Sticky is "showing the user
            // something" (flying to a target or pointing at one). It does
            // NOT follow the cursor. During the bezier flight, position is
            // driven frame-by-frame by the navigation timer; we suppress
            // the implicit animation so the arc stays smooth.
            // The orb is symmetric so triangleRotationDegrees no longer
            // drives a visible rotation; the directional cue during flight
            // comes from buddyFlightScale (grows mid-arc, shrinks on landing).
            MysticalOrbView(
                bodyColor: companionManager.stickyVoiceColor,
                personaAvatar: companionManager.activePersonaAvatar
            )
                .shadow(color: companionManager.stickyVoiceColor.opacity(0.6), radius: 8 + (buddyFlightScale - 1.0) * 20, x: 0, y: 0)
                .scaleEffect(buddyFlightScale)
                .opacity(orbShouldBeVisible ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.easeInOut(duration: 0.4), value: orbShouldBeVisible)

            // Persona wheel overlay — drawn last so it sits on top of
            // the cursor orb, edge glow, and any speech bubble while
            // the user is holding the wheel hotkey. Only renders on
            // the screen containing the wheel's anchor point so the
            // other displays stay clean.
            personaWheelOverlay
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .onAppear {
            // Set initial cursor position immediately before starting animation
            let mouseLocation = NSEvent.mouseLocation
            isCursorOnThisScreen = screenFrame.contains(mouseLocation)

            let swiftUIPosition = convertScreenPointToSwiftUICoordinates(mouseLocation)
            self.cursorPosition = CGPoint(x: swiftUIPosition.x + 35, y: swiftUIPosition.y + 25)

            startTrackingCursor()

            // Only show welcome message on first appearance (app start)
            // and only if the cursor starts on this screen
            if isFirstAppearance && isCursorOnThisScreen {
                withAnimation(.easeIn(duration: 2.0)) {
                    self.cursorOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                    startWelcomeAnimation()
                }
            } else {
                self.cursorOpacity = 1.0
            }
        }
        .onDisappear {
            timer?.invalidate()
            navigationAnimationTimer?.invalidate()
            companionManager.tearDownOnboardingVideo()
        }
        .onChange(of: companionManager.detectedElementScreenLocation) { newLocation in
            // When a UI element location is detected, navigate the buddy to
            // that position so it points at the element.
            guard let screenLocation = newLocation,
                  let displayFrame = companionManager.detectedElementDisplayFrame else {
                return
            }

            // Only navigate if the target is on THIS screen
            guard screenFrame.contains(CGPoint(x: displayFrame.midX, y: displayFrame.midY))
                  || displayFrame == screenFrame else {
                return
            }

            startNavigatingToElement(screenLocation: screenLocation)
        }
    }

    /// Whether the buddy triangle should be visible on this screen.
    /// True when cursor is on this screen during normal following, or
    /// when navigating/pointing at a target on this screen. When another
    /// screen is navigating (detectedElementScreenLocation is set but this
    /// screen isn't the one animating), hide the cursor so only one buddy
    /// is ever visible at a time.
    private var buddyIsVisibleOnThisScreen: Bool {
        switch buddyNavigationMode {
        case .followingCursor:
            // If another screen's BlueCursorView is navigating to an element,
            // hide the cursor on this screen to prevent a duplicate buddy
            if companionManager.detectedElementScreenLocation != nil {
                return false
            }
            return isCursorOnThisScreen
        case .navigatingToTarget, .pointingAtTarget:
            return true
        }
    }

    // MARK: - Cursor Tracking

    private func startTrackingCursor() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            let mouseLocation = NSEvent.mouseLocation
            self.isCursorOnThisScreen = self.screenFrame.contains(mouseLocation)

            // While the persona wheel is held open, every cursor frame
            // figures out which spoke the user is pointing at and
            // pushes the result into CompanionManager so the wheel
            // (rendered below in the same view) and the release-commit
            // logic both see a fresh hovered id.
            self.updateHoveredPersonaSpokeIfWheelVisible(currentMouseLocation: mouseLocation)

            // During forward flight or pointing, the buddy is NOT interrupted by
            // mouse movement — it completes its full animation and return flight.
            // Only during the RETURN flight do we allow cursor movement to cancel
            // (so the buddy snaps to following if the user moves while it's flying back).
            if self.buddyNavigationMode == .navigatingToTarget && self.isReturningToCursor {
                let currentMouseInSwiftUI = self.convertScreenPointToSwiftUICoordinates(mouseLocation)
                let distanceFromNavigationStart = hypot(
                    currentMouseInSwiftUI.x - self.cursorPositionWhenNavigationStarted.x,
                    currentMouseInSwiftUI.y - self.cursorPositionWhenNavigationStarted.y
                )
                if distanceFromNavigationStart > 100 {
                    cancelNavigationAndResumeFollowing()
                }
                return
            }

            // During forward navigation or pointing, just skip cursor tracking
            if self.buddyNavigationMode != .followingCursor {
                return
            }

            // Normal cursor following
            let swiftUIPosition = self.convertScreenPointToSwiftUICoordinates(mouseLocation)
            let buddyX = swiftUIPosition.x + 35
            let buddyY = swiftUIPosition.y + 25
            self.cursorPosition = CGPoint(x: buddyX, y: buddyY)
        }
    }

    /// Converts a macOS screen point (AppKit, bottom-left origin) to SwiftUI
    /// coordinates (top-left origin) relative to this screen's overlay window.
    private func convertScreenPointToSwiftUICoordinates(_ screenPoint: CGPoint) -> CGPoint {
        let x = screenPoint.x - screenFrame.origin.x
        let y = (screenFrame.origin.y + screenFrame.height) - screenPoint.y
        return CGPoint(x: x, y: y)
    }

    // MARK: - Persona Wheel Hover Tracking

    /// While the persona wheel is held open, computes which spoke the
    /// cursor is currently pointing toward (or nil for the dead zone)
    /// and writes the result back to CompanionManager. Only the
    /// overlay covering the screen the wheel was summoned on does the
    /// computation — overlays on other screens skip it so the published
    /// hovered-id isn't being clobbered by N writers per frame.
    private func updateHoveredPersonaSpokeIfWheelVisible(currentMouseLocation: CGPoint) {
        guard companionManager.isPersonaWheelVisible,
              let wheelCenterScreenLocation = companionManager.personaWheelCenterScreenLocation else {
            return
        }

        // Only the overlay containing the wheel's anchor point owns
        // hover updates. (When the cursor crosses to another screen
        // mid-hold, the cursor moves but the wheel stays anchored —
        // releasing dismisses it without a commit, which feels right.)
        guard screenFrame.contains(wheelCenterScreenLocation) else { return }

        let cursorOffsetFromWheelCenter = CGPoint(
            x: currentMouseLocation.x - wheelCenterScreenLocation.x,
            // Negate so positive y-offset reads as "below the center"
            // in SwiftUI screen-space (matches the wheel's spoke layout).
            y: wheelCenterScreenLocation.y - currentMouseLocation.y
        )

        let totalSpokeCount = companionManager.allWheelPersonas.count
        let hoveredSpokeIndex = PersonaWheelGeometry.hoveredSpokeIndex(
            cursorOffsetFromCenter: cursorOffsetFromWheelCenter,
            totalSpokes: totalSpokeCount
        )

        let hoveredPersonaId: String?
        if let hoveredSpokeIndex,
           hoveredSpokeIndex >= 0,
           hoveredSpokeIndex < totalSpokeCount {
            hoveredPersonaId = companionManager.allWheelPersonas[hoveredSpokeIndex].id
        } else {
            hoveredPersonaId = nil
        }

        if companionManager.hoveredWheelPersonaId != hoveredPersonaId {
            companionManager.hoveredWheelPersonaId = hoveredPersonaId
        }
    }

    // MARK: - Element Navigation

    /// Starts animating the buddy toward a detected UI element location.
    private func startNavigatingToElement(screenLocation: CGPoint) {
        // Don't interrupt welcome animation
        guard !showWelcome || welcomeText.isEmpty else { return }

        // Convert the AppKit screen location to SwiftUI coordinates for this screen
        let targetInSwiftUI = convertScreenPointToSwiftUICoordinates(screenLocation)

        // Offset the target so the buddy sits beside the element rather than
        // directly on top of it — 8px to the right, 12px below.
        let offsetTarget = CGPoint(
            x: targetInSwiftUI.x + 8,
            y: targetInSwiftUI.y + 12
        )

        // Clamp target to screen bounds with padding
        let clampedTarget = CGPoint(
            x: max(20, min(offsetTarget.x, screenFrame.width - 20)),
            y: max(20, min(offsetTarget.y, screenFrame.height - 20))
        )

        // Record the current cursor position so we can detect if the user
        // moves the mouse enough to cancel the return flight
        let mouseLocation = NSEvent.mouseLocation
        cursorPositionWhenNavigationStarted = convertScreenPointToSwiftUICoordinates(mouseLocation)

        // Enter navigation mode — stop cursor following
        buddyNavigationMode = .navigatingToTarget
        isReturningToCursor = false
        // Anchor the edge-glow gravity to the destination as soon as
        // the flight begins, so the aurora is already pulling toward
        // the target before the buddy finishes its arc.
        navigationTargetPosition = clampedTarget

        animateBezierFlightArc(to: clampedTarget) {
            guard self.buddyNavigationMode == .navigatingToTarget else { return }
            self.startPointingAtElement()
        }
    }

    /// Animates the buddy along a quadratic bezier arc from its current position
    /// to the specified destination. The triangle rotates to face its direction
    /// of travel (tangent to the curve) each frame, scales up at the midpoint
    /// for a "swooping" feel, and the glow intensifies during flight.
    private func animateBezierFlightArc(
        to destination: CGPoint,
        onComplete: @escaping () -> Void
    ) {
        navigationAnimationTimer?.invalidate()

        let startPosition = cursorPosition
        let endPosition = destination

        let deltaX = endPosition.x - startPosition.x
        let deltaY = endPosition.y - startPosition.y
        let distance = hypot(deltaX, deltaY)

        // Flight duration scales with distance: short hops are quick, long
        // flights are more dramatic. Clamped to 0.6s–1.4s.
        let flightDurationSeconds = min(max(distance / 800.0, 0.6), 1.4)
        let frameInterval: Double = 1.0 / 60.0
        let totalFrames = Int(flightDurationSeconds / frameInterval)
        var currentFrame = 0

        // Control point for the quadratic bezier arc. Offset the midpoint
        // upward (negative Y in SwiftUI) so the buddy flies in a parabolic arc.
        let midPoint = CGPoint(
            x: (startPosition.x + endPosition.x) / 2.0,
            y: (startPosition.y + endPosition.y) / 2.0
        )
        let arcHeight = min(distance * 0.2, 80.0)
        let controlPoint = CGPoint(x: midPoint.x, y: midPoint.y - arcHeight)

        navigationAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            currentFrame += 1

            if currentFrame > totalFrames {
                self.navigationAnimationTimer?.invalidate()
                self.navigationAnimationTimer = nil
                self.cursorPosition = endPosition
                self.buddyFlightScale = 1.0
                onComplete()
                return
            }

            // Linear progress 0→1 over the flight duration
            let linearProgress = Double(currentFrame) / Double(totalFrames)

            // Smoothstep easeInOut: 3t² - 2t³ (Hermite interpolation)
            let t = linearProgress * linearProgress * (3.0 - 2.0 * linearProgress)

            // Quadratic bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
            let oneMinusT = 1.0 - t
            let bezierX = oneMinusT * oneMinusT * startPosition.x
                        + 2.0 * oneMinusT * t * controlPoint.x
                        + t * t * endPosition.x
            let bezierY = oneMinusT * oneMinusT * startPosition.y
                        + 2.0 * oneMinusT * t * controlPoint.y
                        + t * t * endPosition.y

            self.cursorPosition = CGPoint(x: bezierX, y: bezierY)

            // Rotation: face the direction of travel by computing the tangent
            // to the bezier curve. B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
            let tangentX = 2.0 * oneMinusT * (controlPoint.x - startPosition.x)
                         + 2.0 * t * (endPosition.x - controlPoint.x)
            let tangentY = 2.0 * oneMinusT * (controlPoint.y - startPosition.y)
                         + 2.0 * t * (endPosition.y - controlPoint.y)
            // +90° offset because the triangle's "tip" points up at 0° rotation,
            // and atan2 returns 0° for rightward movement
            self.triangleRotationDegrees = atan2(tangentY, tangentX) * (180.0 / .pi) + 90.0

            // Scale pulse: sin curve peaks at midpoint of the flight.
            // Buddy grows to ~1.3x at the apex, then shrinks back to 1.0x on landing.
            let scalePulse = sin(linearProgress * .pi)
            self.buddyFlightScale = 1.0 + scalePulse * 0.3
        }
    }

    /// Transitions to pointing mode — shows a speech bubble with a bouncy
    /// scale-in entrance and variable-speed character streaming.
    private func startPointingAtElement() {
        buddyNavigationMode = .pointingAtTarget

        // Rotate back to default pointer angle now that we've arrived
        triangleRotationDegrees = -35.0

        // Reset navigation bubble state — start small for the scale-bounce entrance
        navigationBubbleText = ""
        navigationBubbleOpacity = 1.0
        navigationBubbleSize = .zero
        navigationBubbleScale = 0.5

        // Use custom bubble text from the companion manager (e.g. onboarding demo)
        // if available, otherwise fall back to a random pointer phrase
        let pointerPhrase = companionManager.detectedElementBubbleText
            ?? navigationPointerPhrases.randomElement()
            ?? "right here!"

        streamNavigationBubbleCharacter(phrase: pointerPhrase, characterIndex: 0) {
            // All characters streamed — hold for 3 seconds, then fly back
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard self.buddyNavigationMode == .pointingAtTarget else { return }
                self.navigationBubbleOpacity = 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard self.buddyNavigationMode == .pointingAtTarget else { return }
                    self.startFlyingBackToCursor()
                }
            }
        }
    }

    /// Streams the navigation bubble text one character at a time with variable
    /// delays (30–60ms) for a natural "speaking" rhythm.
    private func streamNavigationBubbleCharacter(
        phrase: String,
        characterIndex: Int,
        onComplete: @escaping () -> Void
    ) {
        guard buddyNavigationMode == .pointingAtTarget else { return }
        guard characterIndex < phrase.count else {
            onComplete()
            return
        }

        let charIndex = phrase.index(phrase.startIndex, offsetBy: characterIndex)
        navigationBubbleText.append(phrase[charIndex])

        // On the first character, trigger the scale-bounce entrance
        if characterIndex == 0 {
            navigationBubbleScale = 1.0
        }

        let characterDelay = Double.random(in: 0.03...0.06)
        DispatchQueue.main.asyncAfter(deadline: .now() + characterDelay) {
            self.streamNavigationBubbleCharacter(
                phrase: phrase,
                characterIndex: characterIndex + 1,
                onComplete: onComplete
            )
        }
    }

    /// Flies the buddy back to the current cursor position after pointing is done.
    private func startFlyingBackToCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let cursorInSwiftUI = convertScreenPointToSwiftUICoordinates(mouseLocation)
        let cursorWithTrackingOffset = CGPoint(x: cursorInSwiftUI.x + 35, y: cursorInSwiftUI.y + 25)

        cursorPositionWhenNavigationStarted = cursorInSwiftUI

        buddyNavigationMode = .navigatingToTarget
        isReturningToCursor = true

        animateBezierFlightArc(to: cursorWithTrackingOffset) {
            self.finishNavigationAndResumeFollowing()
        }
    }

    /// Cancels an in-progress navigation because the user moved the cursor.
    private func cancelNavigationAndResumeFollowing() {
        navigationAnimationTimer?.invalidate()
        navigationAnimationTimer = nil
        navigationBubbleText = ""
        navigationBubbleOpacity = 0.0
        navigationBubbleScale = 1.0
        buddyFlightScale = 1.0
        finishNavigationAndResumeFollowing()
    }

    /// Returns the buddy to normal cursor-following mode after navigation completes.
    private func finishNavigationAndResumeFollowing() {
        navigationAnimationTimer?.invalidate()
        navigationAnimationTimer = nil
        buddyNavigationMode = .followingCursor
        isReturningToCursor = false
        // Releasing the gravity anchor triggers the edge-glow's pull
        // strength to fade back to 0 (animated inside EdgeGlowView).
        navigationTargetPosition = nil
        triangleRotationDegrees = -35.0
        buddyFlightScale = 1.0
        navigationBubbleText = ""
        navigationBubbleOpacity = 0.0
        navigationBubbleScale = 1.0
        companionManager.clearDetectedElementLocation()
    }

    // MARK: - Welcome Animation

    private func startWelcomeAnimation() {
        withAnimation(.easeIn(duration: 0.4)) {
            self.bubbleOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < self.fullWelcomeMessage.count else {
                timer.invalidate()
                // Hold the text for 2 seconds, then fade it out
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.showWelcome = false
                    // Start the onboarding video right after the welcome text disappears
                    self.companionManager.setupOnboardingVideo()
                }
                return
            }

            let index = self.fullWelcomeMessage.index(self.fullWelcomeMessage.startIndex, offsetBy: currentIndex)
            self.welcomeText.append(self.fullWelcomeMessage[index])
            currentIndex += 1
        }
    }
}

// MARK: - Blue Cursor Waveform

/// A small blue waveform that replaces the triangle cursor while
/// the user is holding the push-to-talk shortcut and speaking.
private struct BlueCursorWaveformView: View {
    let audioPowerLevel: CGFloat

    private let barCount = 5
    private let listeningBarProfile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { timelineContext in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { barIndex in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(DS.Colors.overlayCursorBlue)
                        .frame(
                            width: 2,
                            height: barHeight(
                                for: barIndex,
                                timelineDate: timelineContext.date
                            )
                        )
                }
            }
            .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.6), radius: 6, x: 0, y: 0)
            .animation(.linear(duration: 0.08), value: audioPowerLevel)
        }
    }

    private func barHeight(for barIndex: Int, timelineDate: Date) -> CGFloat {
        let animationPhase = CGFloat(timelineDate.timeIntervalSinceReferenceDate * 3.6) + CGFloat(barIndex) * 0.35
        let normalizedAudioPowerLevel = max(audioPowerLevel - 0.008, 0)
        let easedAudioPowerLevel = pow(min(normalizedAudioPowerLevel * 2.85, 1), 0.76)
        let reactiveHeight = easedAudioPowerLevel * 10 * listeningBarProfile[barIndex]
        let idlePulse = (sin(animationPhase) + 1) / 2 * 1.5
        return 3 + reactiveHeight + idlePulse
    }
}

// MARK: - Blue Cursor Spinner

/// A small blue spinning indicator that replaces the triangle cursor
/// while the AI is processing a voice input.
private struct BlueCursorSpinnerView: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(
                AngularGradient(
                    colors: [
                        DS.Colors.overlayCursorBlue.opacity(0.0),
                        DS.Colors.overlayCursorBlue
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.6), radius: 6, x: 0, y: 0)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}

// MARK: - Edge Glow

/// Identifies the conversational beat the edge glow is currently
/// rendering for. Each mode has a distinct visual treatment so the
/// user can tell — without looking at the cursor or the panel — which
/// half of the conversation Sticky is in.
/// Which edge(s) of the screen the glow anchors to. Mode picks the
/// anchor (see `EdgeGlowMode.defaultAnchor`) so the user reads the
/// direction of the glow as the direction of conversation: glow up from
/// the bottom while *they* speak, glow down from the top while *Sticky*
/// speaks back, glow as a full-screen halo while a teach session is
/// recording the desktop.
enum EdgeGlowAnchor {
    case bottom
    case top
    /// All four edges. Used during teach-mode recording to communicate
    /// "the whole environment is being observed" — reads as a halo ring
    /// around the desktop rather than a single directional glow.
    case all

    var includesBottom: Bool { self == .bottom || self == .all }
    var includesTop: Bool { self == .top || self == .all }
    var includesLeading: Bool { self == .all }
    var includesTrailing: Bool { self == .all }
}

enum EdgeGlowMode {
    /// User is holding push-to-talk and speaking. Mic-driven, anchored
    /// to the bottom edge in their voice color (blue by default).
    case listeningToUser
    /// Transcript finalized; waiting for Claude (and the first TTS
    /// chunk) to come back. Same anchor + color as listening so the
    /// transition is visually continuous, but a horizontal shimmer
    /// sweep + slow synthetic breathing replace the mic-reactivity so
    /// the user can tell at a glance that we're now waiting on the
    /// model rather than listening.
    case processingThinking
    /// AI is speaking the response back. TTS-driven, anchored to the
    /// top edge in Sticky's voice color so it reads as "Sticky talking
    /// down at me" — conversational, the opposite direction of the
    /// user's own bottom glow.
    case respondingWithAI
    /// Reverse Clicky teach session is recording. All four edges glow
    /// in the user's voice color (mic-reactive) — a halo ring around
    /// the desktop. The full-screen surround is the indicator that this
    /// is a different mode from a normal Ask interaction.
    case teachRecording

    /// Each mode has a single natural anchor. Centralizing the mapping
    /// here means call sites only choose a mode — they don't also have
    /// to remember which edges that mode glows on.
    var defaultAnchor: EdgeGlowAnchor {
        switch self {
        case .listeningToUser, .processingThinking: return .bottom
        case .respondingWithAI: return .top
        case .teachRecording: return .all
        }
    }

    /// Only `.processingThinking` shows the moving highlight sweep.
    /// Listening / responding / teach are all driven by real audio so
    /// they're inherently animated; processing has nothing to react to,
    /// which is exactly when we need an extra animation to feel alive.
    var usesShimmerSweep: Bool {
        self == .processingThinking
    }

    /// `.processingThinking` ignores the input audio level (which is 0
    /// during the wait) and breathes on a slow synthetic pulse instead.
    /// Every other mode is driven by real audio.
    var usesSyntheticBreathing: Bool {
        self == .processingThinking
    }
}

/// A single layered "halo" of soft inner-shadow-style glow that emanates
/// from one edge of the screen and fades inward. Built as a stack of
/// gradient bands at increasing blur radii, masked at a soft corner
/// radius so the corners curve gracefully and the glow never looks like
/// a hard rectangle. Audio reactivity scales the overall intensity so
/// the halo pulses with the user's voice or the AI's TTS.
private struct InnerShadowEdgeHalo: View {
    /// Which edge of the screen the halo emanates from. The four cases
    /// (`.bottom`, `.top`, `.leading`, `.trailing`) each rotate the
    /// gradient and frame alignment so the brightest band sits flush
    /// against the matching screen edge.
    let edge: Edge
    /// Saturated color of the glow's outer halo. Bright color near the
    /// edge fades to fully transparent toward the center of the screen.
    let color: Color
    /// 0...1 reactivity scalar. Drives both the brightness of every
    /// layer and the height/spread of the saturated band, so silence
    /// reads as a calm dim glow and shouting reads as a tall vivid one.
    let intensity: CGFloat
    /// Soft mask radius applied to the entire halo. The reference uses
    /// a small ~24pt radius so the corners feel gently rounded but the
    /// glow is still flush against three of the four screen edges.
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Layer 1 — broad outer halo. Largest blur, biggest spread,
            // lowest opacity. Establishes the "atmospheric" reach of
            // the glow into the center of the screen.
            haloBand(
                colorOpacity: 0.42,
                bandHeight: 280,
                blurRadius: 42
            )
            // Layer 2 — mid bloom. Medium blur, more saturated. This
            // is the band the eye reads as "the color" of the glow.
            haloBand(
                colorOpacity: 0.72,
                bandHeight: 170,
                blurRadius: 28
            )
            // Layer 3 — saturated core. Tight blur, near-full opacity,
            // sitting close to the screen edge. Gives the glow its
            // visual weight.
            haloBand(
                colorOpacity: 0.92,
                bandHeight: 80,
                blurRadius: 16
            )
            // Layer 4 — white inner highlight. Sits hottest at the
            // very edge so the band has a luminous rim, like the
            // reference's "Inner Shadow 3" white pass at Plus Lighter.
            haloBand(
                colorOpacity: 0.55,
                bandHeight: 28,
                blurRadius: 8,
                colorOverride: .white,
                blendMode: .plusLighter
            )
        }
        // Scale the entire halo's brightness with audio reactivity. We
        // multiply opacity (rather than the per-band opacity scalars)
        // so the four-layer relationship stays consistent across
        // intensities — every band gets brighter together.
        .opacity(Double(intensity))
        // Round the corners so the glow doesn't look like a hard
        // rectangle pasted onto the screen. Mac screens are nearly
        // square at the corners so this is a deliberate softening, not
        // a literal match.
        .mask {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        }
        .allowsHitTesting(false)
    }

    /// Renders a single gradient band along the chosen edge, sized to
    /// the requested height and blurred. Stacking several of these with
    /// different opacities and blur radii creates the layered
    /// inner-shadow look from the reference.
    @ViewBuilder
    private func haloBand(
        colorOpacity: Double,
        bandHeight: CGFloat,
        blurRadius: CGFloat,
        colorOverride: Color? = nil,
        blendMode: BlendMode = .normal
    ) -> some View {
        let bandColor = colorOverride ?? color
        // The band is a linear gradient running from transparent (deep
        // inside the screen) to fully colored (right at the edge), so
        // the glow appears to emanate from the edge inward.
        let gradient = LinearGradient(
            stops: [
                .init(color: bandColor.opacity(0), location: 0),
                .init(color: bandColor.opacity(colorOpacity * 0.55), location: 0.45),
                .init(color: bandColor.opacity(colorOpacity), location: 1)
            ],
            startPoint: gradientStartPoint,
            endPoint: gradientEndPoint
        )

        gradient
            // Frame the band so its long axis runs along the chosen
            // edge and its short axis (the height for top/bottom, the
            // width for leading/trailing) controls how far the glow
            // reaches into the screen.
            .frame(
                maxWidth: edgeIsHorizontal ? .infinity : bandHeight,
                maxHeight: edgeIsHorizontal ? bandHeight : .infinity,
                alignment: edgeAlignment
            )
            // Frame again at the parent size so we can position the
            // band flush against the chosen edge regardless of where
            // it would otherwise lay out.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment)
            .blur(radius: blurRadius)
            .blendMode(blendMode)
    }

    /// Whether the chosen edge runs horizontally (`.bottom` or `.top`).
    /// Used to flip the band's frame so the long axis stays aligned to
    /// the edge.
    private var edgeIsHorizontal: Bool {
        edge == .bottom || edge == .top
    }

    /// Frame alignment that pins the band against the chosen edge.
    private var edgeAlignment: Alignment {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    /// Gradient start point. The "transparent" stop sits at the inner
    /// side of the band (away from the edge); the "saturated" stop
    /// sits flush against the edge.
    private var gradientStartPoint: UnitPoint {
        switch edge {
        case .bottom: return .top       // transparent at top, saturated at bottom
        case .top: return .bottom
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }

    private var gradientEndPoint: UnitPoint {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

/// A horizontally-traveling highlight that sweeps across the bottom
/// edge of the screen during the `.processingThinking` mode. Gives the
/// otherwise-static "we're waiting on Claude" state a visible rhythm
/// so the user can tell something is happening — without us pretending
/// to react to audio that isn't there.
private struct ProcessingShimmerSweep: View {
    /// Color of the shimmer band — same hue as the bottom edge halo so
    /// it reads as part of the same glow rather than a separate effect.
    let color: Color
    /// 0...1 visibility multiplier. Animated up to 1 when entering
    /// processing mode and back to 0 when leaving, so the shimmer
    /// fades in/out rather than snapping.
    let visibility: CGFloat
    /// Seconds the shimmer takes to traverse the screen once. 2.4s is
    /// slow enough that the eye reads the sweep clearly, fast enough
    /// to feel "alive" rather than sluggish during the wait.
    private let cycleSeconds: Double = 2.4
    /// Width of the moving highlight as a fraction of the screen width.
    /// 0.45 lands on a noticeable-but-not-overwhelming band.
    private let bandWidthFraction: CGFloat = 0.45

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsedSeconds = timeline.date.timeIntervalSinceReferenceDate
            // Phase advances 0 → 1 over `cycleSeconds`, then wraps. Eased
            // with a sine so the sweep slows at the edges and is
            // fastest in the middle — feels more like a breath than a
            // metronome tick.
            let rawPhase = (elapsedSeconds.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds
            let easedPhase = (1 - cos(rawPhase * .pi)) / 2

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let bandWidth = width * bandWidthFraction
                // Travel range goes from -bandWidth (band fully off
                // the leading edge) to width + bandWidth (band fully
                // off the trailing edge), so the sweep enters and
                // exits the screen smoothly rather than popping.
                let bandXOffset = -bandWidth + (width + 2 * bandWidth) * CGFloat(easedPhase)

                LinearGradient(
                    stops: [
                        .init(color: color.opacity(0), location: 0),
                        .init(color: color.opacity(0.55), location: 0.5),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth, height: 220)
                .blur(radius: 38)
                // Sit the band flush against the bottom edge with its
                // top fading inward. `position` places its center, so
                // we offset by bandWidth/2 horizontally and put the
                // band's vertical center 60pt above the bottom edge so
                // the brightest part of the blur lands on the edge.
                .position(x: bandXOffset + bandWidth / 2, y: height - 60)
                .blendMode(.plusLighter)
            }
        }
        .opacity(Double(visibility))
        .allowsHitTesting(false)
    }
}

/// Screen-edge glow that comes alive during any active voice interaction
/// — the user holding push-to-talk, Sticky talking back, or a Reverse
/// Clicky teach session recording. Built as four `InnerShadowEdgeHalo`
/// instances (one per edge) whose individual opacities are driven by the
/// current mode's `defaultAnchor`. Crossfades between anchors when the
/// mode changes (e.g. listening's bottom glow handing off to responding's
/// top glow) by animating those per-edge opacities rather than swapping
/// the view tree, so the bottom-to-top transition looks like a smooth
/// reorientation of light rather than a hard cut.
///
/// Audio reactivity (mic level during listening / teach, TTS level
/// during responding) scales the halo's intensity in real time. When
/// silent, a slow synthetic breathing pulse keeps the glow visibly
/// alive at low brightness. During processing, a horizontal shimmer
/// sweep fades in to communicate "we're waiting on Claude" without
/// pretending to react to non-existent audio.
private struct EdgeGlowView: View {
    /// Live audio power level in 0...1. Mic during listening / teach,
    /// TTS playback level during responding, 0 during processing.
    let audioPowerLevel: CGFloat
    /// Mode determines the anchor (which edges glow), the color usage
    /// (handled by the caller via `color`), the audio source (handled
    /// by the caller via `audioPowerLevel`), and whether the synthetic
    /// breathing + shimmer sweep are active.
    let mode: EdgeGlowMode
    /// The hue of the glow. The caller picks user vs Sticky color
    /// based on whose turn it is in the conversation, so this view
    /// doesn't need to know about the voice picker or the user's blue.
    let color: Color

    /// Per-edge opacity drivers. All four halos are mounted at all
    /// times; switching modes animates these between 0 and 1 (or 0 and
    /// `teachEdgeOpacity` for the four-edge halo ring) to crossfade
    /// the glow from one anchor to another. Mounting them statically
    /// is cheaper than tearing the tree on every state change and
    /// gives us a built-in crossfade for free.
    @State private var bottomEdgeOpacity: Double
    @State private var topEdgeOpacity: Double
    @State private var leadingEdgeOpacity: Double
    @State private var trailingEdgeOpacity: Double

    /// 0...1 visibility of the processing shimmer sweep. Animated up
    /// when entering `.processingThinking` and back down when leaving
    /// so the sweep fades cleanly rather than appearing/disappearing.
    @State private var shimmerVisibility: Double

    /// 0 = drive the halo from real audio. 1 = drive from the synthetic
    /// breathing pulse used during `.processingThinking`. Crossfaded
    /// rather than hard-switched so transitions in/out of processing
    /// don't look like the glow snaps to a different rhythm.
    @State private var syntheticBreathingInfluence: Double

    /// Per-edge opacity used when all four edges are active (teach
    /// mode). Dimmed below 1.0 so the four overlapping halos read as a
    /// halo ring around the desktop rather than a heavy frame.
    private static let teachEdgeOpacity: Double = 0.62

    /// Soft corner radius applied to every halo's mask. ~24pt is large
    /// enough to feel gently rounded but small enough that three edges
    /// still feel visually flush with the screen.
    private static let cornerRadius: CGFloat = 24

    /// Slow synthetic pulse period used during processing. Also drives
    /// the silent-but-alive baseline breathing during listening / teach.
    /// 3.5s is slower than a heartbeat — settled, contemplative.
    private static let breathingPeriodSeconds: Double = 3.5
    /// Faster pulse period used specifically during processing so it
    /// feels like a wait, not just a calm idle.
    private static let processingPulsePeriodSeconds: Double = 2.4

    init(audioPowerLevel: CGFloat, mode: EdgeGlowMode, color: Color) {
        self.audioPowerLevel = audioPowerLevel
        self.mode = mode
        self.color = color
        let anchor = mode.defaultAnchor
        let activeOpacity: Double = (anchor == .all) ? Self.teachEdgeOpacity : 1.0
        _bottomEdgeOpacity = State(initialValue: anchor.includesBottom ? activeOpacity : 0)
        _topEdgeOpacity = State(initialValue: anchor.includesTop ? activeOpacity : 0)
        _leadingEdgeOpacity = State(initialValue: anchor.includesLeading ? activeOpacity : 0)
        _trailingEdgeOpacity = State(initialValue: anchor.includesTrailing ? activeOpacity : 0)
        _shimmerVisibility = State(initialValue: mode.usesShimmerSweep ? 1.0 : 0.0)
        _syntheticBreathingInfluence = State(initialValue: mode.usesSyntheticBreathing ? 1.0 : 0.0)
    }

    var body: some View {
        // TimelineView keeps the breathing and shimmer animations
        // ticking independently of audio so the glow feels alive even
        // in silence.
        TimelineView(.animation) { timeline in
            let elapsedSeconds = timeline.date.timeIntervalSinceReferenceDate

            // Real audio reactivity, eased so soft sounds register and
            // peaks plateau cleanly.
            let easedAudio = audioReactivityEased

            // Slow synthetic breathing — used both as the
            // silent-but-alive baseline (when audio is near zero) and
            // as the primary driver during processing.
            let processingBreath = (sin(elapsedSeconds * 2 * .pi / Self.processingPulsePeriodSeconds) + 1) / 2  // 0...1
            let idleBreath = (sin(elapsedSeconds * 2 * .pi / Self.breathingPeriodSeconds) + 1) / 2  // 0...1

            // Audio-driven intensity: a moving baseline so the halo
            // is always visible, plus a reactive boost on top.
            let baselineIntensity: CGFloat = 0.28 + 0.06 * CGFloat(idleBreath)
            let audioIntensity = baselineIntensity + (1 - baselineIntensity) * easedAudio

            // Processing intensity: ignore audio entirely, breathe on
            // a calmer 0.32 → 0.78 swing so the glow feels like a
            // patient wait.
            let processingIntensity: CGFloat = 0.32 + 0.46 * CGFloat(processingBreath)

            // Crossfade between the two regimes. The animated influence
            // value goes 0 → 1 over 600ms when entering processing and
            // back the other way when leaving, so the rhythm changes
            // smoothly rather than snapping.
            let intensity = audioIntensity * (1 - CGFloat(syntheticBreathingInfluence))
                          + processingIntensity * CGFloat(syntheticBreathingInfluence)

            ZStack {
                InnerShadowEdgeHalo(
                    edge: .bottom,
                    color: color,
                    intensity: intensity,
                    cornerRadius: Self.cornerRadius
                )
                .opacity(bottomEdgeOpacity)

                InnerShadowEdgeHalo(
                    edge: .top,
                    color: color,
                    intensity: intensity,
                    cornerRadius: Self.cornerRadius
                )
                .opacity(topEdgeOpacity)

                InnerShadowEdgeHalo(
                    edge: .leading,
                    color: color,
                    intensity: intensity,
                    cornerRadius: Self.cornerRadius
                )
                .opacity(leadingEdgeOpacity)

                InnerShadowEdgeHalo(
                    edge: .trailing,
                    color: color,
                    intensity: intensity,
                    cornerRadius: Self.cornerRadius
                )
                .opacity(trailingEdgeOpacity)

                // Shimmer sweep is mounted at all times; visibility
                // animates between 0 (every other mode) and 1
                // (processing) so it crossfades rather than appears.
                ProcessingShimmerSweep(
                    color: color,
                    visibility: CGFloat(shimmerVisibility)
                )
            }
            .allowsHitTesting(false)
        }
        // Animate the per-edge opacities, shimmer visibility, and
        // synthetic-breathing influence together when the mode changes.
        // Done in a single `withAnimation` block so the visual handoff
        // (e.g. listening → responding crossfading bottom → top) reads
        // as one coordinated reorientation of light rather than several
        // disjoint property animations.
        .onChange(of: mode) { _, newMode in
            let anchor = newMode.defaultAnchor
            let activeOpacity: Double = (anchor == .all) ? Self.teachEdgeOpacity : 1.0
            withAnimation(.easeInOut(duration: 0.55)) {
                bottomEdgeOpacity = anchor.includesBottom ? activeOpacity : 0
                topEdgeOpacity = anchor.includesTop ? activeOpacity : 0
                leadingEdgeOpacity = anchor.includesLeading ? activeOpacity : 0
                trailingEdgeOpacity = anchor.includesTrailing ? activeOpacity : 0
                shimmerVisibility = newMode.usesShimmerSweep ? 1.0 : 0.0
                syntheticBreathingInfluence = newMode.usesSyntheticBreathing ? 1.0 : 0.0
            }
        }
    }

    /// Eased version of the audio power level. Subtracts a tiny noise
    /// floor so background room hum doesn't drive the glow, then
    /// eases with a sub-1 exponent so soft sounds register strongly
    /// and loud peaks plateau cleanly.
    private var audioReactivityEased: CGFloat {
        let normalized = max(audioPowerLevel - 0.008, 0)
        let eased = pow(min(Double(normalized) * 2.85, 1), 0.76)
        return CGFloat(eased)
    }
}

// MARK: - Mystical Orb

/// Sticky's pointer cursor — a glowing single-color orb with a soft halo
/// that pulses gently. Two render modes:
///
/// 1. **Default** (`personaAvatar` is nil) — solid colored orb body
///    tinted with `bodyColor`. Used for `.me` / `.team` selections.
/// 2. **Persona** (`personaAvatar` is non-nil) — the orb body is replaced
///    with a circular avatar (initials / SF Symbol / image file) so the
///    cursor visually becomes the active teammate. The pulsing halo
///    stays on, tinted with the persona's accent color so the visual
///    identity is consistent with the response bubbles and edge glow.
///
/// The outer 88x88 frame is preserved in both modes so positioning math
/// elsewhere (cursor offset, navigation arcs) doesn't need to change.
private struct MysticalOrbView: View {
    /// Halo / body color of the orb. Tied to Sticky's voice color so the
    /// cursor visually matches the picker orb in the panel and the top-
    /// edge halo when Sticky talks back. When `personaAvatar` is set,
    /// this is used only for the halo (the body becomes the avatar).
    let bodyColor: Color

    /// When non-nil, replaces the solid orb body with a circular avatar
    /// for the active teammate persona. Nil for the default Sticky look.
    let personaAvatar: PersonaAvatar?

    @State private var pulseScale: CGFloat = 1.0

    /// Diameter of the orb body / avatar. Slightly larger when wearing
    /// a persona so a face / initials are legible at a glance — the
    /// solid orb works fine at 28pt but a tiny portrait at 28pt is just
    /// a colored dot.
    private var bodyDiameter: CGFloat {
        return personaAvatar != nil ? 36 : 28
    }

    var body: some View {
        ZStack {
            // Outer halo — broad blurred glow that pulses gently behind
            // the body. Same in both modes so the "this is Sticky" cue
            // (a calm pulsing aura) reads identically whether you're
            // looking at the default orb or a persona's face.
            Circle()
                .fill(bodyColor.opacity(0.55))
                .frame(width: 60, height: 60)
                .blur(radius: 18)
                .scaleEffect(pulseScale)

            // Body — either the default solid orb, or the persona's
            // circular avatar. The persona case still gets the same
            // colored glow shadow so the figure has weight on a busy
            // desktop wallpaper.
            if let personaAvatar {
                PersonaAvatarView(
                    avatar: personaAvatar,
                    diameter: bodyDiameter,
                    showsRing: true,
                    ringColor: Color.white.opacity(0.85),
                    ringLineWidth: 1.5
                )
                .shadow(color: bodyColor.opacity(0.7), radius: 6, x: 0, y: 0)
            } else {
                Circle()
                    .fill(bodyColor)
                    .frame(width: bodyDiameter, height: bodyDiameter)
                    .shadow(color: bodyColor.opacity(0.7), radius: 6, x: 0, y: 0)
            }
        }
        .frame(width: 88, height: 88)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

/// Rounded-rect speech bubble with a small triangular tail on its left edge,
/// used by the navigation pointer bubble so the "over here!" callout reads
/// as if it's coming out of the persona avatar/orb sitting to the bubble's
/// upper-left. The tail is pinned near the top of the left edge — the bubble
/// is positioned at `cursorPosition.x + 10, cursorPosition.y + 18`, which
/// places the orb above-and-to-the-left, so the tail naturally points back
/// at it.
private struct ChatBubbleShape: Shape {
    var cornerRadius: CGFloat = 8
    /// How far down the left edge the tail's center sits, measured from the
    /// top of the bubble. ~12pt keeps the tail aligned with the first line
    /// of text in a small (11pt) speech bubble.
    var tailCenterFromTop: CGFloat = 12
    var tailWidth: CGFloat = 8
    var tailHeight: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let bubbleRect = CGRect(
            x: rect.minX + tailHeight,
            y: rect.minY,
            width: rect.width - tailHeight,
            height: rect.height
        )

        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Triangular tail — points left, attached to the bubble's left edge.
        let tailTop = max(rect.minY + cornerRadius, rect.minY + tailCenterFromTop - tailWidth / 2)
        let tailBottom = min(rect.maxY - cornerRadius, tailTop + tailWidth)
        let tailTipX = rect.minX
        let tailBaseX = bubbleRect.minX + 0.5  // overlap by half a point so the seam disappears

        path.move(to: CGPoint(x: tailBaseX, y: tailTop))
        path.addLine(to: CGPoint(x: tailTipX, y: (tailTop + tailBottom) / 2))
        path.addLine(to: CGPoint(x: tailBaseX, y: tailBottom))
        path.closeSubpath()

        return path
    }
}

// Manager for overlay windows — creates one per screen so the cursor
// buddy seamlessly follows the cursor across multiple monitors.
@MainActor
class OverlayWindowManager {
    private var overlayWindows: [OverlayWindow] = []
    var hasShownOverlayBefore = false

    func showOverlay(onScreens screens: [NSScreen], companionManager: CompanionManager) {
        // Hide any existing overlays
        hideOverlay()

        // Track if this is the first time showing overlay (welcome message)
        let isFirstAppearance = !hasShownOverlayBefore
        hasShownOverlayBefore = true

        // Create one overlay window per screen
        for screen in screens {
            let window = OverlayWindow(screen: screen)

            let contentView = BlueCursorView(
                screenFrame: screen.frame,
                isFirstAppearance: isFirstAppearance,
                companionManager: companionManager
            )

            let hostingView = NSHostingView(rootView: contentView)
            hostingView.frame = screen.frame
            window.contentView = hostingView

            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
    }

    func hideOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
    }

    /// Fades out overlay windows over `duration` seconds, then removes them.
    func fadeOutAndHideOverlay(duration: TimeInterval = 0.4) {
        let windowsToFade = overlayWindows
        overlayWindows.removeAll()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in windowsToFade {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            for window in windowsToFade {
                window.orderOut(nil)
                window.contentView = nil
            }
        })
    }

    func isShowingOverlay() -> Bool {
        return !overlayWindows.isEmpty
    }
}

// MARK: - Onboarding Video Player

/// NSViewRepresentable wrapping an AVPlayerLayer so HLS video plays
/// inside SwiftUI. Uses a custom NSView subclass to keep the player
/// layer sized to the view's bounds automatically.
private struct OnboardingVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerNSView {
        let view = AVPlayerNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerNSView, context: Context) {
        nsView.player = player
    }
}

private class AVPlayerNSView: NSView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    private let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
