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

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardProfileView: View {
    /// Optional shared CompanionManager. Threaded in from
    /// `DashboardView` so voice picker writes go through
    /// `setSelectedVoiceID(_:)` — that updates the in-memory
    /// `@Published var selectedVoiceID` immediately, instead of only
    /// updating UserDefaults (which CompanionManager only reads at
    /// init, so a UserDefaults-only write wouldn't take effect until
    /// the next app launch).
    let companionManager: CompanionManager?

    init(companionManager: CompanionManager? = nil) {
        self.companionManager = companionManager
    }

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
    @State private var customVoiceIdInput: String = ""

    /// Bumped after a profile picture is saved or removed so the avatar
    /// preview re-reads the file from disk instead of caching the old
    /// NSImage. Without this the AsyncImage-style cache holds onto the
    /// previous bytes after an in-place replacement.
    @State private var profilePictureReloadCounter: Int = 0

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
                fieldLabel("Profile picture")
                profilePictureRow

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

    // MARK: - Profile picture row

    private var profilePictureRow: some View {
        HStack(spacing: ElevenLabsBrand.Spacing.md) {
            profilePictureAvatar
                .id(profilePictureReloadCounter)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: pickAndSaveProfilePicture) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .bold))
                            Text(dashboardMockAuthState.profilePicturePath == nil ? "Upload" : "Change")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .elevenLabsPrimaryButtonStyle(isFullWidth: false)

                    if dashboardMockAuthState.profilePicturePath != nil {
                        Button(action: removeProfilePicture) {
                            Text("Remove")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }

                Text("PNG or JPEG. Square images look best.")
                    .font(.system(size: 11))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var profilePictureAvatar: some View {
        if let path = dashboardMockAuthState.profilePicturePath,
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                )
        } else {
            ZStack {
                Circle()
                    .fill(ElevenLabsBrand.Colors.paperRecessed)
                    .overlay(
                        Circle().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                    )
                Text(initialsFromDisplayName(draftDisplayName))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }
            .frame(width: 56, height: 56)
        }
    }

    private func initialsFromDisplayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2,
           let first = parts.first?.first,
           let last = parts.last?.first {
            return String([first, last]).uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }

    private func pickAndSaveProfilePicture() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.png, .jpeg, .image]
        openPanel.prompt = "Choose"
        openPanel.message = "Pick a profile picture"

        guard openPanel.runModal() == .OK, let sourceURL = openPanel.url else { return }

        do {
            let savedPath = try saveProfilePictureFile(sourceURL: sourceURL)
            dashboardMockAuthState.profilePicturePath = savedPath
            profilePictureReloadCounter += 1
        } catch {
            NSLog("Failed to save profile picture: \(error)")
        }
    }

    private func removeProfilePicture() {
        if let existingPath = dashboardMockAuthState.profilePicturePath {
            try? FileManager.default.removeItem(atPath: existingPath)
        }
        dashboardMockAuthState.profilePicturePath = nil
        profilePictureReloadCounter += 1
    }

    /// Copies the picked image into Application Support so the file
    /// survives the original being moved/deleted, and so we own a
    /// stable path. Overwrites any existing profile picture on disk.
    private func saveProfilePictureFile(sourceURL: URL) throws -> String {
        let fileManager = FileManager.default
        guard let applicationSupportDirectoryURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(domain: "DashboardProfileView", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not locate Application Support directory."
            ])
        }

        let directoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("com.learning-buddy.clicky", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let destinationURL = directoryURL.appendingPathComponent("profile-picture.\(fileExtension)", isDirectory: false)

        // Clear any old profile picture (any extension) before writing
        // the new one so we don't leave stale files behind.
        if let existingFiles = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            for fileURL in existingFiles where fileURL.lastPathComponent.hasPrefix("profile-picture.") {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.path
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

                customVoiceRow
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
            // Route through CompanionManager so the in-memory
            // selectedVoiceID updates immediately (it also persists to
            // UserDefaults). Writing to UserDefaults directly here
            // wouldn't take effect until the next launch, since
            // CompanionManager only reads the key at init.
            if let companionManager {
                companionManager.setSelectedVoiceID(voiceId)
            } else {
                UserDefaults.standard.set(voiceId, forKey: "selectedElevenLabsVoiceID")
            }
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

    // A row that lets the user paste an arbitrary ElevenLabs voice id
    // (e.g. one they cloned in their own ElevenLabs account) and use it
    // as the active voice. Selected when the saved voice id isn't one
    // of the bundled options.
    private var customVoiceRow: some View {
        let trimmedInput = customVoiceIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCustomActive = !trimmedInput.isEmpty && draftVoiceId == trimmedInput
        let isBundledVoiceSelected = draftVoiceId.map { savedVoiceId in
            ElevenLabsTTSClient.freeVoices.contains(where: { $0.id == savedVoiceId })
        } ?? false
        let isSelected = isCustomActive && !isBundledVoiceSelected

        return HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    isSelected
                        ? ElevenLabsBrand.Colors.ink
                        : ElevenLabsBrand.Colors.inkTertiary
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom voice")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                HStack(spacing: 6) {
                    TextField("Paste ElevenLabs voice ID", text: $customVoiceIdInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ElevenLabsBrand.Colors.paperRecessed)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                        )

                    Button("Use") {
                        let trimmed = customVoiceIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        draftVoiceId = trimmed
                        if let companionManager {
                            companionManager.setSelectedVoiceID(trimmed)
                        } else {
                            UserDefaults.standard.set(trimmed, forKey: "selectedElevenLabsVoiceID")
                        }
                    }
                    .buttonStyle(InteractivePressStyle(pressScale: 0.98))
                    .pointerCursor()
                    .disabled(trimmedInput.isEmpty || trimmedInput == draftVoiceId)
                }
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

    // MARK: - TASTE.md export card

    private var tasteExportCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("EXPORT")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                Text("Export your taste as TASTE.md")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                Text("Writes a markdown file with your soul + every approved note, grouped by domain. The file is named TASTE.md so it drops cleanly into a personas folder.")
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
        // The user's TASTE.md should reflect everything Sticky knows
        // about them — both the hand-curated soul + bundled principles
        // (loaded from their persona's TASTE.md, the source of truth
        // for identity prose) AND any extra principles teach-mode has
        // appended into taste-profile.json over time. Merge them by id;
        // the two sources use disjoint id schemes (slug vs UUID) so
        // dedup collisions are unlikely but cheap to guard against.
        let localBundle = PersonaStore.myCurrentBundle()

        let bundledPrinciples: [TastePrinciple] = localBundle?.taste.principles ?? []
        let teachModePrinciples: [TastePrinciple] = {
            do {
                return try TasteProfileStore.loadProfile().principles
            } catch {
                return []
            }
        }()

        var seenPrincipleIds = Set<String>()
        var mergedPrinciples: [TastePrinciple] = []
        for principle in bundledPrinciples + teachModePrinciples {
            guard !seenPrincipleIds.contains(principle.id) else { continue }
            seenPrincipleIds.insert(principle.id)
            mergedPrinciples.append(principle)
        }

        let mergedProfile = TasteProfile(
            userId: PersonaStore.myPersonaId,
            principles: mergedPrinciples,
            updatedAt: Date()
        )

        DashboardTasteMarkdownExporter.exportPersonalProfileAsMarkdown(
            mergedProfile,
            displayName: localBundle?.displayName ?? dashboardMockAuthState.displayName,
            role: localBundle?.role ?? dashboardMockAuthState.role,
            accentHex: localBundle?.accentColorHex,
            voiceId: localBundle?.voiceId,
            soulProse: localBundle?.soul
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
        // If the saved voice id isn't one of the bundled options, surface
        // it in the custom-voice input so the user sees what's currently
        // active and can edit it. Bundled selections leave the input
        // empty so it reads as "add a new custom voice".
        if let savedVoiceId = draftVoiceId,
           !ElevenLabsTTSClient.freeVoices.contains(where: { $0.id == savedVoiceId }) {
            customVoiceIdInput = savedVoiceId
        } else {
            customVoiceIdInput = ""
        }
    }
}
