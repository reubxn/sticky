//
//  DashboardWindowController.swift
//  leanring-buddy
//
//  Owns the Dashboard NSWindow — a real titled, resizable window (not
//  a transient panel) hosting the full SwiftUI Dashboard with sidebar
//  navigation. Modeled directly on `ChatWindowController` for
//  consistency: lazy creation, hide-on-close (so re-opens are instant
//  and state survives), centered on the cursor's screen on first
//  open, ElevenLabs-brand paper background tinted on the titlebar.
//
//  Because the app is LSUIElement=true, ordering this window front
//  doesn't fully steal focus from the user's previous app — it just
//  appears, like Chat does. Right behavior for an assistant
//  dashboard.
//

import AppKit
import ClerkKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {

    /// Shared singleton — the menu bar panel button calls
    /// `DashboardWindowController.shared.toggleDashboardWindow()` to
    /// show/hide. Created lazily on first reference.
    static let shared = DashboardWindowController()

    private var dashboardWindow: NSWindow?

    /// Weak reference to the shared CompanionManager. Threaded in by
    /// `MenuBarPanelManager` the first time the dashboard is opened so
    /// the in-dashboard live chat and memory tabs can share the same
    /// companion state (persona, taste profile, model selection) the
    /// menu bar and floating chat use. Weak because CompanionManager
    /// owns the app lifecycle — the dashboard is a leaf and must never
    /// extend it.
    private weak var companionManager: CompanionManager?

    private let initialWindowSize = NSSize(width: 920, height: 640)

    /// Inject the shared CompanionManager. Safe to call multiple times —
    /// last write wins.
    func setCompanionManager(_ companionManager: CompanionManager) {
        self.companionManager = companionManager
    }

    /// Toggles visibility: show if hidden, bring to front if behind,
    /// hide if it's already key. Wired to the mini-panel's "Open
    /// Dashboard" button.
    ///
    /// Optional `initialSection` lets callers (e.g. "click a persona
    /// in the mini panel") jump straight to a specific tab. Passing
    /// nil preserves whatever section was last visible.
    func toggleDashboardWindow(initialSection: DashboardSection? = nil) {
        if AuthenticationManager.shared.isSignedIn
            && !AuthenticationManager.shared.canAccessProductionFeatures {
            showDashboardWindow()
            return
        }

        if let dashboardWindow, dashboardWindow.isVisible {
            if dashboardWindow.isKeyWindow {
                dashboardWindow.orderOut(nil)
            } else {
                if let initialSection {
                    DashboardNavigationState.shared.selectedSection = initialSection
                }
                dashboardWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        if let initialSection {
            DashboardNavigationState.shared.selectedSection = initialSection
        }

        if dashboardWindow == nil {
            dashboardWindow = createDashboardWindow()
        }

        guard let dashboardWindow else { return }
        dashboardWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showDashboardWindow(initialSection: DashboardSection? = nil) {
        if let initialSection,
           AuthenticationManager.shared.canAccessProductionFeatures {
            DashboardNavigationState.shared.selectedSection = initialSection
        }

        if dashboardWindow == nil {
            dashboardWindow = createDashboardWindow()
        }

        guard let dashboardWindow else { return }
        dashboardWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Convenience: open the dashboard pinned to a specific persona
    /// in the Personas tab. The mini-panel passes a persona id when
    /// the user clicks a persona row to view it.
    func openShowingPersona(personaId: String) {
        guard AuthenticationManager.shared.canAccessProductionFeatures else {
            showDashboardWindow()
            return
        }

        DashboardNavigationState.shared.focusedPersonaId = personaId
        toggleDashboardWindow(initialSection: .tastes)
    }

    private func createDashboardWindow() -> NSWindow {
        let dashboardRootView = DashboardView(companionManager: companionManager)
            .environment(Clerk.shared)
        let hostingController = NSHostingController(rootView: dashboardRootView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialWindowSize.width,
                height: initialWindowSize.height
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sticky Dashboard"
        // Match the Chat window's editorial chrome — transparent
        // titlebar so the paper background extends edge-to-edge under
        // the traffic lights, hidden title text so the wordmark in the
        // sidebar is the only "title" reading.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Drag only from the titlebar area (standard macOS behavior) —
        // the dashboard body has interactive content the user expects
        // to click, not grab.
        window.isMovableByWindowBackground = false
        // Follow the app-level appearance driven by ThemeManager.
        // Leaving this nil means the window picks up `NSApp.appearance`
        // (system / forced light / forced dark) and the dynamic brand
        // colors below resolve into the right palette.
        window.appearance = nil
        window.backgroundColor = NSColor(ElevenLabsBrand.Colors.paper)
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.minSize = NSSize(width: 760, height: 520)

        let frameAutosaveKey = "stickyDashboardWindowFrame"
        let didRestorePersistedFrame = window.setFrameAutosaveName(frameAutosaveKey)

        if !didRestorePersistedFrame {
            centerWindowOnCursorScreen(window)
        }

        return window
    }

    /// Same centering logic as `ChatWindowController` — places the
    /// window on whichever screen the cursor is on, biased slightly
    /// above vertical center.
    private func centerWindowOnCursorScreen(_ window: NSWindow) {
        let targetScreen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main

        guard let targetScreen else { return }

        let screenVisibleFrame = targetScreen.visibleFrame
        let outerWindowFrame = window.frame

        let windowOriginX = screenVisibleFrame.midX - (outerWindowFrame.width / 2)
        let verticalBiasOffset = screenVisibleFrame.height * 0.04
        let windowOriginY = screenVisibleFrame.midY
            - (outerWindowFrame.height / 2)
            + verticalBiasOffset

        window.setFrame(
            NSRect(
                x: windowOriginX,
                y: windowOriginY,
                width: outerWindowFrame.width,
                height: outerWindowFrame.height
            ),
            display: false
        )
    }

    // MARK: - NSWindowDelegate

    /// Hide instead of destroy on close so re-opens are instant and
    /// the user's last-selected section persists.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
