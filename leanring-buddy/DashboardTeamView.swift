//
//  DashboardTeamView.swift
//  leanring-buddy
//
//  "Team" tab — shows every teammate as a card with their main role
//  as a subtag, plus a (mocked) Invite Teammate button. Clicking a
//  teammate jumps to that persona's read-only detail view in the
//  Tastes tab. Inviting just shows a fake "Invitation sent" toast —
//  there's no real team backend in the hackathon MVP.
//

import SwiftUI

struct DashboardTeamView: View {
    @StateObject private var dashboardNavigationState = DashboardNavigationState.shared

    @State private var pendingInviteEmailText: String = ""
    @State private var showingInviteFormCard: Bool = false
    @State private var lastInviteSentToEmail: String? = nil

    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "TEAM",
                title: "Your team's lenses.",
                subtitle: "Every teammate's persona is here — their main role is their subtag. Click any card to read their taste."
            ) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingInviteFormCard.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Invite teammate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
            }

            if showingInviteFormCard {
                inviteFormCard
            }

            if let lastInviteSentToEmail {
                inviteSentToast(emailAddress: lastInviteSentToEmail)
            }

            teammatesList
        }
    }

    private var inviteFormCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            Text("Send a Sticky invite")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Text("Enter an email — we'll fake-send an invitation. No real backend, just a hackathon demo.")
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                TextField("teammate@email.com", text: $pendingInviteEmailText)
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

                Button(action: sendMockInvite) {
                    Text("Send")
                        .font(.system(size: 12, weight: .semibold))
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                .disabled(pendingInviteEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(pendingInviteEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
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

    private func inviteSentToast(emailAddress: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text("Invitation sent to \(emailAddress).")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Spacer()
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private var teammatesList: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("\(PersonaStore.availableTeammates.count) teammates")

            VStack(spacing: ElevenLabsBrand.Spacing.sm) {
                // Surface the local user as the first card too — handy
                // for a Team page that's a directory rather than just
                // an "everyone else" list.
                if let yourBundle = PersonaStore.myCurrentBundle() {
                    teammateRow(forBundle: yourBundle, isYou: true)
                }
                ForEach(PersonaStore.availableTeammates) { teammateBundle in
                    teammateRow(forBundle: teammateBundle, isYou: false)
                }
            }
        }
    }

    private func teammateRow(forBundle bundle: PersonaBundle, isYou: Bool) -> some View {
        Button(action: {
            // Jump to the Tastes tab pinned to this person.
            dashboardNavigationState.focusedPersonaId = bundle.id
            dashboardNavigationState.selectedSection = .tastes
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.md) {
                PersonaAvatarView(avatar: bundle.avatar, diameter: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(bundle.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ElevenLabsBrand.Colors.ink)

                        if isYou {
                            Text("YOU")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.4)
                                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(ElevenLabsBrand.Colors.paperRecessed)
                                )
                        }
                    }

                    // Subtag = main role / skill — exactly what the
                    // user asked for ("teammates subtag should be
                    // there main role/skill").
                    if let role = bundle.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    }

                    Text("\(bundle.taste.principles.count) principle\(bundle.taste.principles.count == 1 ? "" : "s") · \(domainsSummary(forBundle: bundle))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
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

    private func domainsSummary(forBundle bundle: PersonaBundle) -> String {
        let domainsPresent = Set(bundle.taste.principles.map { $0.domain })
        let labels: [String] = [.general, .design, .writing, .code]
            .filter { domainsPresent.contains($0) }
            .map { domainName($0) }
        return labels.isEmpty ? "no taste yet" : labels.joined(separator: ", ")
    }

    private func domainName(_ domain: TasteDomain) -> String {
        switch domain {
        case .general: return "General"
        case .design:  return "Design"
        case .writing: return "Writing"
        case .code:    return "Code"
        }
    }

    private func sendMockInvite() {
        let trimmed = pendingInviteEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastInviteSentToEmail = trimmed
        pendingInviteEmailText = ""
        withAnimation(.easeInOut(duration: 0.18)) {
            showingInviteFormCard = false
        }
    }
}
