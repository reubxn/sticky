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
import UniformTypeIdentifiers

struct DashboardTeamView: View {
    @StateObject private var dashboardNavigationState = DashboardNavigationState.shared
    @ObservedObject private var authenticationManager = AuthenticationManager.shared

    @State private var pendingInviteEmailText: String = ""
    @State private var showingInviteFormCard: Bool = false
    @State private var lastInviteSentToEmail: String? = nil

    // Team context — the shared brief + dropped files. Loaded on appear
    // and persisted on every edit so the prompt builders read fresh
    // material on the next call.
    @State private var teamContextProfile: TeamContextProfile = TeamContextStore.loadProfile()

    // Reflects the brief field so we can debounce-save without thrashing
    // disk on every keystroke. Synced from teamContextProfile on appear /
    // when profile is replaced wholesale.
    @State private var pendingTeamBriefText: String = ""

    // True while the SwiftUI .onDrop is hovering with valid file
    // providers, used to highlight the drop zone.
    @State private var isDropZoneHighlighted: Bool = false

    // Banner shown after a file was added or rejected.
    @State private var fileImportStatusMessage: String? = nil

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

            teamContextSection

            teammatesList
        }
        .onAppear {
            reloadTeamContextFromDisk()
        }
    }

    // MARK: - Team context section
    //
    // A brief about what the team does plus a file dropper. Every persona
    // operating in team scope (and every teammate persona) gets this as
    // background context — they see filenames + summaries by default and
    // the body of small text files inlined for direct reading.

    private var teamContextSection: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                ElevenLabsEyebrow("TEAM CONTEXT")
                Text("What your team does.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text("A brief plus any shared files. Every persona sees this overview when speaking on behalf of the team — small text files are read directly, larger or binary files are summarised by name.")
                    .font(.system(size: 12))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            teamBriefCard

            teamFilesCard

            if let fileImportStatusMessage {
                fileImportStatusToast(messageText: fileImportStatusMessage)
            }
        }
    }

    private var teamBriefCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                Text("Team brief")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Spacer()
                if !pendingTeamBriefText.isEmpty {
                    Text("\(pendingTeamBriefText.count) chars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }
            }

            Text("Describe what the team is working on, who you're for, what matters. A few sentences is plenty.")
                .font(.system(size: 11))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            // SwiftUI's TextEditor with the .plain text-field-like treatment
            // gives us a multi-line input that fits the dashboard look.
            TextEditor(text: $pendingTeamBriefText)
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .scrollContentBackground(.hidden)
                .padding(ElevenLabsBrand.Spacing.sm)
                .frame(minHeight: 110, maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ElevenLabsBrand.Colors.paperRecessed)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                )
                .onChange(of: pendingTeamBriefText) { _, newBriefText in
                    saveTeamBrief(newBriefText)
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

    private var teamFilesCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                Text("Shared files")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Spacer()
                Text("\(teamContextProfile.attachedFiles.count) file\(teamContextProfile.attachedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            }

            Text("Drop files in or click Add file. Add a one-line summary so personas know what's inside without reading the whole thing.")
                .font(.system(size: 11))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

            fileDropZone

            if !teamContextProfile.attachedFiles.isEmpty {
                attachedFilesList
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

    private var fileDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            Text("Drop a file here")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text("or")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            Button(action: presentNativeFilePicker) {
                Text("Choose file…")
                    .font(.system(size: 12, weight: .semibold))
            }
            .elevenLabsPrimaryButtonStyle(isFullWidth: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ElevenLabsBrand.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isDropZoneHighlighted
                        ? ElevenLabsBrand.Colors.paperRecessed
                        : ElevenLabsBrand.Colors.paperRecessed.opacity(0.5)
                )
        )
        .overlay(
            // Dashed-style outline to read clearly as a drop target. SwiftUI's
            // StrokeStyle with `dash:` works on RoundedRectangle.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropZoneHighlighted
                        ? ElevenLabsBrand.Colors.ink.opacity(0.45)
                        : ElevenLabsBrand.Colors.hairline,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropZoneHighlighted) { itemProviders in
            return handleDroppedItemProviders(itemProviders)
        }
    }

    private var attachedFilesList: some View {
        VStack(spacing: ElevenLabsBrand.Spacing.xs) {
            ForEach(teamContextProfile.attachedFiles) { attachedFile in
                attachedFileRow(forAttachedFile: attachedFile)
            }
        }
    }

    private func attachedFileRow(forAttachedFile attachedFile: TeamContextAttachedFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: attachedFile.isPlainText ? "doc.text" : "doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                Text(attachedFile.filename)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(formattedSize(forBytes: attachedFile.sizeBytes))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                Button(action: { removeAttachedFile(attachedFile) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            // Per-file summary input. Lives on the row so the user can
            // write "brand guidelines from Sept" without leaving the
            // page. Saves on commit so the inevitable per-keystroke disk
            // write doesn't happen here.
            TextField(
                "One-line summary so personas know what's inside…",
                text: bindingForSummaryOfAttachedFile(attachedFile)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .padding(.horizontal, ElevenLabsBrand.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.paperRecessed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
            .onSubmit {
                persistTeamContextProfile()
            }
        }
        .padding(ElevenLabsBrand.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func fileImportStatusToast(messageText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text(messageText)
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
                PersonaAvatarView(
                    avatar: bundle.avatar,
                    diameter: 48,
                    uploadedImageOverridePath: PersonaStore.uploadedProfilePicturePath(forPersonaId: bundle.id)
                )

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

                    Text("\(bundle.taste.principles.count) note\(bundle.taste.principles.count == 1 ? "" : "s") · \(domainsSummary(forBundle: bundle))")
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

    // MARK: - Team context: load / save

    private func reloadTeamContextFromDisk() {
        let loadedProfile = TeamContextStore.loadProfile()
        teamContextProfile = loadedProfile
        pendingTeamBriefText = loadedProfile.brief
    }

    /// Persists the brief on every keystroke. Disk writes are cheap for
    /// a few KB of JSON and we'd rather take the small cost than risk
    /// a typed-but-not-saved brief on app quit. The saveProfile call
    /// already updates `updatedAt` for us.
    private func saveTeamBrief(_ newBriefText: String) {
        teamContextProfile.brief = newBriefText
        persistTeamContextProfile()
    }

    private func persistTeamContextProfile() {
        do {
            try TeamContextStore.saveProfile(teamContextProfile)
        } catch {
            print("⚠️ DashboardTeamView: failed to persist team context: \(error)")
            showFileImportStatus(message: "Couldn't save team context. Try again.")
        }
    }

    /// SwiftUI binding for the summary field of one attached file. We
    /// can't bind directly into the array because mutating a struct
    /// inside an array via Binding requires manual lookup by id.
    private func bindingForSummaryOfAttachedFile(
        _ attachedFile: TeamContextAttachedFile
    ) -> Binding<String> {
        Binding<String>(
            get: {
                guard let indexInArray = teamContextProfile.attachedFiles
                    .firstIndex(where: { $0.id == attachedFile.id }) else {
                    return ""
                }
                return teamContextProfile.attachedFiles[indexInArray].summary
            },
            set: { newSummaryText in
                guard let indexInArray = teamContextProfile.attachedFiles
                    .firstIndex(where: { $0.id == attachedFile.id }) else {
                    return
                }
                teamContextProfile.attachedFiles[indexInArray].summary = newSummaryText
                // Persist on every keystroke for parity with the brief.
                persistTeamContextProfile()
            }
        )
    }

    // MARK: - Team context: file import

    /// Native macOS file picker. Used by the "Choose file…" button as a
    /// keyboard-accessible alternative to drag-and-drop.
    private func presentNativeFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        openPanel.title = "Add files to team context"
        openPanel.prompt = "Add"

        openPanel.begin { userResponse in
            guard userResponse == .OK else { return }
            for pickedFileURL in openPanel.urls {
                importFileFromSourceURL(pickedFileURL)
            }
        }
    }

    /// Handler for `.onDrop`. Each item provider asynchronously resolves
    /// to a file URL; we import each one as it lands. Returns true when
    /// at least one provider looked like a file URL so SwiftUI shows the
    /// "accepted" cursor.
    private func handleDroppedItemProviders(_ itemProviders: [NSItemProvider]) -> Bool {
        var providersAcceptedFromThisDrop: Int = 0
        for itemProvider in itemProviders {
            guard itemProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            providersAcceptedFromThisDrop += 1
            itemProvider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { itemDataRepresentation, _ in
                // The provider hands us a Data representation of the URL
                // (UTF-8 bytes of the path). Convert back on the main
                // queue before touching SwiftUI state / disk.
                guard let itemData = itemDataRepresentation as? Data,
                      let droppedFileURL = URL(
                        dataRepresentation: itemData,
                        relativeTo: nil,
                        isAbsolute: true
                      ) else {
                    return
                }
                DispatchQueue.main.async {
                    importFileFromSourceURL(droppedFileURL)
                }
            }
        }
        return providersAcceptedFromThisDrop > 0
    }

    /// Single-file import path used by both the drop zone and the open
    /// panel. Copies the file body into Application Support, appends an
    /// entry to the profile, and persists.
    private func importFileFromSourceURL(_ sourceURL: URL) {
        do {
            let importedAttachedFile = try TeamContextStore.importFile(fromSourceURL: sourceURL)
            teamContextProfile.attachedFiles.append(importedAttachedFile)
            persistTeamContextProfile()
            showFileImportStatus(message: "Added \(importedAttachedFile.filename).")
        } catch {
            print("⚠️ DashboardTeamView: import failed for \(sourceURL.path): \(error)")
            showFileImportStatus(message: "Couldn't add \(sourceURL.lastPathComponent).")
        }
    }

    private func removeAttachedFile(_ attachedFileToRemove: TeamContextAttachedFile) {
        // Wipe the on-disk body before mutating the array so a partial
        // failure leaves a worse end state ("file ghosted in JSON but
        // body gone") rather than a silent leak ("body remains forever
        // because the JSON entry is gone"). The store logs but doesn't
        // throw, so this never fails the user-visible flow.
        TeamContextStore.deleteFileBody(forAttachedFile: attachedFileToRemove)
        teamContextProfile.attachedFiles.removeAll(where: { $0.id == attachedFileToRemove.id })
        persistTeamContextProfile()
        showFileImportStatus(message: "Removed \(attachedFileToRemove.filename).")
    }

    /// Brief inline status bar — used for both successes and failures so
    /// we don't need separate toast components. Auto-clears after a
    /// short delay so the dashboard doesn't accumulate stale messages.
    private func showFileImportStatus(message: String) {
        fileImportStatusMessage = message
        let messageSnapshot = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if fileImportStatusMessage == messageSnapshot {
                fileImportStatusMessage = nil
            }
        }
    }

    private func formattedSize(forBytes byteCount: Int) -> String {
        if byteCount < 1024 {
            return "\(byteCount) B"
        }
        let kilobytes = Double(byteCount) / 1024.0
        if kilobytes < 1024 {
            return String(format: "%.1f KB", kilobytes)
        }
        let megabytes = kilobytes / 1024.0
        return String(format: "%.1f MB", megabytes)
    }
}
