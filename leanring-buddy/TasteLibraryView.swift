//
//  TasteLibraryView.swift
//  leanring-buddy
//
//  The "Memory" window. Lists every TastePrinciple Sticky has learned,
//  grouped by domain (design / writing / code / general). Personal scope
//  is editable; Team scope is read-only and surfaces a hint that
//  team-profile.json is the source of truth.
//
//  Editorial styling — paper background, white cards, gradient swatches
//  to give each domain a recognizable identity. Lives in its own
//  NSWindow (TasteLibraryWindowController).
//

import AppKit
import SwiftUI

// MARK: - Domain → Brand Mapping
//
// Each taste domain maps to one of the brand's four mesh gradients so
// the four sections of the library read as visually distinct islands.
// The mapping is intentional, not algorithmic, so each domain has a
// memorable color identity even if more domains are added later.

private enum DomainBrand {
    static func gradient(for domain: TasteDomain) -> LinearGradient {
        switch domain {
        case .design:  return ElevenLabsBrand.Gradients.ember
        case .writing: return ElevenLabsBrand.Gradients.skyBlush
        case .code:    return ElevenLabsBrand.Gradients.cool
        case .general: return ElevenLabsBrand.Gradients.sunset
        }
    }

    static func displayLabel(for domain: TasteDomain) -> String {
        switch domain {
        case .design:  return "Design"
        case .writing: return "Writing"
        case .code:    return "Code"
        case .general: return "General"
        }
    }

    /// Stable order so the list doesn't reshuffle when principles are
    /// added or removed.
    static let stableDomainOrder: [TasteDomain] = [.design, .writing, .code, .general]
}

// MARK: - Library View

struct TasteLibraryView: View {
    @ObservedObject var companionManager: CompanionManager

    /// Which scope's principles are visible. Personal is editable; team
    /// is read-only.
    @State private var selectedLibraryScope: LibraryScope = .personal

    /// The principles shown in the list, refreshed from disk whenever the
    /// scope changes or the user mutates the profile.
    @State private var loadedPersonalProfile: TasteProfile = TasteProfile(
        userId: "local-user",
        principles: [],
        updatedAt: Date()
    )
    @State private var loadedTeamProfile: TeamTasteProfile? = nil

    /// Inline toast shown after Import succeeds. Auto-fades after 3s.
    @State private var importToastMessage: String? = nil

    /// Confirmation alert state for the Forget action. We hold the principle
    /// itself rather than just its id so the alert copy can quote the
    /// statement — much friendlier than "Forget this principle?".
    @State private var principlePendingDeletion: TastePrinciple? = nil

    enum LibraryScope: String, CaseIterable {
        case personal
        case team

        var displayLabel: String {
            switch self {
            case .personal: return "Personal"
            case .team:     return "Team"
            }
        }
    }

    var body: some View {
        ZStack {
            ElevenLabsBrand.Colors.paper
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                libraryHeader

                Rectangle()
                    .fill(ElevenLabsBrand.Colors.hairline)
                    .frame(height: 1)

                if selectedLibraryScope == .team {
                    teamReadOnlyBanner
                        .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                        .padding(.top, ElevenLabsBrand.Spacing.md)
                }

                if let importToastMessage {
                    importSuccessToast(message: importToastMessage)
                        .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                        .padding(.top, ElevenLabsBrand.Spacing.md)
                        .transition(.opacity)
                }

                principleScrollList
            }
        }
        .frame(width: 540, height: 660)
        .onAppear {
            refreshProfilesFromDisk()
        }
        .onChange(of: selectedLibraryScope) { _ in
            refreshProfilesFromDisk()
        }
        .alert(
            "Forget this note?",
            isPresented: deletionAlertBinding,
            presenting: principlePendingDeletion
        ) { principleAboutToBeDeleted in
            Button("Cancel", role: .cancel) {
                principlePendingDeletion = nil
            }
            Button("Forget", role: .destructive) {
                deletePrincipleNow(principleAboutToBeDeleted)
            }
        } message: { principleAboutToBeDeleted in
            Text("Sticky won't use this anymore:\n\n“\(principleAboutToBeDeleted.statement)”")
        }
    }

    // MARK: - Header
    //
    // Hero-style header: eyebrow, display headline, then a row of pill
    // tabs (Personal/Team) next to ghost pill buttons (Export/Import).
    // Reads like a magazine cover instead of a settings panel.

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            ElevenLabsEyebrow("MEMORY")

            Text(headlineText)
                .font(ElevenLabsBrand.Typography.hero(size: 26))
                .tracking(-0.5)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                scopePillTabs

                Spacer()

                exportButton
                importButton
            }
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
        .padding(.top, ElevenLabsBrand.Spacing.lg)
        .padding(.bottom, ElevenLabsBrand.Spacing.md)
    }

    private var headlineText: String {
        let count = principlesForCurrentScope().count
        if count == 0 {
            return "Nothing learned\nyet."
        }
        let noteNoun = count == 1 ? "note" : "notes"
        let scopeWord = selectedLibraryScope == .personal ? "your" : "the team's"
        return "\(count) \(noteNoun)\nabout \(scopeWord) taste."
    }

    private var scopePillTabs: some View {
        HStack(spacing: 6) {
            ForEach(LibraryScope.allCases, id: \.self) { scopeOption in
                scopePillTab(scope: scopeOption)
            }
        }
    }

    private func scopePillTab(scope scopeOption: LibraryScope) -> some View {
        let isSelected = selectedLibraryScope == scopeOption
        return Button(action: {
            selectedLibraryScope = scopeOption
        }) {
            Text(scopeOption.displayLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    isSelected
                        ? ElevenLabsBrand.Colors.paper
                        : ElevenLabsBrand.Colors.ink
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                            ? ElevenLabsBrand.Colors.inkPure
                            : ElevenLabsBrand.Colors.card
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : ElevenLabsBrand.Colors.hairline,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Export / Import buttons

    private var exportButton: some View {
        ghostPillButton(
            iconSymbol: "square.and.arrow.up",
            label: "Export",
            action: handleExportTapped,
            isDisabled: isExportDisabled
        )
    }

    private var importButton: some View {
        let isPersonalScope = selectedLibraryScope == .personal
        return ghostPillButton(
            iconSymbol: "square.and.arrow.down",
            label: "Import",
            action: handleImportTapped,
            isDisabled: !isPersonalScope
        )
        .nativeTooltip(
            isPersonalScope
                ? "Merge a Sticky taste export into your profile"
                : "Switch to Personal to import"
        )
    }

    @ViewBuilder
    private func ghostPillButton(
        iconSymbol: String,
        label: String,
        action: @escaping () -> Void,
        isDisabled: Bool
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(ElevenLabsBrand.Colors.card))
            .overlay(Capsule().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: !isDisabled)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    /// Disable Export when the current scope has nothing to export so the
    /// user doesn't get an empty file. Avoids confusing "What did I just
    /// save?" moments.
    private var isExportDisabled: Bool {
        switch selectedLibraryScope {
        case .personal: return loadedPersonalProfile.principles.isEmpty
        case .team:     return loadedTeamProfile == nil
        }
    }

    // MARK: - Team read-only banner

    private var teamReadOnlyBanner: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .padding(.top, 1)

            Text("Team taste is shared. Edit team-profile.json directly to change it.")
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            Spacer(minLength: 0)
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    // MARK: - Import toast

    private func importSuccessToast(message: String) -> some View {
        HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Text(message)
                .font(ElevenLabsBrand.Typography.bodyStrong)
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Spacer(minLength: 0)
        }
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
    }

    // MARK: - Principle list

    @ViewBuilder
    private var principleScrollList: some View {
        let visiblePrinciples = principlesForCurrentScope()

        if visiblePrinciples.isEmpty {
            emptyStateView
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.lg) {
                    ForEach(DomainBrand.stableDomainOrder, id: \.self) { domainGroup in
                        let principlesInDomain = visiblePrinciples.filter { $0.domain == domainGroup }
                        if !principlesInDomain.isEmpty {
                            domainSection(
                                domain: domainGroup,
                                principlesInDomain: principlesInDomain
                            )
                        }
                    }
                }
                .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
                .padding(.top, ElevenLabsBrand.Spacing.lg)
                .padding(.bottom, ElevenLabsBrand.Spacing.xl)
            }
        }
    }

    /// Each domain section: gradient swatch + domain label + count, then
    /// a vertical stack of white principle cards. The swatch turns each
    /// section into a recognizable visual landmark.
    private func domainSection(
        domain: TasteDomain,
        principlesInDomain: [TastePrinciple]
    ) -> some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                // Domain swatch — small gradient tile with the clover
                // overlay, sized to align with the section label.
                ElevenLabsGradientTile(
                    gradient: DomainBrand.gradient(for: domain),
                    radius: 6
                )
                .frame(width: 22, height: 22)

                Text(DomainBrand.displayLabel(for: domain))
                    .font(ElevenLabsBrand.Typography.bodyStrong)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                Text("\(principlesInDomain.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ElevenLabsBrand.Colors.paperRecessed))

                Spacer()
            }

            VStack(spacing: ElevenLabsBrand.Spacing.xs) {
                ForEach(principlesInDomain) { principleInList in
                    PrincipleCardView(
                        principle: principleInList,
                        canDelete: selectedLibraryScope == .personal,
                        onRequestDelete: { requestDeletion(of: principleInList) }
                    )
                }
            }
        }
    }

    // MARK: - Empty state
    //
    // Hero gradient + paper card with copy. Mirrors the chat empty state
    // so the two windows share a visual language.

    @ViewBuilder
    private var emptyStateView: some View {
        let isPersonalScope = selectedLibraryScope == .personal

        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            ElevenLabsGradientTile(gradient: ElevenLabsBrand.Gradients.cool) {
                VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                    Spacer(minLength: 0)
                    ElevenLabsEyebrow("EMPTY")
                        .foregroundColor(.white.opacity(0.85))
                    Text(isPersonalScope
                         ? "Your taste\nlibrary is open."
                         : "No team taste\nloaded yet.")
                        .font(ElevenLabsBrand.Typography.hero(size: 26))
                        .tracking(-0.5)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ElevenLabsBrand.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 200)

            Text(isPersonalScope
                 ? "Hit Show & tell and narrate while you work. Sticky will start filling this in with notes on what's behind your decisions."
                 : "Add a team-profile.json to ~/Library/Application Support/com.learning-buddy.clicky/ to share notes across the team.")
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
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
        .padding(.horizontal, ElevenLabsBrand.Spacing.lg)
        .padding(.top, ElevenLabsBrand.Spacing.lg)
        .padding(.bottom, ElevenLabsBrand.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Computed copy + state helpers

    /// Returns the principles for the currently selected scope. Sorted so
    /// the most recently updated principles appear first within each
    /// domain group — keeps "what just got saved" visible without making
    /// the user scroll.
    private func principlesForCurrentScope() -> [TastePrinciple] {
        let principlesForScope: [TastePrinciple]
        switch selectedLibraryScope {
        case .personal:
            principlesForScope = loadedPersonalProfile.principles
        case .team:
            principlesForScope = loadedTeamProfile?.principles ?? []
        }
        return principlesForScope.sorted { firstPrinciple, secondPrinciple in
            firstPrinciple.updatedAt > secondPrinciple.updatedAt
        }
    }

    private func refreshProfilesFromDisk() {
        do {
            loadedPersonalProfile = try TasteProfileStore.loadProfile()
        } catch {
            print("⚠️ TasteLibraryView: failed to load personal profile: \(error)")
        }
        loadedTeamProfile = TeamTasteProfileStore.loadTeamProfile()
    }

    // MARK: - Delete flow

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { principlePendingDeletion != nil },
            set: { isStillPresented in
                if !isStillPresented {
                    principlePendingDeletion = nil
                }
            }
        )
    }

    private func requestDeletion(of principleToDelete: TastePrinciple) {
        principlePendingDeletion = principleToDelete
    }

    private func deletePrincipleNow(_ principleToDelete: TastePrinciple) {
        do {
            try TasteProfileStore.deletePrinciple(id: principleToDelete.id)
        } catch {
            principlePendingDeletion = nil
            presentInlineErrorAlert(
                title: "Couldn't forget that",
                message: error.localizedDescription
            )
            return
        }
        principlePendingDeletion = nil
        refreshProfilesFromDisk()
    }

    // MARK: - Export action

    private func handleExportTapped() {
        switch selectedLibraryScope {
        case .personal:
            TasteProfileExporter.exportPersonalProfile(loadedPersonalProfile)
        case .team:
            if let teamProfileToExport = loadedTeamProfile {
                TasteProfileExporter.exportTeamProfile(teamProfileToExport)
            }
        }
    }

    // MARK: - Import action

    private func handleImportTapped() {
        guard selectedLibraryScope == .personal else { return }

        let importResult = TasteProfileExporter.importPersonalProfile()

        switch importResult {
        case .none:
            // User cancelled — silent no-op.
            return
        case .some(.success(let importSummary)):
            loadedPersonalProfile = importSummary.mergedProfile
            let addedCount = importSummary.newPrinciplesAdded
            let noteNoun = addedCount == 1 ? "note" : "notes"
            withAnimation(.easeInOut(duration: 0.2)) {
                if addedCount > 0 {
                    importToastMessage = "Imported \(addedCount) new \(noteNoun)"
                } else {
                    importToastMessage = "No new notes to import — they were already in your profile."
                }
            }
            scheduleImportToastAutoFade()
        case .some(.failure(let importerError)):
            presentInlineErrorAlert(
                title: "Import failed",
                message: importerError.localizedDescription
            )
        }
    }

    private func scheduleImportToastAutoFade() {
        // Capture the message we just set so a subsequent quick re-import
        // doesn't get its own toast clobbered by this delayed fade.
        let toastMessageAtSchedule = importToastMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if importToastMessage == toastMessageAtSchedule {
                withAnimation(.easeInOut(duration: 0.25)) {
                    importToastMessage = nil
                }
            }
        }
    }

    // MARK: - Inline error alert

    private func presentInlineErrorAlert(title: String, message: String) {
        let errorAlert = NSAlert()
        errorAlert.messageText = title
        errorAlert.informativeText = message
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: "OK")
        errorAlert.runModal()
    }
}

// MARK: - Principle Card

/// One principle in the library, rendered as a white card on paper. The
/// statement is the headline. Evidence (the user's spoken reasoning) is
/// shown beneath in lighter type so the card reads like a quote.
/// Hovering reveals a circular trash button on Personal cards.
private struct PrincipleCardView: View {
    let principle: TastePrinciple
    let canDelete: Bool
    let onRequestDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(principle.statement)
                    .font(ElevenLabsBrand.Typography.bodyStrong)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let firstEvidenceItem = principle.evidence.first, !firstEvidenceItem.isEmpty {
                    Text("“\(firstEvidenceItem)”")
                        .font(ElevenLabsBrand.Typography.body)
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                        .italic()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            if canDelete {
                Button(action: onRequestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.gradientCoral)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(ElevenLabsBrand.Colors.gradientCoral.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .nativeTooltip("Forget this note")
                .opacity(isHovering ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.12), value: isHovering)
            }
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(
                    isHovering
                        ? ElevenLabsBrand.Colors.hairlineStrong
                        : ElevenLabsBrand.Colors.hairline,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { isCurrentlyHovering in
            isHovering = isCurrentlyHovering
        }
    }
}
