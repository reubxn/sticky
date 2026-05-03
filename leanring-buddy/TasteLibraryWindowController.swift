//
//  TasteLibraryWindowController.swift
//  leanring-buddy
//
//  Owns the "Sticky's Memory" window — a real titled NSWindow that lists
//  every TastePrinciple Sticky has learned. Lazy-creates one window and
//  re-uses it across opens so the user's scroll position persists if
//  they close and re-open the window.
//
//  Like ChatWindowController, this lives outside the menu bar panel so
//  the user can leave it open while working in another app, drag it
//  around, and resize it. NSApp.activate is called on show so an
//  LSUIElement app can still surface a normal window from the menu bar
//  context.
//

import AppKit
import SwiftUI

@MainActor
final class TasteLibraryWindowController: NSObject, NSWindowDelegate {
    /// Strongly held instance of the window so it survives between opens.
    /// The class itself is held by `MenuBarPanelManager`, which lives for
    /// the lifetime of the app.
    private var libraryWindow: NSWindow?

    private let initialWindowSize = NSSize(width: 540, height: 660)

    private let companionManager: CompanionManager

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        super.init()
    }

    /// Brings the library window to the front, creating it on first
    /// invocation. We `NSApp.activate(ignoringOtherApps:)` so the window
    /// appears above whatever app the user was in — without this call,
    /// LSUIElement apps can leave the new window stranded behind other
    /// apps' windows.
    func showWindow() {
        if libraryWindow == nil {
            libraryWindow = createLibraryWindow()
        }

        guard let libraryWindow else { return }
        libraryWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createLibraryWindow() -> NSWindow {
        let libraryRootView = TasteLibraryView(companionManager: companionManager)
        let libraryHostingController = NSHostingController(rootView: libraryRootView)

        // Standard titled window with close + minimize. No fullscreen
        // and no zoom — the library is a compact reference list, it
        // doesn't benefit from being maximised.
        let libraryWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialWindowSize.width,
                height: initialWindowSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        libraryWindow.title = ""
        // Hide the system title and merge the titlebar into the content
        // area so the paper background runs beneath the traffic-light
        // controls. The view's own hero header carries the identity.
        libraryWindow.titlebarAppearsTransparent = true
        libraryWindow.titleVisibility = .hidden
        libraryWindow.titlebarSeparatorStyle = .none
        // Drag only from the titlebar area (standard macOS behavior) —
        // the library body has interactive content the user expects to
        // click, not grab.
        libraryWindow.isMovableByWindowBackground = false
        // Inherit `NSApp.appearance` (driven by ThemeManager) so the
        // window flips light/dark in lockstep with the rest of the app.
        libraryWindow.appearance = nil
        libraryWindow.backgroundColor = NSColor(ElevenLabsBrand.Colors.paper)
        libraryWindow.contentViewController = libraryHostingController
        libraryWindow.delegate = self
        // We hide-on-close instead of releasing so the window can be
        // reopened instantly without rebuilding the SwiftUI hierarchy.
        libraryWindow.isReleasedWhenClosed = false
        // Make the window join all spaces and survive being re-fronted
        // alongside fullscreen apps — the user might be teaching from a
        // fullscreen design tool.
        libraryWindow.collectionBehavior = [.fullScreenAuxiliary]
        // Don't float above other apps — it's a reference window, not a
        // companion overlay. The cursor overlay is the floating panel.
        libraryWindow.level = .normal
        libraryWindow.minSize = NSSize(width: 480, height: 480)

        // Persist the window's last frame so re-opens land where the
        // user left it. AppKit reads this from defaults on first show.
        let frameAutosaveKey = "stickyTasteLibraryWindowFrame"
        let didRestorePersistedFrame = libraryWindow.setFrameAutosaveName(frameAutosaveKey)

        if !didRestorePersistedFrame {
            centerWindowOnCursorScreen(libraryWindow)
        }

        return libraryWindow
    }

    /// Places the window centered on whichever screen the user's cursor
    /// is on right now (or main, if the cursor isn't on any screen),
    /// biased slightly above vertical center so it feels balanced.
    /// AppKit's coordinates are bottom-left origin, so a *higher* y =
    /// visually higher.
    private func centerWindowOnCursorScreen(_ libraryWindow: NSWindow) {
        let targetScreen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main

        guard let targetScreen else { return }

        let screenVisibleFrame = targetScreen.visibleFrame
        let outerWindowFrame = libraryWindow.frame

        let windowOriginX = screenVisibleFrame.midX - (outerWindowFrame.width / 2)
        let verticalBiasOffset = screenVisibleFrame.height * 0.06
        let windowOriginY = screenVisibleFrame.midY
            - (outerWindowFrame.height / 2)
            + verticalBiasOffset

        libraryWindow.setFrame(
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

    /// Hide the window on close instead of tearing it down so re-opening
    /// is instant and scroll position survives.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
