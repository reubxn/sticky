//
//  ThemeManager.swift
//  leanring-buddy
//
//  Drives the app's light / dark / system appearance. Owns the single
//  source of truth for the user's preferred theme mode, persists it to
//  UserDefaults, and applies it to `NSApp.appearance` so every window
//  and AppKit-backed surface (menu bar panel, dashboard, chat) flips
//  in lockstep.
//
//  Default mode is `.system` so a fresh install follows the user's
//  macOS appearance setting until they pick a side. Toggles in the
//  menu bar panel and Dashboard Settings both read/write through
//  `ThemeManager.shared.mode` and observe `objectWillChange` for live
//  updates.
//

import AppKit
import Combine
import SwiftUI

/// User-selectable theme preference. Persisted via the raw string so a
/// future migration can read the old value cleanly.
enum AppThemeMode: String, CaseIterable, Codable, Identifiable {
    /// Follow the macOS system appearance — the default. Flips
    /// automatically if the user toggles light/dark in System Settings.
    case system
    /// Force the editorial paper-and-ink palette regardless of system.
    case light
    /// Force the warm dark variant of the paper palette regardless of
    /// system.
    case dark

    var id: String { rawValue }

    /// Short human label shown in the picker UI.
    var displayLabel: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// SF Symbol name used by the picker chips and the menu bar
    /// toggle so the three options read at a glance.
    var sfSymbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let userDefaultsKey = "stickyAppThemeMode"

    /// The user's chosen mode. Writing this value persists the
    /// selection to `UserDefaults` and immediately reapplies the
    /// appearance to `NSApp` so all windows update.
    @Published var mode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.userDefaultsKey)
            // User-initiated change — cross-fade the visible windows so
            // the flip doesn't feel like a hard cut.
            applyAppearanceToRunningApp(animated: true)
        }
    }

    private init() {
        if let storedRawValue = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let storedMode = AppThemeMode(rawValue: storedRawValue) {
            self.mode = storedMode
        } else {
            self.mode = .system
        }
    }

    /// Applies the persisted preference to `NSApp.appearance`. Called
    /// from `applicationDidFinishLaunching` so every window created
    /// thereafter inherits the right look without each call site having
    /// to set its own `appearance`. Re-invoked whenever `mode` changes.
    ///
    /// When `animated` is true, every visible window is snapshotted, the
    /// snapshot is overlaid on top of the window, the appearance flip
    /// happens, and then the snapshots fade out — so the user sees a
    /// soft cross-fade between the old and new looks instead of a hard
    /// instant cut. Launch-time application of the persisted theme uses
    /// `animated: false` because there is no "previous" look to fade
    /// from.
    func applyAppearanceToRunningApp(animated: Bool = false) {
        guard animated else {
            applyAppearanceImmediately()
            return
        }

        // Capture a snapshot of every visible window's contentView and
        // pin it on top of that contentView. The snapshot is just an
        // image of the *current* appearance; once we change
        // `NSApp.appearance` below, AppKit will repaint the real views
        // underneath the snapshot in the new appearance, and the
        // snapshot fade will reveal that new look gradually.
        let snapshotOverlays: [NSView] = NSApp.windows.compactMap { window in
            guard window.isVisible,
                  let contentView = window.contentView,
                  contentView.bounds.width > 0,
                  contentView.bounds.height > 0
            else { return nil }
            return Self.installAppearanceSnapshotOverlay(on: contentView)
        }

        applyAppearanceImmediately()

        // If we couldn't capture anything (e.g. no visible windows),
        // skip the animation block entirely.
        guard !snapshotOverlays.isEmpty else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for snapshotOverlay in snapshotOverlays {
                snapshotOverlay.animator().alphaValue = 0
            }
        }, completionHandler: {
            for snapshotOverlay in snapshotOverlays {
                snapshotOverlay.removeFromSuperview()
            }
        })
    }

    /// Sets `NSApp.appearance` to match `mode` with no transition. Used
    /// at launch and as the underlying primitive for the animated path.
    private func applyAppearanceImmediately() {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Renders `contentView` to a bitmap, wraps it in a click-through
    /// overlay view, and pins the overlay to fill `contentView`. Returns
    /// the overlay so the caller can fade it out and remove it.
    /// Returns nil if the bitmap couldn't be created.
    private static func installAppearanceSnapshotOverlay(on contentView: NSView) -> NSView? {
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        else { return nil }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)

        let snapshotImage = NSImage(size: contentView.bounds.size)
        snapshotImage.addRepresentation(bitmap)

        let overlay = AppearanceTransitionSnapshotView(frame: contentView.bounds)
        overlay.image = snapshotImage
        overlay.imageScaling = .scaleAxesIndependently
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        // Position above all sibling subviews so it covers the live
        // contentView during the fade.
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        return overlay
    }
}

/// NSImageView subclass used purely to host the cross-fade snapshot.
/// Returns nil from `hitTest` so that even though it sits on top of the
/// real window content during the ~0.35s fade, mouse clicks pass
/// through to the live views underneath.
private final class AppearanceTransitionSnapshotView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
