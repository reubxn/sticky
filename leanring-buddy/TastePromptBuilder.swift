//
//  TastePromptBuilder.swift
//  leanring-buddy
//
//  Converts a TasteProfile into a short prose block that gets prepended to
//  the existing Sticky voice system prompt. Hackathon MVP: just a flat list
//  framed as "judgment context, not rigid rules". No domain grouping, no
//  weighting by confidence — those are easy to add later if the demo needs
//  more nuance.
//

import Foundation

/// Result of building a taste-context block. Carries both the prompt text
/// (already framed and ready to prepend) and a mapping from the short
/// labels the prompt embeds (`P1`, `T1`, …) back to the underlying
/// TastePrinciple objects. The response handler uses the mapping to
/// resolve the `[USED:...]` tag Claude returns at the end of its reply
/// into a list of principles to display in the transparency chip.
struct TasteContextBlock {
    /// The full prompt text to prepend to the system prompt, including the
    /// principle list, the framing, and the trailing `[USED:...]` instruction.
    /// Empty string when there are no principles to inject.
    let promptText: String

    /// Maps each short label in the prompt (e.g. "P1", "T1") to the
    /// principle that label refers to. Empty when promptText is empty.
    let principlesByShortLabel: [String: TastePrinciple]

    /// Subset of the keys in `principlesByShortLabel` whose principle came
    /// from the team profile rather than the user's personal profile. The
    /// chip uses this to render a "Team" pill on those rows.
    let teamShortLabels: Set<String>
}

enum TastePromptBuilder {
    /// Builds a system-prompt block describing the user's saved taste so
    /// Sticky can ground every voice answer in their preferences. When the
    /// scope is `.team`, the block also includes the team profile's
    /// principles, deduped against personal by id. Returns an empty string
    /// when nothing approved is available — the caller no-ops cleanly.
    ///
    /// Thin wrapper around `buildTasteContextBlock(...)` for callers that
    /// only need the prompt text (e.g. teammate persona composition, which
    /// doesn't render the transparency chip).
    static func tasteContextBlock(
        personalProfile: TasteProfile,
        teamProfile: TeamTasteProfile?,
        scope: TasteScope
    ) -> String {
        return buildTasteContextBlock(
            personalProfile: personalProfile,
            teamProfile: teamProfile,
            scope: scope
        ).promptText
    }

    /// Builds a TasteContextBlock — the prompt text plus the label->principle
    /// mapping the response handler needs to resolve Claude's
    /// `[USED:...]` tag back into displayable principles.
    ///
    /// Each principle is emitted with a stable short label (`P1`, `P2`, ...
    /// for personal; `T1`, `T2`, ... for team). The trailing instruction
    /// asks Claude to list which short labels it actually used at the end
    /// of its reply. The instruction has to live INSIDE this block so
    /// Claude sees the principle list and the tag protocol together.
    static func buildTasteContextBlock(
        personalProfile: TasteProfile,
        teamProfile: TeamTasteProfile?,
        scope: TasteScope
    ) -> TasteContextBlock {
        let approvedPersonalPrinciples = personalProfile.principles.filter { $0.approved }

        // Resolve the principles we'll actually emit, splitting them by
        // origin so we can label personal vs team rows differently in the
        // prompt (`P1` vs `T1`) and in the chip ("Personal" vs "Team").
        let personalPrinciplesToEmit: [TastePrinciple]
        let teamPrinciplesToEmit: [TastePrinciple]

        switch scope {
        case .personal:
            personalPrinciplesToEmit = approvedPersonalPrinciples
            teamPrinciplesToEmit = []

        case .team:
            personalPrinciplesToEmit = approvedPersonalPrinciples
            if let teamProfile {
                // Dedupe team principles against personal by id — if the
                // same principle is in both, keep it on the personal side
                // so it shows up once with a `P` label (the user's own
                // taste takes precedence over inherited team taste).
                let personalPrincipleIds = Set(approvedPersonalPrinciples.map { $0.id })
                teamPrinciplesToEmit = teamProfile.principles.filter { teamPrinciple in
                    teamPrinciple.approved && !personalPrincipleIds.contains(teamPrinciple.id)
                }
            } else {
                teamPrinciplesToEmit = []
            }
        }

        let totalPrinciplesToEmit = personalPrinciplesToEmit.count + teamPrinciplesToEmit.count
        guard totalPrinciplesToEmit > 0 else {
            return TasteContextBlock(promptText: "", principlesByShortLabel: [:], teamShortLabels: [])
        }

        // Build the label->principle mapping in lockstep with the lines we
        // emit so the prompt and the resolver agree on what `P1` means.
        var principlesByShortLabel: [String: TastePrinciple] = [:]
        var teamShortLabels: Set<String> = []
        var promptLines: [String] = []

        switch scope {
        case .personal:
            promptLines.append("the user's taste — things they've taught you they prefer:")
        case .team:
            if let teamProfile {
                promptLines.append("the user's taste — combined personal preferences and the \(teamProfile.name) team's preferences:")
            } else {
                promptLines.append("the user's taste — things they've taught you they prefer:")
            }
        }

        for (zeroBasedIndex, personalPrinciple) in personalPrinciplesToEmit.enumerated() {
            let shortLabel = "P\(zeroBasedIndex + 1)"
            principlesByShortLabel[shortLabel] = personalPrinciple
            promptLines.append("- [\(shortLabel)][\(personalPrinciple.domain.rawValue)] \(personalPrinciple.statement)")
        }

        for (zeroBasedIndex, teamPrinciple) in teamPrinciplesToEmit.enumerated() {
            let shortLabel = "T\(zeroBasedIndex + 1)"
            principlesByShortLabel[shortLabel] = teamPrinciple
            teamShortLabels.insert(shortLabel)
            promptLines.append("- [\(shortLabel)][\(teamPrinciple.domain.rawValue)] \(teamPrinciple.statement)")
        }

        promptLines.append("")
        promptLines.append("treat these as judgment context, not rigid rules. when something on screen lines up with one of these, lean into it; when something cuts against one, gently flag the tension. don't recite the list back to the user — just let it shape your answer.")
        promptLines.append("")
        // The trailing tag has to be inside the SAME block as the list so
        // Claude sees the IDs and the tag protocol together. `[USED:none]`
        // is required when nothing applied so we can distinguish "Claude
        // didn't lean on anything" from "Claude forgot to emit the tag".
        promptLines.append("when you finish your reply, on a final new line write [USED:P1,T1] (or whichever short labels above you genuinely leaned on). if you didn't use any, write [USED:none]. the user will not see this tag — it powers a small ui chip that tells them which principles informed your answer. put this tag AFTER any [POINT:...] tag if you also point at something.")

        return TasteContextBlock(
            promptText: promptLines.joined(separator: "\n"),
            principlesByShortLabel: principlesByShortLabel,
            teamShortLabels: teamShortLabels
        )
    }

    /// Strips the trailing `[USED:...]` tag from a full assistant reply
    /// and returns the remaining text plus the parsed list of short labels.
    ///
    /// - Tolerant to surrounding whitespace and missing tag (returns input
    ///   unchanged with an empty label array in that case).
    /// - `[USED:none]` parses to an empty array — treated identically to
    ///   "Claude said it didn't use any principles" by the caller.
    /// - The cleaned text still contains the `[POINT:...]` tag (if any) —
    ///   this parser only knows about the `[USED:...]` tag.
    static func parseUsedTag(from rawAssistantResponse: String) -> (cleanText: String, usedShortLabels: [String]) {
        // Match `[USED:<contents>]` at the end of the response, allowing
        // any trailing whitespace. Anchored with `$` and the `s` flag so
        // newlines between the body and the tag don't break the match.
        let usedTagPattern = #"\[USED:([^\]]*)\]\s*$"#

        guard let usedTagRegex = try? NSRegularExpression(pattern: usedTagPattern, options: []),
              let usedTagMatch = usedTagRegex.firstMatch(
                in: rawAssistantResponse,
                range: NSRange(rawAssistantResponse.startIndex..., in: rawAssistantResponse)
              ) else {
            return (cleanText: rawAssistantResponse, usedShortLabels: [])
        }

        guard let usedTagFullRange = Range(usedTagMatch.range, in: rawAssistantResponse),
              let usedTagContentRange = Range(usedTagMatch.range(at: 1), in: rawAssistantResponse) else {
            return (cleanText: rawAssistantResponse, usedShortLabels: [])
        }

        let cleanedText = String(rawAssistantResponse[..<usedTagFullRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTagContents = String(rawAssistantResponse[usedTagContentRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // `[USED:none]` (case-insensitive, allow surrounding whitespace) → empty list.
        if rawTagContents.lowercased() == "none" || rawTagContents.isEmpty {
            return (cleanText: cleanedText, usedShortLabels: [])
        }

        let parsedShortLabels = rawTagContents
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (cleanText: cleanedText, usedShortLabels: parsedShortLabels)
    }
}
