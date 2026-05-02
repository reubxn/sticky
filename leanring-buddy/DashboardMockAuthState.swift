//
//  DashboardMockAuthState.swift
//  leanring-buddy
//
//  Fake sign-in state for the Dashboard window. Hackathon MVP: no real
//  auth, no backend, no password — just a UserDefaults-backed flag and
//  a display name so Profile / Sign-out / Sign-in flows have something
//  to bind to. The `isSignedIn` flag defaults to true on first launch
//  so the dashboard isn't perpetually showing a sign-in wall to a
//  single-user demo build.
//

import Combine
import Foundation

/// Persisted "are we signed in" + "who are we" state for the Dashboard.
/// Single source of truth so every dashboard subview can react to a
/// sign-out by collapsing to the sign-in screen.
@MainActor
final class DashboardMockAuthState: ObservableObject {

    /// Shared instance — the dashboard is a singleton window so a
    /// shared store keeps `ProfileDashboardView` and the sidebar's
    /// sign-out chip reading the same value.
    static let shared = DashboardMockAuthState()

    private static let isSignedInDefaultsKey = "dashboardMockIsSignedIn"
    private static let displayNameDefaultsKey = "dashboardMockDisplayName"
    private static let roleDefaultsKey = "dashboardMockRole"
    private static let emailDefaultsKey = "dashboardMockEmail"

    /// True while the user is "signed in". Defaults to true on first
    /// launch so the demo doesn't open into an empty sign-in wall.
    @Published var isSignedIn: Bool {
        didSet {
            UserDefaults.standard.set(isSignedIn, forKey: Self.isSignedInDefaultsKey)
        }
    }

    /// Friendly display name shown in the sidebar chip and Profile
    /// header. Defaults to the local persona's display name (Reuban)
    /// so it feels personalised on first open.
    @Published var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: Self.displayNameDefaultsKey)
        }
    }

    /// Short role / skill tag — shown next to the name in the sidebar
    /// and used as the "subtag" on team member rows so teammates can
    /// see what someone's main lens is at a glance.
    @Published var role: String {
        didSet {
            UserDefaults.standard.set(role, forKey: Self.roleDefaultsKey)
        }
    }

    /// Email address — shown in Profile, used on the (mocked) sign-in
    /// screen as the only credential field.
    @Published var email: String {
        didSet {
            UserDefaults.standard.set(email, forKey: Self.emailDefaultsKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard

        // Honour an explicit `false` from a previous sign-out, but
        // default to `true` on a fresh install so the dashboard opens
        // ready to use.
        if defaults.object(forKey: Self.isSignedInDefaultsKey) != nil {
            self.isSignedIn = defaults.bool(forKey: Self.isSignedInDefaultsKey)
        } else {
            self.isSignedIn = true
        }

        // Default display name pulls from the local persona bundle if
        // we can read it — otherwise a generic fallback. This makes the
        // first-launch experience feel personalised.
        let bundledDisplayName = PersonaStore.myOwnBundle?.displayName ?? "You"
        self.displayName = defaults.string(forKey: Self.displayNameDefaultsKey) ?? bundledDisplayName

        let bundledRole = PersonaStore.myOwnBundle?.role ?? "Maker"
        self.role = defaults.string(forKey: Self.roleDefaultsKey) ?? bundledRole

        self.email = defaults.string(forKey: Self.emailDefaultsKey) ?? ""
    }

    // MARK: - Actions

    func signIn(emailAddress: String) {
        // Mock — accept anything non-empty. Persist the email so the
        // Profile page shows it back.
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.email = trimmed
        self.isSignedIn = true
    }

    func signOut() {
        self.isSignedIn = false
    }
}
