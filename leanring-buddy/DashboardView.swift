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
            if let companionManager {
                DashboardSettingsView(companionManager: companionManager)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    Text("Settings unavailable")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text("Open Sticky from the menu bar first.")
                        .font(.system(size: 12))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ElevenLabsBrand.Colors.paper)
            }
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

            workspaceProvisioningContent

            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                if authenticationManager.canRetryWorkspaceProvisioning {
                    Button("Retry workspace setup") {
                        authenticationManager.retryProvisioning()
                    }
                    .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                    .pointerCursor()
                }

                Button("Sign out") {
                    authenticationManager.signOut()
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.98))
                .pointerCursor()
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ElevenLabsBrand.Spacing.xl)
    }

    @ViewBuilder
    private var workspaceProvisioningContent: some View {
        switch authenticationManager.workspaceProvisioningState {
        case .idle, .provisioning:
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                ProgressView()
                Text("Setting up your personal workspace…")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }
        case .ready(let snapshot):
            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.xs) {
                ElevenLabsEyebrow("PERSONAL WORKSPACE")
                Text(snapshot.workspaceName)
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 22))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(snapshot.personaSetupState.statusText)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                Text("Provisioning is complete. Ask, Teach, personas, chat, memory, tastes, and team data remain unavailable until production storage is connected.")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failure(let message, let attempt):
            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.xs) {
                Text("Workspace setup attempt \(attempt) failed.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(message)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DashboardSignInView: View {
    private static let clerkTheme = ClerkTheme(
        colors: .init(
            primary: ElevenLabsBrand.Colors.ink,
            background: ElevenLabsBrand.Colors.paper,
            input: ElevenLabsBrand.Colors.card,
            danger: DS.Colors.destructive,
            success: DS.Colors.success,
            warning: DS.Colors.warning,
            foreground: ElevenLabsBrand.Colors.ink,
            mutedForeground: ElevenLabsBrand.Colors.inkSecondary,
            primaryForeground: ElevenLabsBrand.Colors.paper,
            inputForeground: ElevenLabsBrand.Colors.ink,
            neutral: ElevenLabsBrand.Colors.inkTertiary,
            ring: ElevenLabsBrand.Colors.ink,
            muted: ElevenLabsBrand.Colors.paperRecessed,
            secondaryButtonBackground: ElevenLabsBrand.Colors.card,
            secondaryButtonForeground: ElevenLabsBrand.Colors.ink,
            shadow: .clear,
            border: ElevenLabsBrand.Colors.ink
        ),
        design: .init(borderRadius: ElevenLabsBrand.Radius.card)
    )

    var body: some View {
        AuthView(isDismissible: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.clerkTheme, Self.clerkTheme)
            .background(ElevenLabsBrand.Colors.paper)
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
