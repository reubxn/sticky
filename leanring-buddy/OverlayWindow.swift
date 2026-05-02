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

// Right-tilted parallelogram shape — Clicky's logo. Used as the cursor
// pointer body in the overlay, and the same geometry is rendered via
// NSBezierPath in MenuBarPanelManager so the menu bar icon matches.
// "Tilted right" = top edge shifted right of the bottom edge, so the
// parallel diagonal sides lean like the italic slash `∕`.
struct Parallelogram: Shape {
    /// Horizontal skew of the top edge relative to the bottom, expressed
    /// as a fraction of the rect's width. 0 = rectangle, 0.35 = clear lean.
    var skewFraction: CGFloat = 0.35

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let skew = rect.width * skewFraction
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))            // bottom-left
        path.addLine(to: CGPoint(x: rect.minX + skew, y: rect.minY))  // top-left (shifted right)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))         // top-right
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))  // bottom-right
        path.closeSubpath()
        return path
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

    private let fullWelcomeMessage = "hey! i'm clicky"

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
    /// follows the cursor: it appears only when Clicky is "showing the
    /// user something" — i.e. flying to or pointing at a detected element.
    /// Idle, listening, and processing all show nothing on this screen
    /// except (during listening) the audio-reactive edge glow.
    private var orbShouldBeVisible: Bool {
        guard buddyIsVisibleOnThisScreen else { return false }
        return buddyNavigationMode == .navigatingToTarget
            || buddyNavigationMode == .pointingAtTarget
    }

    /// True when the screen-edge glow should be on this screen. Visible
    /// across the entire active arc of an interaction — listening (user
    /// speaking), processing (waiting for the AI), and responding (AI
    /// speaking back) — so the user always has a luminous indication
    /// that Clicky is engaged. Also visible while a Reverse Clicky teach
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

    /// Maps the current voice state to the visual mode the EdgeGlowView
    /// should render in. Each mode has its own palette + motion
    /// parameters so the user, the loading wait, and the AI's reply are
    /// distinguishable at a glance. Teach-session recording reuses the
    /// listening palette for now — the dedicated amber/full-edge halo
    /// per the plan is a follow-up.
    private var edgeGlowMode: EdgeGlowMode {
        if companionManager.teachSessionState == .recording {
            return .listeningToUser
        }
        switch companionManager.voiceState {
        case .listening: return .listeningToUser
        case .processing: return .processingThinking
        case .responding: return .respondingWithAI
        case .idle: return .listeningToUser  // unused — view is hidden
        }
    }

    /// Picks which audio source drives the aurora's reactivity for the
    /// current voice state. During `.listening` we use the live mic
    /// level; during `.responding` we use the TTS playback level;
    /// during `.processing` we feed 0 because the EdgeGlowView
    /// synthesizes its own pulsing rhythm in that mode. Teach-session
    /// recording uses the same mic level as listening — the user is
    /// narrating, so the glow should react to their voice.
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

    /// The point the aurora's gravity should pull toward, in this
    /// screen's SwiftUI coordinates. Non-nil during navigate/point so
    /// the curtains visibly bend toward the element Clicky is
    /// indicating; nil when the buddy is just following the cursor so
    /// the aurora hangs at the edges as usual.
    private var edgeGlowPullTarget: CGPoint? {
        switch buddyNavigationMode {
        case .navigatingToTarget, .pointingAtTarget:
            return navigationTargetPosition
        case .followingCursor:
            return nil
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
                pullTarget: edgeGlowPullTarget
            )
                .opacity(edgeGlowShouldBeVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: companionManager.voiceState)
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
                            .fill(DS.Colors.overlayCursorBlue)
                            .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.5), radius: 6, x: 0, y: 0)
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
                            .fill(DS.Colors.overlayCursorBlue)
                            .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.5), radius: 6, x: 0, y: 0)
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Colors.overlayCursorBlue)
                            .shadow(
                                color: DS.Colors.overlayCursorBlue.opacity(0.5 + (1.0 - navigationBubbleScale) * 1.0),
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

            // Mystical orb — only visible when Clicky is "showing the user
            // something" (flying to a target or pointing at one). It does
            // NOT follow the cursor. During the bezier flight, position is
            // driven frame-by-frame by the navigation timer; we suppress
            // the implicit animation so the arc stays smooth.
            // The orb is symmetric so triangleRotationDegrees no longer
            // drives a visible rotation; the directional cue during flight
            // comes from buddyFlightScale (grows mid-arc, shrinks on landing).
            MysticalOrbView()
                .shadow(color: DS.Colors.overlayCursorBlue.opacity(0.6), radius: 8 + (buddyFlightScale - 1.0) * 20, x: 0, y: 0)
                .scaleEffect(buddyFlightScale)
                .opacity(orbShouldBeVisible ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.easeInOut(duration: 0.4), value: orbShouldBeVisible)

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
/// half of the conversation Clicky is in.
enum EdgeGlowMode {
    /// User is holding push-to-talk and speaking. Mic-driven aurora,
    /// full-saturation cool palette, fast motion. The "you're being
    /// heard" state.
    case listeningToUser
    /// Transcript finalized; waiting for Claude (and the first TTS
    /// chunk) to come back. No real audio source — instead the aurora
    /// breathes on a slow synthetic pulse so it's clearly distinct
    /// from both speaking states.
    case processingThinking
    /// AI is speaking the response back. TTS-driven, but visibly
    /// different from `.listeningToUser`: warmer palette skew (more
    /// magenta/pink, less green), slightly slower phase speeds, so the
    /// user reads the glow as "the AI talking" rather than mirroring
    /// their own voice.
    case respondingWithAI
}

/// Per-mode visual configuration that the EdgeGlowView applies on top
/// of the per-layer baseline parameters. Lets `.listeningToUser`,
/// `.processingThinking`, and `.respondingWithAI` share the same
/// ribbon stack while looking and behaving distinctly.
private struct EdgeGlowModeStyle {
    /// When true, the EdgeGlowView ignores the input `audioPowerLevel`
    /// and synthesizes its own slow sine pulse instead. Used by
    /// `.processingThinking` to telegraph "AI is thinking" without
    /// needing real audio.
    let usesSyntheticPulse: Bool
    /// Period of the synthetic pulse in seconds. Only relevant when
    /// `usesSyntheticPulse` is true.
    let pulsePeriodSeconds: Double
    /// Multiplied into every layer's `primaryPhaseSpeed` and
    /// `secondaryPhaseSpeed`. < 1.0 = calmer / more considered motion.
    let phaseSpeedMultiplier: Double
    /// Multiplied into every layer's `waveAmplitude`. Lets a mode dial
    /// the entire stack's expressiveness up or down without changing
    /// each layer's individual character.
    let amplitudeMultiplier: CGFloat
    /// Per-color opacity scalars (1.0 = baseline, 0.0 = layer hidden).
    /// Lets each mode tune the color balance — e.g. boost magenta/pink
    /// for `.respondingWithAI`, drop them for `.processingThinking`.
    let indigoOpacityScale: Double
    let blueOpacityScale: Double
    let cyanOpacityScale: Double
    let greenOpacityScale: Double
    let magentaOpacityScale: Double
    let whiteOpacityScale: Double
    let pinkOpacityScale: Double

    static func style(for mode: EdgeGlowMode) -> EdgeGlowModeStyle {
        switch mode {
        case .listeningToUser:
            // Baseline behavior: every layer at 1.0, mic-driven.
            return EdgeGlowModeStyle(
                usesSyntheticPulse: false,
                pulsePeriodSeconds: 0,
                phaseSpeedMultiplier: 1.0,
                amplitudeMultiplier: 1.0,
                indigoOpacityScale: 1.0,
                blueOpacityScale: 1.0,
                cyanOpacityScale: 1.0,
                greenOpacityScale: 1.0,
                magentaOpacityScale: 1.0,
                whiteOpacityScale: 1.0,
                pinkOpacityScale: 1.0
            )
        case .processingThinking:
            // Cooler, calmer "thinking" feel. Magenta and pink mostly
            // off so the palette reads cool/blue/cyan; phase speed
            // slowed; a 2.4s synthetic pulse drives the swell so the
            // aurora visibly breathes while waiting.
            return EdgeGlowModeStyle(
                usesSyntheticPulse: true,
                pulsePeriodSeconds: 2.4,
                phaseSpeedMultiplier: 0.55,
                amplitudeMultiplier: 0.85,
                indigoOpacityScale: 1.0,
                blueOpacityScale: 1.0,
                cyanOpacityScale: 0.95,
                greenOpacityScale: 0.55,
                magentaOpacityScale: 0.20,
                whiteOpacityScale: 0.85,
                pinkOpacityScale: 0.25
            )
        case .respondingWithAI:
            // Warmer skew so it reads as the AI's voice rather than
            // the user's. Slightly slower phase speed so the AI feels
            // measured next to the user's energetic input.
            return EdgeGlowModeStyle(
                usesSyntheticPulse: false,
                pulsePeriodSeconds: 0,
                phaseSpeedMultiplier: 0.78,
                amplitudeMultiplier: 1.0,
                indigoOpacityScale: 1.0,
                blueOpacityScale: 0.85,
                cyanOpacityScale: 0.70,
                greenOpacityScale: 0.45,
                magentaOpacityScale: 1.55,
                whiteOpacityScale: 1.0,
                pinkOpacityScale: 1.55
            )
        }
    }
}

/// An aurora-like glow anchored to the bottom edge of the screen during
/// any active voice interaction. Built as a stack of bottom-anchored
/// "ribbons" — each ribbon is a band of color whose top edge undulates
/// like an aurora curtain (sum of two sine waves at different
/// frequencies, both phase-shifted continuously over time). The ribbons
/// drift laterally at different speeds and use cool aurora colors
/// (indigo → blue → cyan → green → magenta → white highlight), with
/// most layers using `.plusLighter` for the luminous additive feel of
/// real auroras. The center stays fully transparent so the user's work
/// is never occluded.
///
/// The `mode` parameter selects an `EdgeGlowModeStyle` that applies
/// global motion + per-color opacity scalars on top of each layer's
/// baseline configuration, so the same ribbon stack visibly distinguishes
/// listening (mic-driven, cool palette), processing (synthetic
/// breathing pulse, cooler/dimmer), and responding (TTS-driven, warmer
/// pink/magenta skew, slightly slower).
private struct EdgeGlowView: View {
    let audioPowerLevel: CGFloat
    let mode: EdgeGlowMode
    /// Screen-local point the aurora should warp toward, in this
    /// overlay's SwiftUI coordinates. When non-nil, every ribbon's top
    /// edge curves up toward this point with a Gaussian falloff in x —
    /// reading visually as the target exerting "gravity" on the four
    /// edge stacks. Nil = no pull, ribbons hang at the edges normally.
    let pullTarget: CGPoint?

    // Each mode-derived value is stored as its own @State so SwiftUI
    // can interpolate them independently when the mode changes. Without
    // this, switching from `.listening` → `.processingThinking`
    // (or any other transition) snaps every multiplier and opacity
    // scalar to the new mode's value in a single frame, which is what
    // produces the "jagged" feel during state changes. With these
    // animated, the entire stack glides between modes over ~600ms.
    @State private var amplitudeMultiplier: CGFloat
    @State private var phaseSpeedMultiplier: Double
    @State private var indigoOpacityScale: Double
    @State private var blueOpacityScale: Double
    @State private var cyanOpacityScale: Double
    @State private var greenOpacityScale: Double
    @State private var magentaOpacityScale: Double
    @State private var whiteOpacityScale: Double
    @State private var pinkOpacityScale: Double
    /// 0 = drive aurora purely from real audio (mic or TTS).
    /// 1 = drive aurora purely from the synthetic processing pulse.
    /// Animated between the two so transitions in/out of `.processing`
    /// fade rather than snap.
    @State private var pulseInfluence: Double

    /// Animated 0...1 strength of the gravity pull. Tweens up to 1.0
    /// when `pullTarget` becomes non-nil and back to 0 when it clears,
    /// so the aurora doesn't snap into and out of the warped shape —
    /// it eases in over ~450ms and eases back out the same way.
    @State private var pullStrength: Double = 0
    /// Animated x of the gravity well, used when the target moves
    /// (e.g. a new element is detected before the previous pull has
    /// finished fading). Tracking the position via @State means the
    /// pull location slides between targets rather than teleporting.
    @State private var animatedPullTargetX: CGFloat = 0
    @State private var animatedPullTargetY: CGFloat = 0

    init(audioPowerLevel: CGFloat, mode: EdgeGlowMode, pullTarget: CGPoint?) {
        self.audioPowerLevel = audioPowerLevel
        self.mode = mode
        self.pullTarget = pullTarget
        let initial = EdgeGlowModeStyle.style(for: mode)
        _amplitudeMultiplier = State(initialValue: initial.amplitudeMultiplier)
        _phaseSpeedMultiplier = State(initialValue: initial.phaseSpeedMultiplier)
        _indigoOpacityScale = State(initialValue: initial.indigoOpacityScale)
        _blueOpacityScale = State(initialValue: initial.blueOpacityScale)
        _cyanOpacityScale = State(initialValue: initial.cyanOpacityScale)
        _greenOpacityScale = State(initialValue: initial.greenOpacityScale)
        _magentaOpacityScale = State(initialValue: initial.magentaOpacityScale)
        _whiteOpacityScale = State(initialValue: initial.whiteOpacityScale)
        _pinkOpacityScale = State(initialValue: initial.pinkOpacityScale)
        _pulseInfluence = State(initialValue: initial.usesSyntheticPulse ? 1.0 : 0.0)
        // Seed the animated pull-target with the current target (or zero
        // if there isn't one) so the first non-nil transition doesn't
        // lerp from a stale position.
        _animatedPullTargetX = State(initialValue: pullTarget?.x ?? 0)
        _animatedPullTargetY = State(initialValue: pullTarget?.y ?? 0)
        _pullStrength = State(initialValue: pullTarget != nil ? 1.0 : 0.0)
    }

    /// Period of the synthetic processing-state pulse. Fixed rather
    /// than mode-derived so its phase stays continuous when fading
    /// in/out of processing — animating the period would speed up or
    /// slow down the visible pulse mid-cycle, which looks worse than
    /// just keeping a steady 2.4s rhythm whose amplitude fades.
    private static let syntheticPulsePeriodSeconds: Double = 2.4

    var body: some View {
        // TimelineView drives a continuous animation independent of audio
        // so the aurora keeps "living" between words. We compute the
        // shared per-frame values once here and hand them down to all
        // four edge stacks, rather than letting each stack run its own
        // TimelineView (which would still work, but redundantly).
        TimelineView(.animation) { timeline in
            let elapsedSeconds = timeline.date.timeIntervalSinceReferenceDate

            // Synthetic pulse for the processing/loading state. 0...1.
            // Always computed; its visual influence is gated by
            // `pulseInfluence` (animated) rather than a hard switch.
            let syntheticPulse = CGFloat((sin(elapsedSeconds * 2 * .pi / Self.syntheticPulsePeriodSeconds) + 1) / 2)

            // Crossfade audio reactivity between real-audio and pulse.
            // When pulseInfluence is 0 (listening/responding), only the
            // mic/TTS-derived value contributes; when it's 1
            // (processing), only the synthetic pulse contributes; in
            // between we blend, so transitioning between states slides
            // smoothly rather than snapping.
            let micReactivity = audioReactivityNormalized
            let pulseReactivity = syntheticPulse * 0.65
            let audioReactivity = micReactivity * (1 - CGFloat(pulseInfluence))
                                + pulseReactivity * CGFloat(pulseInfluence)

            // Same crossfade for overall opacity. Real-audio mode uses
            // the eased mic/TTS curve (0.55 baseline → 1.0 peak); pulse
            // mode breathes 0.45 → 0.80; the blend is what the user
            // sees during transitions.
            let micIntensity = audioReactiveIntensity
            let pulseIntensity = 0.45 + Double(syntheticPulse) * 0.35
            let overallOpacity = micIntensity * (1 - pulseInfluence) + pulseIntensity * pulseInfluence

            // Reconstitute the (continuously interpolated) style from
            // the @State scalars so AuroraEdgeRibbonStack can keep its
            // existing struct-based parameter API. usesSyntheticPulse
            // and pulsePeriodSeconds are forced off here because we've
            // already baked the pulse into `audioReactivity` above.
            let interpolatedStyle = EdgeGlowModeStyle(
                usesSyntheticPulse: false,
                pulsePeriodSeconds: 0,
                phaseSpeedMultiplier: phaseSpeedMultiplier,
                amplitudeMultiplier: amplitudeMultiplier,
                indigoOpacityScale: indigoOpacityScale,
                blueOpacityScale: blueOpacityScale,
                cyanOpacityScale: cyanOpacityScale,
                greenOpacityScale: greenOpacityScale,
                magentaOpacityScale: magentaOpacityScale,
                whiteOpacityScale: whiteOpacityScale,
                pinkOpacityScale: pinkOpacityScale
            )

            // GeometryReader is needed because the left/right edges
            // require frame-swapped sizing (we render the bottom-anchored
            // ribbon stack into a tall-and-narrow frame whose long axis
            // matches the screen height, then rotate it 90° onto the
            // side edge). Without the actual screen dimensions in hand,
            // we can't size those frames correctly.
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height

                // The pull target lives in screen-local SwiftUI
                // coordinates, but each rotated stack draws in its own
                // coordinate system. Convert once per frame so each
                // stack receives the target expressed in its own
                // bottom-anchored frame:
                //   bottom: identity
                //   top:    rotated 180° around frame center
                //   left:   rotated 90° CW around top-leading + shifted
                //   right:  rotated 90° CCW around top-leading + shifted
                // These inversions match the rotations applied to each
                // stack below — derived by inverting the geometric
                // transforms used to position the four edges.
                let screenPullPoint = CGPoint(x: animatedPullTargetX, y: animatedPullTargetY)
                let bottomLocalPullTarget = screenPullPoint
                let topLocalPullTarget = CGPoint(
                    x: screenWidth - screenPullPoint.x,
                    y: screenHeight - screenPullPoint.y
                )
                let leftLocalPullTarget = CGPoint(
                    x: screenPullPoint.y,
                    y: screenWidth - screenPullPoint.x
                )
                let rightLocalPullTarget = CGPoint(
                    x: screenHeight - screenPullPoint.y,
                    y: screenPullPoint.x
                )

                // ZStack is anchored top-leading so each stack's frame
                // origin lines up at (0, 0). The rotation math for the
                // side edges below assumes that origin — with default
                // .center alignment the side stacks would be centered
                // first and then the rotations would land in the wrong
                // place.
                ZStack(alignment: .topLeading) {
                    // BOTTOM edge — natural orientation.
                    AuroraEdgeRibbonStack(
                        elapsedSeconds: elapsedSeconds,
                        audioReactivity: audioReactivity,
                        style: interpolatedStyle,
                        localPullTarget: bottomLocalPullTarget,
                        pullStrength: pullStrength
                    )
                    .frame(width: screenWidth, height: screenHeight)

                    // TOP edge — rotated 180° around frame center.
                    AuroraEdgeRibbonStack(
                        elapsedSeconds: elapsedSeconds,
                        audioReactivity: audioReactivity,
                        style: interpolatedStyle,
                        localPullTarget: topLocalPullTarget,
                        pullStrength: pullStrength
                    )
                    .frame(width: screenWidth, height: screenHeight)
                    .rotationEffect(.degrees(180))

                    // LEFT edge — frame swapped + rotated 90° CW.
                    AuroraEdgeRibbonStack(
                        elapsedSeconds: elapsedSeconds,
                        audioReactivity: audioReactivity,
                        style: interpolatedStyle,
                        localPullTarget: leftLocalPullTarget,
                        pullStrength: pullStrength
                    )
                    .frame(width: screenHeight, height: screenWidth)
                    .rotationEffect(.degrees(90), anchor: .topLeading)
                    .offset(x: screenWidth, y: 0)

                    // RIGHT edge — frame swapped + rotated 90° CCW.
                    AuroraEdgeRibbonStack(
                        elapsedSeconds: elapsedSeconds,
                        audioReactivity: audioReactivity,
                        style: interpolatedStyle,
                        localPullTarget: rightLocalPullTarget,
                        pullStrength: pullStrength
                    )
                    .frame(width: screenHeight, height: screenWidth)
                    .rotationEffect(.degrees(-90), anchor: .topLeading)
                    .offset(x: 0, y: screenHeight)
                }
                .opacity(overallOpacity)
                .allowsHitTesting(false)
            }
        }
        // Animate every mode-derived scalar over 600ms whenever the
        // parent flips `mode`. This is what turns the previously hard
        // snap between listening/processing/responding into a smooth
        // crossfade — the curtains slow down (or speed up), the
        // palette warms (or cools), and the synthetic pulse fades in
        // (or out) all in lockstep over a single eased transition.
        .onChange(of: mode) { _, newMode in
            let target = EdgeGlowModeStyle.style(for: newMode)
            withAnimation(.easeInOut(duration: 0.6)) {
                amplitudeMultiplier = target.amplitudeMultiplier
                phaseSpeedMultiplier = target.phaseSpeedMultiplier
                indigoOpacityScale = target.indigoOpacityScale
                blueOpacityScale = target.blueOpacityScale
                cyanOpacityScale = target.cyanOpacityScale
                greenOpacityScale = target.greenOpacityScale
                magentaOpacityScale = target.magentaOpacityScale
                whiteOpacityScale = target.whiteOpacityScale
                pinkOpacityScale = target.pinkOpacityScale
                pulseInfluence = target.usesSyntheticPulse ? 1.0 : 0.0
            }
        }
        // Animate the gravity well: pull strength eases in and out, and
        // when the target moves while the pull is already active the
        // anchor location glides rather than teleports.
        .onChange(of: pullTarget) { oldTarget, newTarget in
            if let target = newTarget {
                if oldTarget == nil {
                    // Cold start (no prior pull): snap the position so
                    // the warp grows out of the right place, then ease
                    // the strength up over 450ms.
                    animatedPullTargetX = target.x
                    animatedPullTargetY = target.y
                    withAnimation(.easeInOut(duration: 0.45)) {
                        pullStrength = 1.0
                    }
                } else {
                    // Hot swap (target moved between elements): slide
                    // the anchor from the previous target to the new
                    // one without flickering the strength.
                    withAnimation(.easeInOut(duration: 0.45)) {
                        animatedPullTargetX = target.x
                        animatedPullTargetY = target.y
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.45)) {
                    pullStrength = 0.0
                }
            }
        }
    }

    /// Same easing curve the old waveform indicator used. Keeps a soft
    /// baseline glow even in silence (so the user knows the mic is hot)
    /// and ramps up to full intensity when they speak.
    private var audioReactiveIntensity: Double {
        let normalizedAudioPowerLevel = max(audioPowerLevel - 0.008, 0)
        let easedAudioPowerLevel = pow(min(Double(normalizedAudioPowerLevel) * 2.85, 1), 0.76)
        let baselineIntensity: Double = 0.55
        let audioReactiveBoost: Double = 0.45
        return baselineIntensity + easedAudioPowerLevel * audioReactiveBoost
    }

    /// 0...1 audio drive used inside the ribbons to scale wave amplitude
    /// and animation speed. Same eased curve as `audioReactiveIntensity`
    /// but without the baseline offset — silence really is 0 here so the
    /// aurora calms down between words instead of constantly thrashing.
    private var audioReactivityNormalized: CGFloat {
        let normalizedAudioPowerLevel = max(audioPowerLevel - 0.008, 0)
        let eased = pow(min(Double(normalizedAudioPowerLevel) * 2.85, 1), 0.76)
        return CGFloat(eased)
    }
}

/// A single configuration entry for one aurora ribbon. Used to drive
/// the per-ribbon draw inside `AuroraEdgeRibbonStack`'s consolidated
/// Canvas. Every ribbon has the same per-frame inputs (`audioReactivity`,
/// `elapsedSeconds`) which the stack supplies once, and a small set of
/// per-layer parameters captured in this struct.
private struct AuroraRibbonSpec {
    let color: Color
    let baseHeight: CGFloat
    let waveAmplitude: CGFloat
    let primaryFrequency: CGFloat
    let secondaryFrequency: CGFloat
    let primaryPhaseSpeed: Double
    let secondaryPhaseSpeed: Double
    let lateralDriftAmplitude: CGFloat
    let lateralDriftSpeed: Double
    let bottomOpacity: Double
    let blurRadius: CGFloat
    let blendMode: GraphicsContext.BlendMode
}

/// Renders the seven-ribbon aurora curtain stack into a single
/// `Canvas`. Each ribbon is drawn inside its own `drawLayer` block so it
/// gets its individual blur radius and blend mode, but the entire stack
/// shares one SwiftUI view and one Canvas redraw per frame instead of
/// spawning seven blurred subviews. With four edges around the screen
/// that takes the per-frame compositing budget from 28 blurred Canvas
/// views down to 4 — which is the main reason the previous version
/// dropped frames once all four edges were visible. EdgeGlowView
/// renders four of these by rotating and reframing this view into the
/// bottom / top / left / right edges.
private struct AuroraEdgeRibbonStack: View {
    let elapsedSeconds: Double
    let audioReactivity: CGFloat
    let style: EdgeGlowModeStyle
    /// Gravity-well point in this stack's local (bottom-anchored)
    /// coordinates. EdgeGlowView produces this by inverting the
    /// rotation/offset of each edge so all four stacks see the
    /// "target" in their own frame. Always non-nil; when the pull is
    /// inactive `pullStrength` is 0 and the value is ignored, so we
    /// don't bother making this Optional.
    let localPullTarget: CGPoint
    /// 0...1 strength of the gravity pull. 0 = no warp (ribbons hang
    /// at the edge as usual), 1 = full warp (ribbon's top edge reaches
    /// up to the target at x = localPullTarget.x).
    let pullStrength: Double

    // Aurora palette: deep atmospheric base, classic aurora green/cyan,
    // a magenta accent for the rarer high-altitude tones, and a white
    // highlight right at the edge for that "hot core" specular feel.
    private let deepIndigo = Color(hex: "#1B1F6E")
    private let blue = Color(hex: "#2E5BFF")
    private let cyan = Color(hex: "#3CD9F0")
    private let auroraGreen = Color(hex: "#4DFFA8")
    private let magenta = Color(hex: "#C45CFF")
    private let pink = Color(hex: "#FF7AC8")

    /// All seven ribbon specs, generated fresh each render so the
    /// `style` multipliers (which animate when the mode changes) flow
    /// through. Building them as a small array keeps the Canvas body
    /// readable and lets us iterate cleanly.
    private var ribbons: [AuroraRibbonSpec] {
        [
            // Layer 1 — broad deep-indigo atmospheric bed. Reaches
            // farthest into the screen but at very low opacity.
            AuroraRibbonSpec(
                color: deepIndigo,
                baseHeight: 180,
                waveAmplitude: 24 * style.amplitudeMultiplier,
                primaryFrequency: 1.3,
                secondaryFrequency: 0.55,
                primaryPhaseSpeed: 0.18 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: 0.10 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 90,
                lateralDriftSpeed: 0.07 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.42 * style.indigoOpacityScale,
                blurRadius: 38,
                blendMode: .normal
            ),
            // Layer 2 — blue mid bloom.
            AuroraRibbonSpec(
                color: blue,
                baseHeight: 130,
                waveAmplitude: 32 * style.amplitudeMultiplier,
                primaryFrequency: 1.7,
                secondaryFrequency: 0.95,
                primaryPhaseSpeed: 0.32 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: -0.21 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 70,
                lateralDriftSpeed: 0.11 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.30 * style.blueOpacityScale,
                blurRadius: 26,
                blendMode: .plusLighter
            ),
            // Layer 3 — cyan aurora curtain.
            AuroraRibbonSpec(
                color: cyan,
                baseHeight: 95,
                waveAmplitude: 36 * style.amplitudeMultiplier,
                primaryFrequency: 2.3,
                secondaryFrequency: 1.1,
                primaryPhaseSpeed: 0.42 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: 0.28 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 60,
                lateralDriftSpeed: -0.14 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.24 * style.cyanOpacityScale,
                blurRadius: 18,
                blendMode: .plusLighter
            ),
            // Layer 4 — classic aurora green.
            AuroraRibbonSpec(
                color: auroraGreen,
                baseHeight: 75,
                waveAmplitude: 30 * style.amplitudeMultiplier,
                primaryFrequency: 1.7,
                secondaryFrequency: 2.6,
                primaryPhaseSpeed: -0.27 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: 0.36 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 80,
                lateralDriftSpeed: 0.17 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.18 * style.greenOpacityScale,
                blurRadius: 16,
                blendMode: .plusLighter
            ),
            // Layer 5 — magenta accent.
            AuroraRibbonSpec(
                color: magenta,
                baseHeight: 58,
                waveAmplitude: 26 * style.amplitudeMultiplier,
                primaryFrequency: 1.2,
                secondaryFrequency: 2.1,
                primaryPhaseSpeed: 0.22 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: -0.31 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 100,
                lateralDriftSpeed: -0.09 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.16 * style.magentaOpacityScale,
                blurRadius: 14,
                blendMode: .plusLighter
            ),
            // Layer 6 — white hot core.
            AuroraRibbonSpec(
                color: .white,
                baseHeight: 22,
                waveAmplitude: 5 * style.amplitudeMultiplier,
                primaryFrequency: 3.0,
                secondaryFrequency: 1.5,
                primaryPhaseSpeed: 0.50 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: -0.30 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 40,
                lateralDriftSpeed: 0.20 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.24 * style.whiteOpacityScale,
                blurRadius: 7,
                blendMode: .plusLighter
            ),
            // Layer 7 — pink under-glow.
            AuroraRibbonSpec(
                color: pink,
                baseHeight: 16,
                waveAmplitude: 3 * style.amplitudeMultiplier,
                primaryFrequency: 2.5,
                secondaryFrequency: 1.0,
                primaryPhaseSpeed: -0.18 * style.phaseSpeedMultiplier,
                secondaryPhaseSpeed: 0.24 * style.phaseSpeedMultiplier,
                lateralDriftAmplitude: 30,
                lateralDriftSpeed: 0.15 * style.phaseSpeedMultiplier,
                bottomOpacity: 0.16 * style.pinkOpacityScale,
                blurRadius: 5,
                blendMode: .plusLighter
            ),
        ]
    }

    var body: some View {
        // ONE Canvas draws all seven ribbons. Each ribbon is wrapped
        // in its own drawLayer + blur filter so the per-layer softness
        // varies (deep indigo gets a 38pt halo, the white hot core
        // stays sharp), but everything happens inside a single SwiftUI
        // view rather than a stack of seven blurred Canvas subviews.
        Canvas { context, size in
            let specs = ribbons
            for spec in specs {
                drawRibbon(spec: spec, in: context, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func drawRibbon(
        spec: AuroraRibbonSpec,
        in context: GraphicsContext,
        size: CGSize
    ) {
        // Audio amplifies wave amplitude up to 1.4x and phase speed up
        // to 1.6x. Subtle enough that silence still has motion, strong
        // enough that speaking visibly energizes the aurora.
        let amplitude = spec.waveAmplitude * (1 + audioReactivity * 0.4)
        let phaseSpeedBoost = 1 + Double(audioReactivity) * 0.6
        let primaryPhase = elapsedSeconds * spec.primaryPhaseSpeed * phaseSpeedBoost
        let secondaryPhase = elapsedSeconds * spec.secondaryPhaseSpeed * phaseSpeedBoost
        let lateralDrift = CGFloat(sin(elapsedSeconds * spec.lateralDriftSpeed)) * spec.lateralDriftAmplitude

        // Gravity-pull setup. `pullSigma` controls how wide the warped
        // region is (in points along the ribbon's long axis); the
        // Gaussian centered at localPullTarget.x is what gives the
        // single-peak "pulled toward a single point" shape rather than
        // a generic upward bulge. `pullVerticalDistance` is how far up
        // the wave can reach at x = target.x with full pull strength —
        // capped to a positive value so we never pull the wave DOWN
        // (which would happen if the target sits below the ribbon's
        // resting top, e.g. for an element near a screen edge).
        let baseTopY = size.height - spec.baseHeight
        let pullSigma: CGFloat = 220
        let pullVerticalDistance = max(0, baseTopY - localPullTarget.y) * CGFloat(pullStrength)

        // Top edge of the ribbon: two sine waves summed at a 60/40
        // weighting, then warped upward by the Gaussian-weighted pull
        // toward the local target. With pullStrength=0 the warp term
        // is zero and we get the original undulating ribbon.
        func topEdgeY(at x: CGFloat) -> CGFloat {
            let primaryComponent = sin(2 * .pi * spec.primaryFrequency * (x + lateralDrift) / size.width + primaryPhase) * 0.6
            let secondaryComponent = sin(2 * .pi * spec.secondaryFrequency * (x - lateralDrift) / size.width + secondaryPhase) * 0.4
            let unwarpedTopY = baseTopY + amplitude * CGFloat(primaryComponent + secondaryComponent)
            // Gaussian falloff in x — peaks at 1 when x == target.x,
            // decays to ~0 at distances beyond ~3 sigma.
            let distanceFromTargetX = x - localPullTarget.x
            let gaussian = exp(-(distanceFromTargetX * distanceFromTargetX) / (2 * pullSigma * pullSigma))
            // Pull up by `pullVerticalDistance * gaussian`. Subtract
            // because smaller y is up the screen.
            return unwarpedTopY - CGFloat(gaussian) * pullVerticalDistance
        }

        // Sample at 8pt steps. The blur smooths over any visible
        // segmentation, and 8pt halves the per-frame path-construction
        // cost vs the original 4pt sampling — meaningful when this
        // runs seven times per stack × four stacks per frame.
        let sampleStep: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: 0, y: topEdgeY(at: 0)))
        var x: CGFloat = sampleStep
        while x <= size.width {
            path.addLine(to: CGPoint(x: x, y: topEdgeY(at: x)))
            x += sampleStep
        }
        // Close down through the bottom corners into a filled shape.
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()

        // Vertical gradient: transparent at the wave's average top,
        // fully colored at the screen edge, with a soft midpoint so the
        // upper half of the ribbon doesn't look hollow. When the pull
        // is active, extend the gradient's transparent end upward by
        // the maximum possible warp distance so the pulled "spire" of
        // the ribbon actually has visible color at its tip rather than
        // sitting in the gradient's invisible zone.
        let gradient = Gradient(stops: [
            .init(color: spec.color.opacity(0), location: 0),
            .init(color: spec.color.opacity(spec.bottomOpacity * 0.55), location: 0.55),
            .init(color: spec.color.opacity(spec.bottomOpacity), location: 1)
        ])
        let gradientTopY = size.height - spec.baseHeight - amplitude - pullVerticalDistance
        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: gradientTopY),
            endPoint: CGPoint(x: 0, y: size.height)
        )

        // The outer mutable copy of context carries the ribbon's blend
        // mode — that's what determines how the layer composites onto
        // whatever's already been drawn (.plusLighter for additive
        // glow, .normal for the first base layer). The inner drawLayer
        // is where we add the per-ribbon blur filter and do the actual
        // fill. Wrapping in drawLayer means the blur applies only to
        // this ribbon's pixels, not to the whole canvas.
        var ribbonContext = context
        ribbonContext.blendMode = spec.blendMode
        ribbonContext.drawLayer { layerContext in
            layerContext.addFilter(.blur(radius: spec.blurRadius))
            layerContext.fill(path, with: shading)
        }
    }
}

// MARK: - Mystical Orb

/// Clicky's pointer cursor — a solid right-tilted parallelogram (matches
/// the menu bar logo) sitting inside a single-color blue glow. The outer
/// 88x88 frame is preserved so positioning math elsewhere is unaffected.
private struct MysticalOrbView: View {
    @State private var pulseScale: CGFloat = 1.0

    private let bodyBlue = Color(hex: "#3380FF")

    var body: some View {
        ZStack {
            // Soft single-color glow that pulses gently behind the body.
            Parallelogram()
                .fill(bodyBlue.opacity(0.55))
                .frame(width: 52, height: 52)
                .blur(radius: 18)
                .scaleEffect(pulseScale)

            // Solid parallelogram body — a square skewed into a right-tilted
            // parallelogram, so width and height match.
            Parallelogram()
                .fill(bodyBlue)
                .frame(width: 28, height: 28)
                .shadow(color: bodyBlue.opacity(0.7), radius: 6, x: 0, y: 0)
        }
        .frame(width: 88, height: 88)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
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
