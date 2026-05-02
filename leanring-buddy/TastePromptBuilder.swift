//
//  TastePromptBuilder.swift
//  leanring-buddy
//
//  Converts a TasteProfile into a short prose block that gets prepended to
//  the existing Clicky voice system prompt. Hackathon MVP: just a flat list
//  framed as "judgment context, not rigid rules". No domain grouping, no
//  weighting by confidence — those are easy to add later if the demo needs
//  more nuance.
//

import Foundation

enum TastePromptBuilder {
    /// Builds a system-prompt block describing the user's saved taste so
    /// Clicky can ground every voice answer in their preferences. When the
    /// scope is `.team`, the block also includes the team profile's
    /// principles, deduped against personal by id. Returns an empty string
    /// when nothing approved is available — the caller no-ops cleanly.
    static func tasteContextBlock(
        personalProfile: TasteProfile,
        teamProfile: TeamTasteProfile?,
        scope: TasteScope
    ) -> String {
        let combinedPrinciples = principles(
            personalProfile: personalProfile,
            teamProfile: teamProfile,
            scope: scope
        )
        guard !combinedPrinciples.isEmpty else { return "" }

        var lines: [String] = []

        switch scope {
        case .personal:
            lines.append("the user's taste — things they've taught you they prefer:")
        case .team:
            if let teamProfile {
                lines.append("the user's taste — combined personal preferences and the \(teamProfile.name) team's preferences:")
            } else {
                lines.append("the user's taste — things they've taught you they prefer:")
            }
        }

        for principle in combinedPrinciples {
            lines.append("- [\(principle.domain.rawValue)] \(principle.statement)")
        }
        lines.append("")
        lines.append("treat these as judgment context, not rigid rules. when something on screen lines up with one of these, lean into it; when something cuts against one, gently flag the tension. don't recite the list back to the user — just let it shape your answer.")
        return lines.joined(separator: "\n")
    }

    /// Resolves the union of approved principles for a given scope. Personal
    /// scope = personal-only. Team scope = personal ∪ team, deduped by id
    /// (personal wins on conflict — the user's own principles take
    /// precedence over inherited team ones).
    private static func principles(
        personalProfile: TasteProfile,
        teamProfile: TeamTasteProfile?,
        scope: TasteScope
    ) -> [TastePrinciple] {
        let approvedPersonalPrinciples = personalProfile.principles.filter { $0.approved }

        switch scope {
        case .personal:
            return approvedPersonalPrinciples

        case .team:
            guard let teamProfile else {
                return approvedPersonalPrinciples
            }

            var seenPrincipleIds = Set(approvedPersonalPrinciples.map { $0.id })
            var combinedPrinciples = approvedPersonalPrinciples

            for teamPrinciple in teamProfile.principles where teamPrinciple.approved {
                guard !seenPrincipleIds.contains(teamPrinciple.id) else { continue }
                seenPrincipleIds.insert(teamPrinciple.id)
                combinedPrinciples.append(teamPrinciple)
            }

            return combinedPrinciples
        }
    }
}
