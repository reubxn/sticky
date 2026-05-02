//
//  TasteProfileExporter.swift
//  leanring-buddy
//
//  Pure helpers for exporting and importing taste profiles as JSON files.
//  The Sticky Memory window uses these to let the user back up the
//  knowledgebase or share it with a teammate, and to seed a fresh install
//  from someone else's export.
//
//  Format on disk matches what TasteProfileStore writes natively (pretty
//  printed, sorted keys, ISO-8601 dates) so an export can also be edited
//  by hand and imported back without fuss.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum TasteProfileExporter {
    /// Result of a successful import — surfaced so the caller can show
    /// "Imported N new principle(s)" to the user. The caller has already
    /// merged the new principles into the on-disk profile by the time
    /// they see this value.
    struct ImportSummary {
        let totalPrinciplesInImportedFile: Int
        let newPrinciplesAdded: Int
        let mergedProfile: TasteProfile
    }

    enum ImporterError: Error, LocalizedError {
        case userCancelled
        case fileReadFailed(underlying: Error)
        case fileDecodeFailed(underlying: Error)
        case profileWriteFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Import was cancelled."
            case .fileReadFailed(let underlying):
                return "Couldn't read the file: \(underlying.localizedDescription)"
            case .fileDecodeFailed(let underlying):
                return "Couldn't read that file — make sure it's a Sticky taste export. (\(underlying.localizedDescription))"
            case .profileWriteFailed(let underlying):
                return "Couldn't update your taste profile: \(underlying.localizedDescription)"
            }
        }
    }

    // MARK: - Personal export

    /// Presents an `NSSavePanel` and writes the entire personal profile
    /// (every principle, approved or not) to a pretty-printed JSON file.
    /// No-ops cleanly if the user cancels the save panel.
    @MainActor
    static func exportPersonalProfile(_ personalProfile: TasteProfile) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Sticky Taste"
        savePanel.message = "Save your personal taste profile as JSON."
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = defaultExportFileName(scopeSegment: "personal")
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        guard savePanel.runModal() == .OK, let chosenSaveURL = savePanel.url else {
            return
        }

        do {
            let exportFileData = try encodePersonalProfileForExport(personalProfile)
            try exportFileData.write(to: chosenSaveURL, options: [.atomic])
        } catch {
            presentSimpleErrorAlert(
                title: "Export failed",
                informativeText: error.localizedDescription
            )
        }
    }

    // MARK: - Team export

    /// Same shape as `exportPersonalProfile` but writes the team profile.
    /// The Library window only enables this when a team profile is loaded
    /// in the first place, so we don't need to handle the missing-team
    /// case here.
    @MainActor
    static func exportTeamProfile(_ teamProfile: TeamTasteProfile) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Team Taste"
        savePanel.message = "Save the team taste profile as JSON."
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = defaultExportFileName(scopeSegment: "team")
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        guard savePanel.runModal() == .OK, let chosenSaveURL = savePanel.url else {
            return
        }

        do {
            let exportFileData = try encodeTeamProfileForExport(teamProfile)
            try exportFileData.write(to: chosenSaveURL, options: [.atomic])
        } catch {
            presentSimpleErrorAlert(
                title: "Export failed",
                informativeText: error.localizedDescription
            )
        }
    }

    // MARK: - Personal import

    /// Presents an `NSOpenPanel`, decodes the picked file as a `TasteProfile`,
    /// and merges its principles into the user's existing personal profile
    /// (existing principles win on `id` collision, so we never silently
    /// overwrite something the user already has). Persists the merged
    /// profile to disk and returns a summary for UI feedback.
    ///
    /// Returns `nil` when the user cancels the open panel — the caller
    /// treats that as a no-op rather than an error. Otherwise returns a
    /// `Result` so the caller can render either a success toast or an
    /// inline error alert.
    @MainActor
    static func importPersonalProfile() -> Result<ImportSummary, ImporterError>? {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Sticky Taste"
        openPanel.message = "Pick a Sticky taste export (.json) to merge into your profile."
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK, let chosenImportURL = openPanel.url else {
            return nil
        }

        let importedFileData: Data
        do {
            importedFileData = try Data(contentsOf: chosenImportURL)
        } catch {
            return .failure(.fileReadFailed(underlying: error))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let importedProfile: TasteProfile
        do {
            importedProfile = try decoder.decode(TasteProfile.self, from: importedFileData)
        } catch {
            return .failure(.fileDecodeFailed(underlying: error))
        }

        // Merge into the existing personal profile by appending only the
        // principles whose id we don't already have. This way Import is
        // safe to run repeatedly with the same file — duplicates just
        // get skipped — and the user never loses an edit they made
        // locally.
        let existingPersonalProfile: TasteProfile
        do {
            existingPersonalProfile = try TasteProfileStore.loadProfile()
        } catch {
            return .failure(.profileWriteFailed(underlying: error))
        }

        let existingPrincipleIds = Set(existingPersonalProfile.principles.map { $0.id })
        var mergedProfile = existingPersonalProfile
        var newPrinciplesAddedCount = 0

        for importedPrinciple in importedProfile.principles {
            if existingPrincipleIds.contains(importedPrinciple.id) { continue }
            mergedProfile.principles.append(importedPrinciple)
            newPrinciplesAddedCount += 1
        }

        do {
            try TasteProfileStore.replacePersonalProfile(mergedProfile)
        } catch {
            return .failure(.profileWriteFailed(underlying: error))
        }

        let summary = ImportSummary(
            totalPrinciplesInImportedFile: importedProfile.principles.count,
            newPrinciplesAdded: newPrinciplesAddedCount,
            mergedProfile: mergedProfile
        )
        return .success(summary)
    }

    // MARK: - Helpers

    /// Builds a filename like `sticky-taste-personal-2026-05-02.json` so
    /// repeat exports on the same day overwrite each other in the user's
    /// chosen folder rather than piling up.
    private static func defaultExportFileName(scopeSegment: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        return "sticky-taste-\(scopeSegment)-\(todayString).json"
    }

    private static func encodePersonalProfileForExport(_ personalProfile: TasteProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(personalProfile)
    }

    private static func encodeTeamProfileForExport(_ teamProfile: TeamTasteProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(teamProfile)
    }

    @MainActor
    private static func presentSimpleErrorAlert(title: String, informativeText: String) {
        let errorAlert = NSAlert()
        errorAlert.messageText = title
        errorAlert.informativeText = informativeText
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: "OK")
        errorAlert.runModal()
    }
}
