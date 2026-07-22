//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with companion voice controls.
//

import Combine
import ServiceManagement
import Sparkle
import SwiftUI

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

/// Manages the companion lifecycle: creates the menu bar panel and starts
/// the companion voice pipeline on launch.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private let companionManager = CompanionManager()
    private var sparkleUpdaterController: SPUStandardUpdaterController?
    private var pendingAuthenticationURLs: [URL] = []
    private var hasFinishedLaunching = false
    private var authenticationStateSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 Sticky: Starting...")
        print("🎯 Sticky: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        // Apply the user's persisted theme before any window is built so
        // every NSWindow / NSPanel inherits the right NSAppearance from
        // birth instead of flashing the default and re-rendering.
        ThemeManager.shared.applyAppearanceToRunningApp()

        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)
        observeAuthenticationState()
        AuthenticationManager.shared.configure()
        hasFinishedLaunching = true
        handleAuthenticationURLs(pendingAuthenticationURLs)
        pendingAuthenticationURLs.removeAll()
        registerAsLoginItemIfNeeded()
        // startSparkleUpdater()
    }

    func applicationWillTerminate(_ notification: Notification) {
        authenticationStateSubscription?.cancel()
        companionManager.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard hasFinishedLaunching else {
            pendingAuthenticationURLs.append(contentsOf: urls)
            return
        }

        handleAuthenticationURLs(urls)
    }

    private func handleAuthenticationURLs(_ urls: [URL]) {
        for url in urls {
            guard AuthenticationManager.isSupportedCallbackURL(url) else { continue }
            DashboardWindowController.shared.setCompanionManager(companionManager)
            DashboardWindowController.shared.showDashboardWindow()
            AuthenticationManager.shared.handleIncomingURL(url)
        }
    }

    private func observeAuthenticationState() {
        authenticationStateSubscription = AuthenticationManager.shared.$authenticationState
            .combineLatest(AuthenticationManager.shared.$productionDataReadiness)
            .combineLatest(AuthenticationManager.shared.$authGeneration)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authenticationAndReadiness, _ in
                let authenticationState = authenticationAndReadiness.0
                self?.applyAuthenticationState(authenticationState)
            }
    }

    private func applyAuthenticationState(
        _ authenticationState: ApplicationAuthenticationState
    ) {
        switch authenticationState {
        case .authenticated:
            if AuthenticationManager.shared.canAccessProductionFeatures {
                companionManager.start()
                if !companionManager.hasCompletedOnboarding
                    || !companionManager.allPermissionsGranted {
                    menuBarPanelManager?.showPanelOnLaunch()
                }
            } else {
                companionManager.stop()
                menuBarPanelManager?.handleAuthenticationLoss()
                menuBarPanelManager?.showPanelOnLaunch()
            }
        case .configurationMissing,
             .loading,
             .signedOut,
             .signingOut,
             .signOutFailure,
             .failure:
            companionManager.stop()
            menuBarPanelManager?.handleAuthenticationLoss()

            if authenticationState != .loading
                && authenticationState != .signingOut {
                menuBarPanelManager?.showPanelOnLaunch()
            }
        }
    }

    /// Registers the app as a login item so it launches automatically on
    /// startup. Uses SMAppService which shows the app in System Settings >
    /// General > Login Items, letting the user toggle it off if they want.
    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                print("🎯 Sticky: Registered as login item")
            } catch {
                print("⚠️ Sticky: Failed to register as login item: \(error)")
            }
        }
    }

    private func startSparkleUpdater() {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.sparkleUpdaterController = updaterController

        do {
            try updaterController.updater.start()
        } catch {
            print("⚠️ Sticky: Sparkle updater failed to start: \(error)")
        }
    }
}
