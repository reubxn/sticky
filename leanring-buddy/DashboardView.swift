//
//  DashboardView.swift
//  leanring-buddy
//
//  Root SwiftUI view for the Dashboard window. Two-column layout:
//  fixed-width sidebar on the left (nav + signed-in user chip), main
//  content on the right (one of six section views, switched via
//  `DashboardNavigationState.selectedSection`).
//
//  When the user is signed out (mock auth), the sidebar collapses and
//  the main pane shows a sign-in card. Signing in (mock — any non-
//  empty email) restores the full dashboard.
//

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
    @StateObject private var dashboardMockAuthState = DashboardMockAuthState.shared

    init(companionManager: CompanionManager? = nil) {
        self.companionManager = companionManager
    }

    var body: some View {
        Group {
            if dashboardMockAuthState.isSignedIn {
                signedInDashboardLayout
            } else {
                DashboardSignInView()
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

// MARK: - Sign-in screen (mock)

/// Shown when `DashboardMockAuthState.isSignedIn` is false. One field
/// (email), one button. Accepts any non-empty input — this is the
/// hackathon's fake auth, not real authentication.
struct DashboardSignInView: View {
    @StateObject private var dashboardMockAuthState = DashboardMockAuthState.shared
    @State private var emailInputText: String = ""

    var body: some View {
        VStack(spacing: ElevenLabsBrand.Spacing.lg) {
            Spacer()

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
                ElevenLabsEyebrow("WELCOME BACK")
                Text("Sign in to Sticky.")
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 28))
                    .tracking(-0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text("Mock sign-in for the hackathon demo — any email works.")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("you@email.com", text: $emailInputText)
                    .textFieldStyle(.plain)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                    .padding(.vertical, ElevenLabsBrand.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                            .fill(ElevenLabsBrand.Colors.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                            .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                    )

                Button(action: {
                    dashboardMockAuthState.signIn(emailAddress: emailInputText)
                }) {
                    Text("Sign in")
                }
                .elevenLabsPrimaryButtonStyle()
                .disabled(emailInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(emailInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
            }
            .frame(maxWidth: 360)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ElevenLabsBrand.Spacing.xl)
    }
}
