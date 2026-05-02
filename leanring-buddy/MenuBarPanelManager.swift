//
//  MenuBarPanelManager.swift
//  leanring-buddy
//
//  Manages the NSStatusItem (menu bar icon) and a custom borderless NSPanel
//  that drops down below it when clicked. The panel hosts a SwiftUI view
//  (CompanionPanelView) via NSHostingView. Uses the same NSPanel pattern as
//  FloatingSessionButton and GlobalPushToTalkOverlay for consistency.
//
//  The panel is non-activating so it does not steal focus from the user's
//  current app, and auto-dismisses when the user clicks outside.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let clickyDismissPanel = Notification.Name("clickyDismissPanel")
}

/// Custom NSPanel subclass that can become the key window even with
/// .nonactivatingPanel style, allowing text fields to receive focus.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class MenuBarPanelManager: NSObject {
    /// Weak shared reference so SwiftUI views inside the menu bar panel
    /// can ask the manager to open auxiliary windows (e.g. the Sticky
    /// Memory library) without having a manager instance threaded
    /// through every layer. Set in `init` and cleared on deinit. Weak
    /// because the AppDelegate owns the strong reference.
    private(set) static weak var shared: MenuBarPanelManager?

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?

    /// Lazily created the first time the user taps "View Library". Kept
    /// alive across opens so the window's frame and scroll position
    /// survive being closed.
    private var tasteLibraryWindowController: TasteLibraryWindowController?

    private let companionManager: CompanionManager
    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 380

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()
        Self.shared = self
        createStatusItem()

        dismissPanelObserver = NotificationCenter.default.addObserver(
            forName: .clickyDismissPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = dismissPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Auxiliary Windows

    /// Opens the "Sticky's Memory" library window, lazily creating it on
    /// first invocation. Hides the menu bar panel afterwards so the
    /// library window is the focused thing on screen — otherwise the
    /// panel hangs around behind the new window which is visually noisy.
    func openTasteLibraryWindow(companionManager: CompanionManager) {
        if tasteLibraryWindowController == nil {
            tasteLibraryWindowController = TasteLibraryWindowController(
                companionManager: companionManager
            )
        }
        tasteLibraryWindowController?.showWindow()
        hidePanel()
    }

    // MARK: - Status Item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        button.image = makeStickyMenuBarIcon()
        button.image?.isTemplate = true
        button.action = #selector(statusItemClicked)
        button.target = self
    }

    /// Draws the sticky logo (a solid orb with a flat-cut bottom so it
    /// looks like it's "standing on something") as a menu bar icon. The
    /// in-app pointer cursor stays as a full glowing orb; the menu bar
    /// gets the slightly more graphic, sittable silhouette.
    private func makeStickyMenuBarIcon() -> NSImage {
        let iconSize: CGFloat = 18
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()

        let orbDiameter = iconSize * 0.78
        let radius = orbDiameter / 2
        let center = CGPoint(x: iconSize / 2, y: iconSize / 2)

        // How far below center the flat chord sits, as a fraction of the
        // radius. ~0.65 cuts off a small slice — enough to read as a flat
        // base without losing the round-orb feel.
        let chordOffsetFraction: CGFloat = 0.65
        let chordOffset = radius * chordOffsetFraction
        let halfChord = sqrt(radius * radius - chordOffset * chordOffset)

        // AppKit's drawing context is y-up, so "below center" = smaller y.
        let chordY = center.y - chordOffset
        let rightChordEnd = CGPoint(x: center.x + halfChord, y: chordY)

        // Angles (in degrees) on the circle for the two chord endpoints,
        // measured from the +x axis counterclockwise (standard math).
        let rightAngle = atan2(-chordOffset, halfChord) * 180 / .pi
        let leftAngle = atan2(-chordOffset, -halfChord) * 180 / .pi

        let path = NSBezierPath()
        path.move(to: rightChordEnd)
        // Counterclockwise arc from right chord endpoint up over the top
        // to the left chord endpoint — i.e. the rounded part of the orb.
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: rightAngle,
            endAngle: leftAngle,
            clockwise: false
        )
        // Close the silhouette with a horizontal line — the flat base.
        path.close()

        NSColor.black.setFill()
        path.fill()

        image.unlockFocus()
        return image
    }

    /// Opens the panel automatically on app launch so the user sees
    /// permissions and the start button right away.
    func showPanelOnLaunch() {
        // Small delay so the status item has time to appear in the menu bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showPanel()
        }
    }

    @objc private func statusItemClicked() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Panel Lifecycle

    private func showPanel() {
        if panel == nil {
            createPanel()
        }

        positionPanelBelowStatusItem()

        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func createPanel() {
        let companionPanelView = CompanionPanelView(companionManager: companionManager)
            .frame(width: panelWidth)

        let hostingView = NSHostingView(rootView: companionPanelView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        // The panel's content view is a custom layer-backed NSView that
        // paints a warm walnut→rust gradient with a soft amber radial
        // glow in the bottom-right corner — matching the painterly,
        // atmospheric aesthetic the project uses (see
        // `WarmDropdownBackgroundView` below). 12pt continuous corners
        // and a faint amber border are applied via the view's own layer
        // so the system shadow (`hasShadow = true`) follows the rounded
        // alpha correctly.
        let warmBackgroundView = WarmDropdownBackgroundView()
        warmBackgroundView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // Pin the SwiftUI hosting view to the warm background view's
        // bounds so it tracks resizes when the panel height adjusts to
        // its content fitting size.
        warmBackgroundView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: warmBackgroundView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: warmBackgroundView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: warmBackgroundView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: warmBackgroundView.bottomAnchor)
        ])

        let menuBarPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        menuBarPanel.isFloatingPanel = true
        menuBarPanel.level = .floating
        menuBarPanel.isOpaque = false
        menuBarPanel.backgroundColor = .clear
        // Let AppKit render the native dropdown shadow (matching Apple's
        // own menu-bar dropdowns). The shadow follows the rounded-rect
        // alpha of the NSVisualEffectView content automatically.
        menuBarPanel.hasShadow = true
        menuBarPanel.hidesOnDeactivate = false
        menuBarPanel.isExcludedFromWindowsMenu = true
        menuBarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        menuBarPanel.isMovableByWindowBackground = false
        menuBarPanel.titleVisibility = .hidden
        menuBarPanel.titlebarAppearsTransparent = true

        menuBarPanel.contentView = warmBackgroundView
        panel = menuBarPanel
    }

    private func positionPanelBelowStatusItem() {
        guard let panel else { return }
        guard let buttonWindow = statusItem?.button?.window else { return }

        let statusItemFrame = buttonWindow.frame
        let gapBelowMenuBar: CGFloat = 4

        // Calculate the panel's content height from the hosting view's fitting size
        // so the panel snugly wraps the SwiftUI content instead of using a fixed height.
        let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: panelWidth, height: panelHeight)
        let actualPanelHeight = fittingSize.height

        // Horizontally center the panel beneath the status item icon
        let panelOriginX = statusItemFrame.midX - (panelWidth / 2)
        let panelOriginY = statusItemFrame.minY - actualPanelHeight - gapBelowMenuBar

        panel.setFrame(
            NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: actualPanelHeight),
            display: true
        )
    }

    // MARK: - Click Outside Dismissal

    /// Installs a global event monitor that hides the panel when the user clicks
    /// anywhere outside it — the same transient dismissal behavior as NSPopover.
    /// Uses a short delay so that system permission dialogs (triggered by Grant
    /// buttons in the panel) don't immediately dismiss the panel when they appear.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return }

            // Check if the click is inside the status item button — if so, the
            // statusItemClicked handler will toggle the panel, so don't also hide.
            let clickLocation = NSEvent.mouseLocation
            if panel.frame.contains(clickLocation) {
                return
            }

            // SwiftUI's `.popover` (used by the voice picker dropdown
            // inside the panel content) renders into a separate AppKit
            // window that's positioned outside the parent panel's frame.
            // Without this guard the very first click on any row of the
            // popover dismisses the entire menu bar panel, tearing the
            // popover down with it. Exempt any visible app window that
            // accepts mouse events and contains the click point — that
            // covers SwiftUI popovers and any future child sheets without
            // exempting the click-through cursor overlay.
            let clickIsInsideAuxiliaryAppWindow = NSApp.windows.contains { auxiliaryWindow in
                guard auxiliaryWindow !== panel else { return false }
                guard auxiliaryWindow.isVisible else { return false }
                guard !auxiliaryWindow.ignoresMouseEvents else { return false }
                return auxiliaryWindow.frame.contains(clickLocation)
            }
            if clickIsInsideAuxiliaryAppWindow {
                return
            }

            // Delay dismissal slightly to avoid closing the panel when
            // a system permission dialog appears (e.g. microphone access).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard panel.isVisible else { return }

                // If permissions aren't all granted yet, a system dialog
                // may have focus — don't dismiss during onboarding.
                if !self.companionManager.allPermissionsGranted && !NSApp.isActive {
                    return
                }

                // Pin the panel while the user has transient teach-flow
                // state in flight (recording, analyzing, a review queue,
                // or an unsaved result card). A click anywhere outside the
                // panel during these states would silently throw away
                // mid-flow work, which is worse than leaving the panel up.
                if self.companionManager.shouldKeepPanelOpenForActiveTeachState {
                    return
                }

                self.hidePanel()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}

// MARK: - Warm Dropdown Background

/// Layer-backed NSView that paints the dropdown surface in a riso-print
/// aesthetic — deep near-black at the top, vibrant red through the upper
/// middle, soft pink-peach at the bottom, with a heavy paper-grain noise
/// overlay so the gradient reads as printed rather than digital.
///
/// Layer hierarchy (back to front):
///   root layer (rounded mask, hairline amber border)
///     ├─ gradientLayer  — multi-stop vertical (black → red → pink)
///     ├─ glowLayer      — soft warm radial bloom in the bottom-right
///     ├─ columnLayer    — faint vertical bar pattern (subtle "columns")
///     └─ grainLayer     — tiled procedural noise (paper grain)
final class WarmDropdownBackgroundView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let columnLayer = CALayer()
    private let grainLayer = CALayer()

    /// Cached procedural noise tile so we don't regenerate the random
    /// pattern every time the layer needs to redraw. The image is large
    /// enough (200×200) that the tiled repeat doesn't read as a visible
    /// pattern inside a 320pt-wide panel.
    private static let cachedGrainPatternImage: NSImage = makeGrainPatternImage()

    /// Cached vertical-bar tile so the column overlay is just a tile-fill
    /// rather than a stack of CAGradientLayers.
    private static let cachedColumnPatternImage: NSImage = makeColumnPatternImage()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        // Faint warm border — same idea as Apple's separatorColor stroke
        // but tinted amber so it reads as part of the warm aesthetic
        // rather than fighting it.
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(red: 1.0, green: 0.66, blue: 0.32, alpha: 0.22).cgColor

        // Vertical gradient: near-black at the top, vibrant red through
        // the upper-middle band, warm rust through the lower-middle, and
        // a soft pink-peach at the very bottom — matching the riso-print
        // reference. CAGradientLayer's coordinate system is flipped from
        // view space (y=0 is bottom), so the bottom-of-visible color is
        // first in the array.
        gradientLayer.colors = [
            // Soft pink-peach — visual bottom of the dropdown.
            NSColor(red: 0.97, green: 0.74, blue: 0.74, alpha: 1.0).cgColor,
            // Warm rust transition.
            NSColor(red: 0.92, green: 0.40, blue: 0.30, alpha: 1.0).cgColor,
            // Vibrant red through the middle — the dominant band.
            NSColor(red: 0.86, green: 0.18, blue: 0.10, alpha: 1.0).cgColor,
            // Burnt walnut transition.
            NSColor(red: 0.30, green: 0.07, blue: 0.04, alpha: 1.0).cgColor,
            // Near-black — visual top of the dropdown.
            NSColor(red: 0.06, green: 0.02, blue: 0.02, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 0.18, 0.45, 0.78, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer?.addSublayer(gradientLayer)

        // Soft warm radial bloom anchored to the bottom-right. Adds a hint
        // of asymmetry so the dropdown doesn't feel like a flat strip.
        // Pulled back from the previous design — the new gradient does
        // most of the warmth on its own.
        glowLayer.type = .radial
        glowLayer.colors = [
            NSColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 0.30).cgColor,
            NSColor(red: 1.0, green: 0.60, blue: 0.30, alpha: 0.0).cgColor
        ]
        glowLayer.locations = [0.0, 1.0]
        glowLayer.startPoint = CGPoint(x: 0.85, y: 0.0)   // bottom-right
        glowLayer.endPoint = CGPoint(x: 1.5, y: 0.85)
        layer?.addSublayer(glowLayer)

        // Subtle vertical bars — gives the dropdown the riso "column"
        // texture without literally drawing a stack of gradient pillars.
        // Tiles a small pattern image of darker vertical strips with
        // feathered edges, blended via multiply at low opacity so it
        // reads as a hint of structure rather than a comb.
        columnLayer.backgroundColor = NSColor(
            patternImage: Self.cachedColumnPatternImage
        ).cgColor
        columnLayer.opacity = 0.18
        columnLayer.compositingFilter = "multiplyBlendMode"
        layer?.addSublayer(columnLayer)

        // Paper grain — the most distinctive visual element. A 200×200
        // tile of fine random dots (mix of light and dark, varying
        // alpha) tiled across the whole surface and blended via overlay
        // so it darkens shadows and lifts highlights, reading as
        // genuine paper texture rather than uniform noise.
        grainLayer.backgroundColor = NSColor(
            patternImage: Self.cachedGrainPatternImage
        ).cgColor
        grainLayer.opacity = 0.55
        grainLayer.compositingFilter = "overlayBlendMode"
        layer?.addSublayer(grainLayer)
    }

    override func layout() {
        super.layout()
        // Disable the implicit fade animation that CAGradientLayer
        // performs on frame changes, so resizes (when the panel snaps
        // to fitting size on first show) don't flicker.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        glowLayer.frame = bounds
        columnLayer.frame = bounds
        grainLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Pattern image generators

    /// Generates a 200×200 noise tile of fine random dots — a mix of
    /// translucent light and dark pixels — that, when tiled across the
    /// dropdown and blended via `overlayBlendMode`, reads as paper
    /// grain. Cached as a static so we only pay the cost once per app
    /// launch regardless of how many times the panel is recreated.
    private static func makeGrainPatternImage() -> NSImage {
        let tileSize = NSSize(width: 200, height: 200)
        let grainImage = NSImage(size: tileSize)
        grainImage.lockFocus()

        // Start with a neutral 50% gray fill so overlay-blend is a no-op
        // before we add the speckle. Pure clear would darken the whole
        // dropdown because overlay treats clear as 0% luminance.
        NSColor(white: 0.5, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: tileSize).fill()

        // Dense speckle: ~12000 sub-pixel dots, each with a random
        // luminance and alpha. The variety is what makes it feel like
        // grain rather than uniform noise.
        let dotCount = 12000
        for _ in 0..<dotCount {
            let dotX = CGFloat.random(in: 0..<tileSize.width)
            let dotY = CGFloat.random(in: 0..<tileSize.height)
            let dotLuminance = CGFloat.random(in: 0.0...1.0)
            // Bias darker dots a little stronger than light ones so the
            // overall texture reads as gritty rather than glittery.
            let dotAlpha: CGFloat = dotLuminance < 0.5
                ? CGFloat.random(in: 0.20...0.55)
                : CGFloat.random(in: 0.10...0.40)
            let dotDiameter = CGFloat.random(in: 0.5...1.5)

            NSColor(white: dotLuminance, alpha: dotAlpha).setFill()
            NSRect(
                x: dotX,
                y: dotY,
                width: dotDiameter,
                height: dotDiameter
            ).fill()
        }

        // A sprinkling of slightly larger flecks — sells the
        // hand-printed paper feel where ink pools unevenly.
        let largeFleckCount = 200
        for _ in 0..<largeFleckCount {
            let fleckX = CGFloat.random(in: 0..<tileSize.width)
            let fleckY = CGFloat.random(in: 0..<tileSize.height)
            let fleckLuminance = CGFloat.random(in: 0.0...0.25)
            let fleckAlpha = CGFloat.random(in: 0.20...0.45)
            let fleckDiameter = CGFloat.random(in: 1.5...2.5)

            NSColor(white: fleckLuminance, alpha: fleckAlpha).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: fleckX,
                y: fleckY,
                width: fleckDiameter,
                height: fleckDiameter
            )).fill()
        }

        grainImage.unlockFocus()
        return grainImage
    }

    /// Generates a tile that reads as soft vertical bars when blended via
    /// `multiplyBlendMode`. Each bar is a darker stripe with feathered
    /// edges; gaps between bars stay neutral so the underlying gradient
    /// shows through. Tile width matches the panel width so the repeat
    /// is invisible inside the dropdown.
    private static func makeColumnPatternImage() -> NSImage {
        let tileSize = NSSize(width: 320, height: 1)
        let columnImage = NSImage(size: tileSize)
        columnImage.lockFocus()

        // Neutral fill — multiply-blend treats white as identity, so the
        // gradient passes through unchanged where we don't paint a bar.
        NSColor.white.setFill()
        NSRect(origin: .zero, size: tileSize).fill()

        // Hand-tuned bar positions and widths so the pattern doesn't
        // look mechanical. Picked to feel like the riso reference.
        struct VerticalBar {
            let centerX: CGFloat
            let halfWidth: CGFloat
            let darkness: CGFloat // 0 = black, 1 = unchanged
        }
        let bars: [VerticalBar] = [
            VerticalBar(centerX: 18,  halfWidth: 10, darkness: 0.65),
            VerticalBar(centerX: 58,  halfWidth: 14, darkness: 0.72),
            VerticalBar(centerX: 102, halfWidth: 8,  darkness: 0.60),
            VerticalBar(centerX: 145, halfWidth: 16, darkness: 0.78),
            VerticalBar(centerX: 188, halfWidth: 9,  darkness: 0.62),
            VerticalBar(centerX: 232, halfWidth: 13, darkness: 0.70),
            VerticalBar(centerX: 278, halfWidth: 11, darkness: 0.66),
            VerticalBar(centerX: 308, halfWidth: 7,  darkness: 0.58)
        ]

        // Render each bar as a sequence of 1pt-wide vertical strips with
        // a cosine-shaped horizontal falloff so the bar tapers smoothly
        // at its edges instead of cutting off as a hard rectangle.
        for bar in bars {
            let leftEdge = max(0, bar.centerX - bar.halfWidth)
            let rightEdge = min(tileSize.width, bar.centerX + bar.halfWidth)
            var currentX = leftEdge
            while currentX < rightEdge {
                let normalizedDistanceFromCentre = abs(currentX - bar.centerX) / bar.halfWidth
                let falloffFactor = (cos(normalizedDistanceFromCentre * .pi) + 1) / 2
                let pixelDarkness = 1.0 - (1.0 - bar.darkness) * falloffFactor
                NSColor(white: pixelDarkness, alpha: 1.0).setFill()
                NSRect(x: currentX, y: 0, width: 1, height: tileSize.height).fill()
                currentX += 1
            }
        }

        columnImage.unlockFocus()
        return columnImage
    }
}
