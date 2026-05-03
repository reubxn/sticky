//
//  DashboardTasteMarkdownExporter.swift
//  leanring-buddy
//
//  Exports a TasteProfile as a `TASTE.md` markdown file via NSSavePanel.
//  Companion to TasteProfileExporter (which writes JSON) — same
//  underlying data, but rendered as the human-readable markdown shape
//  the project already uses for per-teammate TASTE.md files. Lets the
//  Dashboard's Profile tab give the user a "download my taste as
//  TASTE.md" button that produces a file they can drop into git or
//  share with a teammate.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DashboardTasteMarkdownExporter {

    /// Opens an NSSavePanel pre-filled with `TASTE.md`, then writes the
    /// rendered markdown to the chosen URL. Silent no-op if the user
    /// cancels the panel. Filename always defaults to `TASTE.md` — that
    /// was the explicit ask: the file should be called TASTE.md.
    static func exportPersonalProfileAsMarkdown(
        _ tasteProfile: TasteProfile,
        displayName: String,
        role: String?,
        accentHex: String?,
        voiceId: String?,
        soulProse: String?
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export TASTE.md"
        savePanel.nameFieldStringValue = "TASTE.md"
        savePanel.allowedContentTypes = [UTType.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let panelResponse = savePanel.runModal()
        guard panelResponse == .OK, let saveDestinationURL = savePanel.url else {
            return
        }

        let renderedMarkdown = renderTasteMarkdown(
            tasteProfile: tasteProfile,
            displayName: displayName,
            role: role,
            accentHex: accentHex,
            voiceId: voiceId,
            soulProse: soulProse
        )

        do {
            try renderedMarkdown.write(to: saveDestinationURL, atomically: true, encoding: .utf8)
        } catch {
            print("⚠️ DashboardTasteMarkdownExporter: write failed: \(error)")
        }
    }

    // MARK: - Markdown rendering

    /// Renders a TasteProfile in the same shape the project's per-
    /// teammate TASTE.md files use. Header line, metadata comment,
    /// Soul section (empty if unknown), Taste section grouped by
    /// domain. Compatible with `PersonaTasteFileStore.parseTasteMarkdown`
    /// so the exported file is round-trippable.
    static func renderTasteMarkdown(
        tasteProfile: TasteProfile,
        displayName: String,
        role: String?,
        accentHex: String?,
        voiceId: String?,
        soulProse: String?
    ) -> String {
        var output: [String] = []

        // Header — "# Name — Role" or just "# Name" if no role.
        if let role, !role.isEmpty {
            output.append("# \(displayName) — \(role)")
        } else {
            output.append("# \(displayName)")
        }
        output.append("")

        // Metadata comment matching PersonaTasteFileStore's parser.
        let resolvedVoice = voiceId ?? ""
        let resolvedAccent = accentHex ?? "#1F6FEB"
        output.append("<!-- @persona id=\(tasteProfile.userId) voice=\(resolvedVoice) accent=\(resolvedAccent) -->")
        output.append("")

        // Soul section — use the persona's actual soul prose when we
        // have it (loaded from the user's persona bundle / TASTE.md);
        // fall back to a placeholder hint only when the profile has
        // never had soul prose attached.
        output.append("## Soul")
        output.append("")
        let trimmedSoulProse = (soulProse ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSoulProse.isEmpty {
            output.append("_Add your personality prose here — how you think, what you care about, what you push back on._")
        } else {
            output.append(trimmedSoulProse)
        }
        output.append("")

        // Taste section — group principles by domain in stable order.
        output.append("## Taste")
        output.append("")

        let domainOrder: [TasteDomain] = [.general, .design, .writing, .code]
        for domain in domainOrder {
            let principlesInDomain = tasteProfile.principles.filter { $0.domain == domain }
            guard !principlesInDomain.isEmpty else { continue }

            output.append("### \(displayLabel(forDomain: domain))")
            output.append("")
            for principle in principlesInDomain {
                output.append(renderPrincipleBullet(principle))
                output.append("")
            }
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Helpers (mirror PersonaTasteFileStore's writer shape)

    private static func displayLabel(forDomain domain: TasteDomain) -> String {
        switch domain {
        case .general: return "General"
        case .design: return "Design"
        case .writing: return "Writing"
        case .code: return "Code"
        }
    }

    private static func renderPrincipleBullet(_ principle: TastePrinciple) -> String {
        let confidenceFormatted = String(format: "%.2f", principle.confidence)
        let tagsJoined = principle.tags.isEmpty ? "—" : principle.tags.joined(separator: ", ")
        let evidenceProse = principle.evidence.first ?? ""

        var lines: [String] = []
        lines.append("- **\(principle.statement)**")
        lines.append("  *(confidence \(confidenceFormatted) · \(tagsJoined))*")
        if !evidenceProse.isEmpty {
            lines.append("  \(evidenceProse)")
        }
        return lines.joined(separator: "\n")
    }
}
