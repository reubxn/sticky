//
//  DashboardView.swift
//  leanring-buddy
//
//  Root SwiftUI view for the Dashboard window. Two-column layout:
//  fixed-width sidebar on the left (nav + signed-in user chip), main
//  content on the right (one of six section views, switched via
//  `DashboardNavigationState.selectedSection`).
//
//  When Convex has not authenticated the Clerk session, the sidebar
//  collapses and the main pane shows Clerk's native sign-in UI.
//

import ClerkKitUI
import SwiftUI

struct DashboardView: View {
    /// Optional shared CompanionManager. Threaded in by
    /// `DashboardWindowController` from the menu bar layer so the live
    /// Chat and Memory tabs can share persona, taste profile, and model
    /// state with the menu bar and floating chat window. Nil in
    /// previews — those tabs render a small "open the menu bar first"
    /// fallback when CompanionManager isn't available.
    let companionManager: CompanionManager?

    @StateObject private var dashboardNavigationState = DashboardNavigationState.shared
    @StateObject private var authenticationManager = AuthenticationManager.shared

    init(companionManager: CompanionManager? = nil) {
        self.companionManager = companionManager
    }

    var body: some View {
        Group {
            switch authenticationManager.authenticationState {
            case .authenticated:
                if authenticationManager.canAccessProductionFeatures {
                    signedInDashboardLayout
                } else {
                    DashboardAccountConnectedView()
                }
            case .signedOut:
                DashboardSignInView()
            case .loading:
                ProgressView("Checking your session…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signingOut:
                ProgressView("Signing out…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .configurationMissing(let message):
                DashboardAuthenticationFailureView(message: message)
            case .signOutFailure(let message):
                DashboardAuthenticationFailureView(message: message)
            case .failure(let message):
                DashboardAuthenticationFailureView(message: message)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(ElevenLabsBrand.Colors.paper.ignoresSafeArea())
    }

    private var signedInDashboardLayout: some View {
        HStack(spacing: 0) {
            DashboardSidebar(
                selectedSection: $dashboardNavigationState.selectedSection
            )
            .frame(width: 220)

            Divider()
                .background(ElevenLabsBrand.Colors.hairline)

            currentSectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Routes to the right section view based on the selected sidebar
    /// item. Each section is its own SwiftUI file so they can grow
    /// independently without bloating this router.
    @ViewBuilder
    private var currentSectionContent: some View {
        switch dashboardNavigationState.selectedSection {
        case .chat:
            DashboardLiveChatView(companionManager: companionManager)
        case .memory:
            DashboardMemoryView(companionManager: companionManager)
        case .tastes:
            DashboardTastesView()
        case .team:
            DashboardTeamView()
        case .profile:
            DashboardProfileView(companionManager: companionManager)
        case .settings:
            DashboardSettingsView()
        }
    }
}

private struct DashboardAccountConnectedView: View {
    @StateObject private var authenticationManager = AuthenticationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            ElevenLabsEyebrow("ACCOUNT CONNECTED")

            Text("You're signed in.")
                .font(ElevenLabsBrand.Typography.cardTitle(size: 30))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.xs) {
                Text(authenticationManager.clerkDisplayName ?? "Signed-in user")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                if !authenticationManager.email.isEmpty {
                    Text(authenticationManager.email)
                        .font(ElevenLabsBrand.Typography.body)
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }
            }

            Text("Workspace provisioning and production storage arrive in the next slice. Until then, Ask, Teach, personas, chat, memory, tastes, and team data stay unavailable so no legacy local data can cross accounts.")
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Sign out") {
                authenticationManager.signOut()
            }
            .elevenLabsPrimaryButtonStyle(isFullWidth: false)
            .pointerCursor()
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ElevenLabsBrand.Spacing.xl)
    }
}

struct DashboardSignInView: View {
    var body: some View {
        AuthView(isDismissible: false)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, ElevenLabsBrand.Spacing.xl)
    }
}

private struct DashboardAuthenticationFailureView: View {
    let message: String
    @StateObject private var authenticationManager = AuthenticationManager.shared

    var body: some View {
        VStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            Text("Authentication needs attention.")
                .font(ElevenLabsBrand.Typography.cardTitle(size: 22))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text(message)
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                authenticationManager.retry()
            }
            .elevenLabsPrimaryButtonStyle(isFullWidth: false)
            .pointerCursor()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ElevenLabsBrand.Spacing.xl)
    }
}
