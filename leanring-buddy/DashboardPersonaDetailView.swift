//
//  DashboardPersonaDetailView.swift
//  leanring-buddy
//
//  Detail view for one persona — your own (editable) or a teammate's
//  (read-only). Header with the persona's avatar, name, role, and
//  voice; Soul prose section; Taste section with principles grouped
//  by domain.
//
//  Editable mode adds a trash icon next to each principle (delete
//  via TasteProfileStore for personal taste) and a "Refresh from
//  TASTE.md" button. We deliberately don't add an "edit principle"
//  flow here — the file is the source of truth, and editing prose
//  inline against a markdown file is too easy to break. Deletes are
//  a clean, one-click operation that round-trips correctly.
//

import SwiftUI

struct DashboardPersonaDetailView: View {
    let personaBundle: PersonaBundle

    /// True when this is the local user's own persona — enables the
    /// principle delete buttons and the edit hints. Teammate views
    /// show the same data but with no destructive actions.
    let isEditable: Bool

    let onClose: () -> Void

    /// Local copy of the bundle so we can re-render after a delete
    /// without waiting for `PersonaStore.myCurrentBundle()` to refresh.
    @State private var displayedBundle: PersonaBundle

    init(personaBundle: PersonaBundle, isEditable: Bool, onClose: @escaping () -> Void) {
        self.personaBundle = personaBundle
        self.isEditable = isEditable
        self.onClose = onClose
        _displayedBundle = State(initialValue: personaBundle)
    }

    var body: some View {
        DashboardContentScrollContainer {
            backLink

            personaHeaderCard

            if !displayedBundle.soul.isEmpty {
                soulSection
            }

            tasteSection
        }
    }

    // MARK: - Back link

    private var backLink: some View {
        Button(action: onClose) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text("All tastes")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .pointerCursor()
    }

    // MARK: - Header card

    private var personaHeaderCard: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.md) {
            PersonaAvatarView(avatar: displayedBundle.avatar, diameter: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayedBundle.displayName)
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 28))
                    .tracking(-0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                if let role = displayedBundle.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }

                HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                    metadataChip(label: "ID", value: displayedBundle.id)
                    if !displayedBundle.voiceId.isEmpty {
                        metadataChip(label: "Voice", value: voiceDisplayName(forId: displayedBundle.voiceId))
                    }
                    metadataChip(label: "Accent", value: displayedBundle.accentColorHex)
                }
                .padding(.top, 4)
            }

            Spacer()

            if !isEditable {
                Text("Read only")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(ElevenLabsBrand.Colors.paperRecessed)
                    )
                    .overlay(
                        Capsule().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
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

    private func metadataChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(ElevenLabsBrand.Colors.paperRecessed)
        )
    }

    private func voiceDisplayName(forId voiceId: String) -> String {
        ElevenLabsTTSClient.freeVoices.first(where: { $0.id == voiceId })?.displayName ?? voiceId
    }

    // MARK: - Soul section

    private var soulSection: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("SOUL")

            Text(displayedBundle.soul)
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(ElevenLabsBrand.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Taste section (principles by domain)

    private var tasteSection: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("TASTE — \(displayedBundle.taste.principles.count) principles")

            if displayedBundle.taste.principles.isEmpty {
                emptyTasteState
            } else {
                let domainOrder: [TasteDomain] = [.general, .design, .writing, .code]
                ForEach(domainOrder, id: \.self) { domain in
                    let principlesInDomain = displayedBundle.taste.principles.filter { $0.domain == domain }
                    if !principlesInDomain.isEmpty {
                        domainGroup(domain: domain, principles: principlesInDomain)
                    }
                }
            }
        }
    }

    private var emptyTasteState: some View {
        Text("No principles yet. Use Teach mode to start adding some.")
            .font(ElevenLabsBrand.Typography.body)
            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            .padding(ElevenLabsBrand.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.paperRecessed)
            )
    }

    private func domainGroup(domain: TasteDomain, principles: [TastePrinciple]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(domainDisplayName(domain).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            VStack(spacing: 8) {
                ForEach(principles) { principle in
                    principleRow(principle)
                }
            }
        }
    }

    private func principleRow(_ principle: TastePrinciple) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
                Text(principle.statement)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if isEditable {
                    Button(action: {
                        deletePrinciple(principle)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    }
                    .buttonStyle(InteractivePressStyle(pressScale: 0.92))
                    .pointerCursor()
                    .nativeTooltip("Remove this principle")
                }
            }

            if let firstEvidence = principle.evidence.first, !firstEvidence.isEmpty {
                Text(firstEvidence)
                    .font(.system(size: 12))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !principle.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(principle.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.3)
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(ElevenLabsBrand.Colors.paperRecessed)
                            )
                    }
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

    private func domainDisplayName(_ domain: TasteDomain) -> String {
        switch domain {
        case .general: return "General"
        case .design:  return "Design"
        case .writing: return "Writing"
        case .code:    return "Code"
        }
    }

    // MARK: - Mutations

    /// Deletes a principle from the local user's taste profile. Only
    /// reachable when `isEditable == true` (i.e. the persona being
    /// shown is the local user's own bundle). Updates the on-disk
    /// JSON profile via TasteProfileStore and re-renders by removing
    /// from the local bundle copy.
    private func deletePrinciple(_ principle: TastePrinciple) {
        guard isEditable else { return }
        do {
            try TasteProfileStore.deletePrinciple(id: principle.id)
        } catch {
            print("⚠️ DashboardPersonaDetailView: delete failed: \(error)")
        }

        var updatedTaste = displayedBundle.taste
        updatedTaste.principles.removeAll(where: { $0.id == principle.id })
        displayedBundle = PersonaBundle(
            id: displayedBundle.id,
            displayName: displayedBundle.displayName,
            role: displayedBundle.role,
            avatar: displayedBundle.avatar,
            accentColorHex: displayedBundle.accentColorHex,
            soul: displayedBundle.soul,
            voiceId: displayedBundle.voiceId,
            taste: updatedTaste
        )
    }
}
