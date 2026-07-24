//
//  DashboardSidebar.swift
//  leanring-buddy
//
//  Left rail of the Dashboard: app wordmark at the top, vertical list
//  of section nav rows in the middle, signed-in user chip + sign-out
//  button at the bottom. The user chip is read-only here (you edit
//  your name/role in the Profile tab) — clicking sign out ends the
//  Clerk session and revokes Convex access.
//

import SwiftUI

struct DashboardSidebar: View {
    @Binding var selectedSection: DashboardSection
    @StateObject private var authenticationManager = AuthenticationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.top, 28)
                .padding(.bottom, ElevenLabsBrand.Spacing.md)

            Divider().background(ElevenLabsBrand.Colors.hairline)

            navigationList
                .padding(.vertical, ElevenLabsBrand.Spacing.sm)

            Spacer()

            Divider().background(ElevenLabsBrand.Colors.hairline)

            signedInUserChip
                .padding(.horizontal, ElevenLabsBrand.Spacing.md)
                .padding(.vertical, ElevenLabsBrand.Spacing.sm)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ElevenLabsBrand.Colors.paperRecessed)
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            StickyOrbGlyph(size: 18, color: ElevenLabsBrand.Colors.inkPure)

            Text("Sticky")
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkPure)

            Spacer()
        }
    }

    // MARK: - Navigation List

    private var navigationList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DashboardSection.allCases) { section in
                navigationRow(forSection: section)
            }
        }
    }

    private func navigationRow(forSection section: DashboardSection) -> some View {
        let isSelected = (selectedSection == section)
        return Button(action: {
            selectedSection = section
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                Image(systemName: section.iconSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.tasteAccent
                            : ElevenLabsBrand.Colors.inkSecondary
                    )

                Text(section.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.inkPure
                            : ElevenLabsBrand.Colors.inkSecondary
                    )

                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ElevenLabsBrand.Colors.card : Color.clear)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.sm - 4)
            )
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
    }

    // MARK: - Signed-in User Chip + Sign Out

    private var signedInUserChip: some View {
        HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            avatarForCurrentUser

            VStack(alignment: .leading, spacing: 2) {
                Text(authenticationManager.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkPure)
                    .lineLimit(1)

                Text(authenticationManager.localRole)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                authenticationManager.signOut()
            }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.92))
            .pointerCursor()
            .nativeTooltip("Sign out")
        }
    }

    /// Avatar for the signed-in user. Prefers a user-uploaded profile
    /// picture from the Profile tab, falls back to the local persona's
    /// avatar, then to initials over a gradient.
    @ViewBuilder
    private var avatarForCurrentUser: some View {
        if let localPersonaBundle = PersonaStore.myOwnBundle {
            PersonaAvatarView(
                avatar: localPersonaBundle.avatar,
                diameter: 32,
                uploadedImageOverridePath: authenticationManager.localProfilePicturePath
            )
        } else {
            Circle()
                .fill(ElevenLabsBrand.Colors.gradientSky)
                .overlay(
                    Text(initials(from: authenticationManager.displayName))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkPure)
                )
        }
    }

    private func initials(from displayName: String) -> String {
        let parts = displayName
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
