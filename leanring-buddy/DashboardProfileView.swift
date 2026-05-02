//
//  DashboardProfileView.swift
//  leanring-buddy
//
//  "Profile" tab — the one place the user edits their own identity:
//  display name, role/skill, voice. Plus an Export TASTE.md button
//  (writes the user's personal taste profile as TASTE.md, the
//  filename was an explicit ask), and a Sign Out button at the
//  bottom. Voice changes persist via UserDefaults the same way the
//  mini panel's voice picker already does.
//

import SwiftUI

struct DashboardProfileView: View {
    @StateObject private var dashboardMockAuthState = DashboardMockAuthState.shared

    /// Reading the personal taste profile lazily so the export button
    /// always has the most recent version (a teach-mode save while the
    /// dashboard is open should be reflected immediately).
    @State private var didJustExportTasteFile: Bool = false

    /// Local working copies of the editable fields. Bound to the
    /// shared mock auth store via the .onChange handlers below — we
    /// don't bind directly so the user can type freely without each
    /// keystroke being persisted.
    @State private var draftDisplayName: String = ""
    @State private var draftRole: String = ""

    /// Selected voice id pulled from UserDefaults (the same key the
    /// mini panel's picker writes to). nil means "default Sticky
    /// voice". Picker is rendered as a list of all free ElevenLabs
    /// voices.
    @State private var draftVoiceId: String?

    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "PROFILE",
                title: "Your Sticky identity.",
                subtitle: "Edit your display name, role, and voice. Export your taste as TASTE.md to share."
            )

            identityCard

            voiceCard

            tasteExportCard

            signOutCard
        }
        .onAppear { loadDraftValuesFromAuthState() }
    }

    // MARK: - Identity card

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("IDENTITY")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                fieldLabel("Display name")
                TextField("Your name", text: $draftDisplayName)
                    .textFieldStyle(.plain)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.sm)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ElevenLabsBrand.Colors.paperRecessed)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                    )

                fieldLabel("Role / main skill")
                TextField("Designer, builder, writer…", text: $draftRole)
                    .textFieldStyle(.plain)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.sm)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ElevenLabsBrand.Colors.paperRecessed)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                    )

                fieldLabel("Email")
                Text(dashboardMockAuthState.email.isEmpty ? "Not signed in with email yet." : dashboardMockAuthState.email)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.sm)
                    .padding(.vertical, 8)

                HStack {
                    Spacer()
                    Button(action: saveIdentityChanges) {
                        Text("Save")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                    .disabled(!hasUnsavedIdentityChanges)
                    .opacity(hasUnsavedIdentityChanges ? 1.0 : 0.4)
                }
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
    }

    private var hasUnsavedIdentityChanges: Bool {
        draftDisplayName != dashboardMockAuthState.displayName
            || draftRole != dashboardMockAuthState.role
    }

    private func saveIdentityChanges() {
        dashboardMockAuthState.displayName = draftDisplayName
        dashboardMockAuthState.role = draftRole
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
    }

    // MARK: - Voice card

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("VOICE")

            Text("Picks the ElevenLabs voice Sticky uses when speaking back. Saves on selection.")
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            VStack(spacing: 6) {
                voiceRow(voiceId: nil, displayName: "Sticky default", descriptor: "Bundled voice")

                ForEach(ElevenLabsTTSClient.freeVoices) { freeVoice in
                    voiceRow(
                        voiceId: freeVoice.id,
                        displayName: freeVoice.displayName,
                        descriptor: freeVoice.descriptor
                    )
                }
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
    }

    private func voiceRow(voiceId: String?, displayName: String, descriptor: String) -> some View {
        let isSelected = (voiceId == draftVoiceId)
        return Button(action: {
            draftVoiceId = voiceId
            // Persist immediately to the same UserDefaults key the
            // mini panel's voice picker reads/writes.
            UserDefaults.standard.set(voiceId, forKey: "selectedElevenLabsVoiceID")
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text(descriptor)
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ElevenLabsBrand.Colors.paperRecessed : Color.clear)
            )
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
    }

    // MARK: - TASTE.md export card

    private var tasteExportCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("EXPORT")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                Text("Export your taste as TASTE.md")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                Text("Writes a markdown file with your soul + every approved principle, grouped by domain. The file is named TASTE.md so it drops cleanly into a personas folder.")
                    .font(.system(size: 12))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(action: exportTasteAsMarkdown) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .bold))
                            Text("Download TASTE.md")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .elevenLabsPrimaryButtonStyle(isFullWidth: false)

                    if didJustExportTasteFile {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Exported")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    }
                }
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
    }

    private func exportTasteAsMarkdown() {
        let personalProfile: TasteProfile = {
            do {
                return try TasteProfileStore.loadProfile()
            } catch {
                return TasteProfile(userId: PersonaStore.myPersonaId, principles: [], updatedAt: Date())
            }
        }()

        // Prefer the user's local persona bundle metadata so the
        // exported TASTE.md has the right voice / accent / role
        // baked in rather than blank metadata.
        let localBundle = PersonaStore.myOwnBundle

        DashboardTasteMarkdownExporter.exportPersonalProfileAsMarkdown(
            personalProfile,
            displayName: localBundle?.displayName ?? dashboardMockAuthState.displayName,
            role: localBundle?.role ?? dashboardMockAuthState.role,
            accentHex: localBundle?.accentColorHex,
            voiceId: localBundle?.voiceId
        )

        // Show the small "Exported" confirmation — clear after a moment.
        didJustExportTasteFile = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didJustExportTasteFile = false
        }
    }

    // MARK: - Sign-out card

    private var signOutCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("SESSION")

            HStack(spacing: ElevenLabsBrand.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in as \(dashboardMockAuthState.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text("Mock sign-in — clicking out signs you out of the dashboard only.")
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }

                Spacer()

                Button(action: { dashboardMockAuthState.signOut() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Sign out")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
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
    }

    // MARK: - State sync

    private func loadDraftValuesFromAuthState() {
        draftDisplayName = dashboardMockAuthState.displayName
        draftRole = dashboardMockAuthState.role
        draftVoiceId = UserDefaults.standard.string(forKey: "selectedElevenLabsVoiceID")
    }
}
