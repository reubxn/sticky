//
//  DashboardTastesView.swift
//  leanring-buddy
//
//  Dashboard tab that shows every persona ("taste") in the system —
//  the user's own first, then teammates. Per the user's instruction
//  these are renamed "Tastes" in the surface copy even though the
//  underlying types are still PersonaBundle.
//
//  Two card variants:
//  - "Your taste" — opens a full editor (DashboardPersonaDetailView
//    edit mode) with editable principle list + soul.
//  - Teammate taste — opens the same detail view in read-only mode.
//
//  When the mini panel asks the dashboard to open pinned to a
//  specific persona (`DashboardNavigationState.focusedPersonaId`),
//  this view auto-pushes the detail view for that persona on appear.
//

import SwiftUI

struct DashboardTastesView: View {
    @StateObject private var dashboardNavigationState = DashboardNavigationState.shared
    @ObservedObject private var authenticationManager = AuthenticationManager.shared

    /// Drives whether we're showing the list of personas or one
    /// persona's detail view. The detail view is pushed as a sheet-
    /// like overlay rather than a NavigationStack push so the layout
    /// stays simple and the close button is always one click away.
    @State private var personaInDetailView: PersonaBundle? = nil

    var body: some View {
        Group {
            if let detailedPersona = personaInDetailView {
                DashboardPersonaDetailView(
                    personaBundle: detailedPersona,
                    isEditable: detailedPersona.id == PersonaStore.myPersonaId,
                    onClose: { personaInDetailView = nil }
                )
            } else {
                tastesListView
            }
        }
        .onAppear {
            // If the dashboard was opened with a focused persona id
            // (mini-panel click), jump straight into that detail view.
            // Defer the state mutation to the next runloop tick so we
            // don't update navigation state inside the same render
            // pass that's reading it.
            if let focusedId = dashboardNavigationState.focusedPersonaId,
               let bundle = personaBundle(forId: focusedId) {
                DispatchQueue.main.async {
                    personaInDetailView = bundle
                    dashboardNavigationState.focusedPersonaId = nil
                }
            }
        }
    }

    // MARK: - List view

    private var tastesListView: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "TASTES",
                title: "Your team's taste, all in one place.",
                subtitle: "Each taste is a person's soul, voice, and the notes Sticky has learned. Click yours to edit. Click a teammate to read."
            )

            yourTasteSection

            if !PersonaStore.availableTeammates.isEmpty {
                teammatesTasteSection
            }
        }
    }

    private var yourTasteSection: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("YOURS")

            if let yourBundle = PersonaStore.myCurrentBundle() {
                personaCard(forBundle: yourBundle, isYours: true)
            } else {
                Text("Your TASTE.md isn't loaded — add one at personas/\(PersonaStore.myPersonaId)/TASTE.md.")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }
        }
    }

    private var teammatesTasteSection: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("TEAM")

            VStack(spacing: ElevenLabsBrand.Spacing.sm) {
                ForEach(PersonaStore.availableTeammates) { teammateBundle in
                    personaCard(forBundle: teammateBundle, isYours: false)
                }
            }
        }
    }

    // MARK: - Persona card

    private func personaCard(forBundle bundle: PersonaBundle, isYours: Bool) -> some View {
        Button(action: {
            personaInDetailView = bundle
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.md) {
                PersonaAvatarView(
                    avatar: bundle.avatar,
                    diameter: 56,
                    uploadedImageOverridePath: PersonaStore.uploadedProfilePicturePath(forPersonaId: bundle.id)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)

                    if let role = bundle.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    }

                    Text("\(bundle.taste.principles.count) note\(bundle.taste.principles.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(isYours ? "Edit" : "View")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }
            .padding(ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
    }

    // MARK: - Helpers

    private func personaBundle(forId personaId: String) -> PersonaBundle? {
        if personaId == PersonaStore.myPersonaId {
            return PersonaStore.myCurrentBundle()
        }
        return PersonaStore.teammate(withId: personaId)
    }
}
