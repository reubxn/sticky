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
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?

    private let companionManager: CompanionManager
    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 380

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()
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

    // MARK: - Status Item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        button.image = makeClickyMenuBarIcon()
        button.image?.isTemplate = true
        button.action = #selector(statusItemClicked)
        button.target = self
    }

    /// Draws the clicky logo (right-tilted parallelogram) as a menu bar
    /// icon. Same geometry as the `Parallelogram` SwiftUI shape used for
    /// the in-app pointer cursor so the menu bar icon and the pointer match.
    /// "Tilted right" = top edge shifted right of the bottom edge.
    private func makeClickyMenuBarIcon() -> NSImage {
        let iconSize: CGFloat = 18
        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()

        // Bounding box of the parallelogram inside the icon — leave a little
        // padding around the edges so the menu bar doesn't clip the shape.
        let parallelogramWidth = iconSize * 0.78
        let parallelogramHeight = iconSize * 0.78
        let originX = (iconSize - parallelogramWidth) / 2
        let originY = (iconSize - parallelogramHeight) / 2

        // Same skew fraction as `Parallelogram.skewFraction` default (0.35).
        let skew = parallelogramWidth * 0.35

        // AppKit y-axis is bottom-up, so "top" here = larger y. The shape
        // leans right (top edge shifted right of the bottom edge).
        let bottomLeft = CGPoint(x: originX, y: originY)
        let topLeft = CGPoint(x: originX + skew, y: originY + parallelogramHeight)
        let topRight = CGPoint(x: originX + parallelogramWidth, y: originY + parallelogramHeight)
        let bottomRight = CGPoint(x: originX + parallelogramWidth - skew, y: originY)

        let path = NSBezierPath()
        path.move(to: bottomLeft)
        path.line(to: topLeft)
        path.line(to: topRight)
        path.line(to: bottomRight)
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

        // The visual-effect view IS the panel's content view. This is the
        // standard AppKit pattern for translucent dropdowns and is what
        // makes the desktop blur reliably visible — wrapping the blur
        // inside a SwiftUI `.background` modifier sometimes leaves the
        // surrounding panel surface opaque depending on layer compositing.
        // Rounded corners are applied via a CALayer mask on the visual
        // effect view itself so the system shadow follows the rounded
        // alpha when `hasShadow = true`.
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.isEmphasized = true
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor
        visualEffectView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // Pin the SwiftUI hosting view to the visual-effect view's bounds
        // so it tracks resizes correctly when the panel height adjusts to
        // its content fitting size.
        visualEffectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
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

        menuBarPanel.contentView = visualEffectView
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

            // Delay dismissal slightly to avoid closing the panel when
            // a system permission dialog appears (e.g. microphone access).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard panel.isVisible else { return }

                // If permissions aren't all granted yet, a system dialog
                // may have focus — don't dismiss during onboarding.
                if !self.companionManager.allPermissionsGranted && !NSApp.isActive {
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
