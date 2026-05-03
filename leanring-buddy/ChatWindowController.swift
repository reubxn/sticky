//
//  ChatWindowController.swift
//  leanring-buddy
//
//  Manages the pop-out chat window. The chat is a *real* NSWindow (not
//  a transient NSPanel) so the user can move it, resize it, and have it
//  stay open across app focus changes — they may want to use the chat
//  alongside whatever app they're working in.
//
//  Because LSUIElement=true, ordering this window front does not bring
//  the app to the foreground in the usual sense — the window just
//  appears, the menu bar stays as it is, and the user can keep working
//  in their previous app. That's the right behavior for an assistant
//  chat: it shouldn't steal focus from whatever the user was doing.
//

import AppKit
import SwiftUI

@MainActor
final class ChatWindowController: NSObject, NSWindowDelegate {

    /// Shared instance so the menu bar panel button can show/hide the
    /// chat without needing to thread a controller reference through
    /// every layer that wants to open it. Created lazily on first use.
    static let shared = ChatWindowController()

    private var chatWindow: NSWindow?
    /// One persistent ChatViewModel for the lifetime of the app so the
    /// transcript survives the user closing and re-opening the window.
    /// Hitting "New chat" inside the window is the explicit way to
    /// clear it. Public so the Dashboard can embed the same live chat
    /// surface inline (in its sidebar tab) and share state with the
    /// floating chat window — sending from one shows up in the other.
    let chatViewModel = ChatViewModel()

    private let initialWindowSize = NSSize(width: 540, height: 640)

    /// Toggles the chat window: opens it if hidden, brings it to front
    /// if already open but obscured, hides it if it's already key.
    /// Wired to the menu bar panel's "Open chat" button.
    ///
    /// `companionManager` is injected so the chat view model can mirror
    /// the voice flow's persona behavior (system prompt with
    /// soul + taste, persona avatar on assistant replies). Optional so
    /// the chat keeps working even when the menu bar panel hasn't been
    /// constructed yet — falls back to a generic Sticky prompt with no
    /// persona injection in that case.
    func toggleChatWindow(companionManager: CompanionManager? = nil) {
        if let companionManager {
            chatViewModel.setCompanionManager(companionManager)
        }

        if let chatWindow, chatWindow.isVisible {
            // Already on screen — bring to front if not key, hide if it is.
            if chatWindow.isKeyWindow {
                chatWindow.orderOut(nil)
            } else {
                chatWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // First open (or re-open after closing) — pick up the latest
        // model selection from UserDefaults so picking Sonnet/Opus in
        // the menu bar panel takes effect on the next chat send.
        chatViewModel.refreshSelectedModelFromUserDefaults()

        if chatWindow == nil {
            chatWindow = createChatWindow()
        }

        guard let chatWindow else { return }
        chatWindow.makeKeyAndOrderFront(nil)
        // Activate so the chat window's text editor can receive focus.
        // Without this, LSUIElement apps can show the window but the
        // text view won't accept keystrokes until the user clicks it.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createChatWindow() -> NSWindow {
        let chatRootView = ChatView(chatViewModel: chatViewModel)
        let hostingController = NSHostingController(rootView: chatRootView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialWindowSize.width,
                height: initialWindowSize.height
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        // Hide the title text and merge the titlebar into the content
        // area so the paper background extends edge-to-edge under the
        // traffic-light controls. Matches the editorial brand aesthetic.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Drag only from the titlebar area (standard macOS behavior) —
        // dragging from anywhere in the body felt off because the chat
        // body has interactive content (text, buttons) the user expects
        // to click, not grab.
        window.isMovableByWindowBackground = false
        // Inherit the app-level appearance set by ThemeManager (system /
        // forced light / forced dark). Setting `appearance = nil`
        // explicitly so the window follows `NSApp.appearance` rather
        // than locking itself to a hardcoded value.
        window.appearance = nil
        // Tint the window background to the brand paper hue so the area
        // beneath the traffic lights matches the SwiftUI content.
        // `ElevenLabsBrand.Colors.paper` is a dynamic Color, so the
        // wrapped NSColor flips automatically when appearance changes.
        window.backgroundColor = NSColor(ElevenLabsBrand.Colors.paper)
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.minSize = NSSize(width: 480, height: 480)
        // Persist the user's preferred position/size across launches.
        // After the first open, AppKit restores the last frame from
        // defaults under this key — so our manual centering only runs
        // when there's nothing saved yet.
        let frameAutosaveKey = "stickyChatWindowFrame"
        let didRestorePersistedFrame = window.setFrameAutosaveName(frameAutosaveKey)

        if !didRestorePersistedFrame {
            centerWindowOnCursorScreen(window)
        }

        return window
    }

    /// Places the window centered on whichever screen the user's cursor
    /// is on (or main, if cursor isn't on any), biased slightly above
    /// vertical center so it feels visually balanced rather than
    /// bottom-heavy. The contentRect we pass into NSWindow.init does
    /// *not* include the titlebar, so we use `setFrame:` against the
    /// real outer frame here — `setFrameOrigin` against the contentRect
    /// produced a window that sat too low on screen.
    private func centerWindowOnCursorScreen(_ window: NSWindow) {
        let targetScreen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main

        guard let targetScreen else { return }

        let screenVisibleFrame = targetScreen.visibleFrame
        let outerWindowFrame = window.frame  // already includes titlebar at this point

        let windowOriginX = screenVisibleFrame.midX - (outerWindowFrame.width / 2)
        // Bias 6% above the screen's vertical center. AppKit uses a
        // bottom-left origin, so a *higher* y-origin = visually higher.
        let verticalBiasOffset = screenVisibleFrame.height * 0.06
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

    /// Hide the window instead of fully tearing it down on close, so
    /// re-opening it is instant and the transcript persists.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
