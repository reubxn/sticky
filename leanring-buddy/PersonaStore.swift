//
//  PersonaStore.swift
//  leanring-buddy
//
//  Loads the available persona bundles (the user's teammates) Sticky
//  can wear. The hackathon MVP ships three sample teammates baked into
//  the binary as Swift constants — when the user uploads real photos /
//  writes real soul.md files / records real voices, this store can be
//  extended to read from `~/Library/Application Support/com.learning-
//  buddy.clicky/personas/<id>/` instead.
//
//  Sample data here is intentionally placeholder — names, roles, voices,
//  and taste principles are stand-ins so the wheel-picker, the cursor
//  swap, and the prompt-injection paths can all be exercised end-to-end
//  before the real team's data lands.
//

import Foundation
import SwiftUI

enum PersonaStore {
    /// Which persona "owns" this Sticky install — i.e. when teach mode
    /// extracts a principle, this is the TASTE.md it gets appended to.
    /// Hardcoded for the hackathon since this is Reuban's machine; on
    /// Leonard's or Magdalena's, swap the value (or move to UserDefaults
    /// when there's a settings UI).
    static let myPersonaId: String = "reuban"

    /// The local user's full bundle, re-read from disk every time so
    /// freshly-taught principles become visible in `.me` apply mode
    /// without an app restart. Returns nil when the owner's TASTE.md
    /// can't be loaded — callers fall back to the legacy JSON path.
    static func myCurrentBundle() -> PersonaBundle? {
        return try? PersonaTasteFileStore.loadBundle(forId: myPersonaId)
    }

    /// All teammate bundles available to the user, resolved once at
    /// app launch. The canonical source of truth is now the per-
    /// teammate TASTE.md files under `personas/<id>/TASTE.md` (bundled
    /// with the app, hot-swappable from Application Support). The
    /// Swift-literal bundles below (`reubanBundle`, `leonardBundle`,
    /// `magdalenaBundle`) stay around only as last-resort fallbacks —
    /// if every TASTE.md fails to load (corrupt build, missing files),
    /// the in-memory copies keep the demo working.
    ///
    /// Order in the radial wheel picker matches the order in the
    /// returned array (clockwise from 12 o'clock).
    static let availableTeammates: [PersonaBundle] = {
        let bundlesFromMarkdown = PersonaTasteFileStore.loadAllAvailableBundles()
        let allBundles: [PersonaBundle]
        if !bundlesFromMarkdown.isEmpty {
            print("📄 PersonaStore: loaded \(bundlesFromMarkdown.count) bundle(s) from TASTE.md")
            allBundles = bundlesFromMarkdown
        } else {
            print("⚠️ PersonaStore: no TASTE.md files reachable — falling back to baked-in Swift bundles")
            allBundles = [reubanBundle, leonardBundle, magdalenaBundle]
        }
        // Drop the local user from the wheel's teammate list — `.me` already
        // represents them, so showing them again as a teammate spoke would be
        // a duplicate face.
        return allBundles.filter { $0.id != myPersonaId }
    }()

    /// The local user's bundle (for the demo, Reuban). Looked up out of the
    /// raw teammate bundles before they're filtered out, so `.me` can borrow
    /// the user's real avatar / accent color even though they're hidden from
    /// the wheel as a separate spoke.
    static let myOwnBundle: PersonaBundle? = {
        let bundlesFromMarkdown = PersonaTasteFileStore.loadAllAvailableBundles()
        let pool = bundlesFromMarkdown.isEmpty
            ? [reubanBundle, leonardBundle, magdalenaBundle]
            : bundlesFromMarkdown
        return pool.first(where: { $0.id == myPersonaId })
    }()

    /// Returns the teammate bundle for the given id, or nil if the id
    /// has been removed since the user's preference was last saved.
    /// Callers should fall back to `.me` when nil is returned.
    static func teammate(withId id: String) -> PersonaBundle? {
        return availableTeammates.first(where: { $0.id == id })
    }

    /// Synthetic "team" pseudo-persona used for the wheel picker so the
    /// pooled-team mode reads as just another orbit on the wheel rather
    /// than a separate UI surface. Has no soul / voice — selecting this
    /// at the wheel level translates to `PersonaSelection.team` and the
    /// existing pooled-team code path runs.
    static let teamPseudoPersona: PersonaBundle = PersonaBundle(
        id: "__team__",
        displayName: "Team",
        role: "Pooled taste",
        avatar: .systemSymbol(name: "person.2.fill", hexColor: "#7C8DA3"),
        accentColorHex: "#7C8DA3",
        soul: "",
        voiceId: "",
        taste: TasteProfile(userId: "team-pseudo", principles: [], updatedAt: Date())
    )

    /// Synthetic "me" pseudo-persona — represents the local user on the
    /// wheel. Selecting this translates to `PersonaSelection.me` and the
    /// existing personal-only code path runs (using the user's own
    /// selectedVoiceID and saved TasteProfile from disk).
    ///
    /// When the local user has a real persona bundle on disk (for the
    /// demo, Reuban), borrow that bundle's avatar + accent color so the
    /// cursor / menu bar / glow all show the user's actual face instead
    /// of a generic `person.fill` glyph. Falls back to the SF Symbol if
    /// the user's bundle can't be loaded (fresh install, missing assets).
    static let mePseudoPersona: PersonaBundle = PersonaBundle(
        id: "__me__",
        displayName: "Me",
        role: "Your taste",
        avatar: myOwnBundle?.avatar
            ?? .systemSymbol(name: "person.fill", hexColor: "#3B82F6"),
        accentColorHex: myOwnBundle?.accentColorHex ?? "#3B82F6",
        soul: "",
        voiceId: "",
        taste: TasteProfile(userId: "local-user", principles: [], updatedAt: Date())
    )

    /// All personas in wheel-display order: Me first (the user's own
    /// identity is the default at the top of the wheel), then Team
    /// (pooled), then each teammate. The wheel picker iterates this
    /// directly to lay out spokes.
    static var allWheelPersonas: [PersonaBundle] {
        return [mePseudoPersona, teamPseudoPersona] + availableTeammates
    }

    /// Maps a wheel-displayed persona back to the `PersonaSelection`
    /// case CompanionManager actually stores. The wheel deals in
    /// PersonaBundle for uniform layout; the rest of the app deals in
    /// PersonaSelection so .me / .team / .teammate semantics stay sharp.
    static func selectionForWheelPersona(_ persona: PersonaBundle) -> PersonaSelection {
        switch persona.id {
        case mePseudoPersona.id: return .me
        case teamPseudoPersona.id: return .team
        default: return .teammate(id: persona.id)
        }
    }

    /// Inverse of `selectionForWheelPersona`. Returns nil when the
    /// referenced teammate has been removed.
    static func wheelPersonaForSelection(_ selection: PersonaSelection) -> PersonaBundle? {
        switch selection {
        case .me: return mePseudoPersona
        case .team: return teamPseudoPersona
        case .teammate(let id): return teammate(withId: id)
        }
    }
}

// MARK: - Sample Persona Bundles
//
// These are placeholders so the system can be exercised end-to-end with
// no external assets required. The user is going to replace each block
// with their real teammates' names, photos, soul.md text, and recorded
// voice ids. The shapes here are the contract — keep `id`, `voiceId`,
// `accentColorHex`, and the principle ids stable when swapping in real
// data so any persistence layer that grows later doesn't lose track of
// which teammate is which.

private extension PersonaStore {
    /// Sample taste-principle factory — reduces boilerplate when laying
    /// out the demo bundles. Created/updated timestamps are pinned to
    /// the start of the hackathon so the JSON is reproducible across
    /// builds (no flapping diffs from `Date()` calls at app launch).
    static func samplePrinciple(
        id: String,
        domain: TasteDomain,
        statement: String,
        evidence: String,
        tags: [String],
        authorId: String,
        confidence: Double = 0.85
    ) -> TastePrinciple {
        TastePrinciple(
            id: id,
            domain: domain,
            statement: statement,
            confidence: confidence,
            evidence: [evidence],
            tags: tags,
            approved: true,
            authorId: authorId,
            createdAt: hackathonEpoch,
            updatedAt: hackathonEpoch
        )
    }

    /// Stable timestamp shared across all sample bundles. Picked to
    /// match the hackathon's start-of-work date in the project memory
    /// (May 1 2026) so all demo data shares a reasonable "as of" date.
    static let hackathonEpoch: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 1
        components.hour = 9
        components.minute = 0
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }()

    // MARK: - Real team bundles
    //
    // Three real teammates the user works with on this project. Avatars
    // are JPEGs/PNGs shipped in the app bundle (`reuban.png`,
    // `leonard.jpeg`, `magda.jpeg`); voices picked from the ElevenLabs
    // free-tier roster to match each person's affect. Souls written
    // from their LinkedIn presence — refine as the demo gets used.

    /// Reuban Ramsden — the user's own bundle, available to other
    /// teammates who want to borrow his lens. Voice: "Liam" (Energetic
    /// · American) — youthful builder cadence to match his ship-fast
    /// engineering register. Accent: cobalt blue (matches the Sticky
    /// default cursor color as a nod to "this is the maker's lens").
    static var reubanBundle: PersonaBundle {
        PersonaBundle(
            id: "reuban",
            displayName: "Reuban",
            role: "Builder · Sticky",
            avatar: .imageFile(filename: "reuban.png"),
            accentColorHex: "#1F6FEB",
            soul: """
            you are reuban. you build software for a living and your default mode is "ship a working version, then sharpen it." you've been the engineer-designer-founder hybrid on every project you've touched — sticky is the latest one — and you trust intuition that's been beaten on enough times to feel like data.

            speak in short, declarative sentences. you don't pad. when you give an opinion, give it whole and stop. ask one tight question instead of three loose ones. when something is good say "that works" and move on; when it isn't, say what the smaller / clearer / more direct version would be.

            you care about: the smallest thing that proves the idea, interfaces a stranger could grok in one sitting, removing chrome that doesn't earn its keep, mood and motion that make a tool feel alive without showing off. you're suspicious of: jargon that hides a missing decision, three-step interactions that should be one, settings panels that should be opinionated defaults, designs that look right in the file but feel wrong in your hand.
            """,
            voiceId: "TX3LPaxmHKxFdv7VOQHJ", // Liam — Energetic · American
            taste: TasteProfile(
                userId: "reuban",
                principles: [
                    samplePrinciple(
                        id: "reuban-build-1",
                        domain: .general,
                        statement: "Ship the smallest thing that proves the idea, then sharpen.",
                        evidence: "Reuban's default project rhythm — working version first, polish in iteration.",
                        tags: ["mvp", "iteration"],
                        authorId: "reuban",
                        confidence: 0.92
                    ),
                    samplePrinciple(
                        id: "reuban-design-1",
                        domain: .design,
                        statement: "Mood and motion matter — a tool should feel alive without showing off.",
                        evidence: "Cursor companion, edge-glow, persona wheel — alive UI is the through-line.",
                        tags: ["motion", "feel"],
                        authorId: "reuban",
                        confidence: 0.88
                    ),
                    samplePrinciple(
                        id: "reuban-product-1",
                        domain: .general,
                        statement: "Three-step interactions that could be one are bugs.",
                        evidence: "Push-to-talk, hold-to-summon — every Sticky gesture collapses to a single hold.",
                        tags: ["interaction", "simplicity"],
                        authorId: "reuban",
                        confidence: 0.86
                    ),
                    samplePrinciple(
                        id: "reuban-code-1",
                        domain: .code,
                        statement: "Opinionated defaults beat configurable settings.",
                        evidence: "Sticky picks one voice, one hotkey, one mode at a time — no preference panes.",
                        tags: ["defaults", "opinionation"],
                        authorId: "reuban",
                        confidence: 0.84
                    )
                ],
                updatedAt: hackathonEpoch
            )
        )
    }

    /// Leonard Cornelius — Imperial College BSc Economics, Finance, and
    /// Data Science; intern at OMMAX (advanced analytics); president of
    /// the EFDS Society; Kearney Academy participant; previously interned
    /// at neotherm and London Strategic Consulting; from Düsseldorf.
    /// Voice: "Daniel" (Steady Broadcaster · British) — calm, deliberate,
    /// matches an analyst who builds VAR models for fun. Accent: muted
    /// slate-blue.
    static var leonardBundle: PersonaBundle {
        PersonaBundle(
            id: "leonard",
            displayName: "Leonard",
            role: "Quant · Imperial",
            avatar: .imageFile(filename: "leonard.jpeg"),
            accentColorHex: "#3F5B7C",
            soul: """
            you are leonard. you read economics, finance, and data science at imperial and your reflex when faced with a question is to ask whether it's actually been measured. you've forecasted unemployment with a VAR model for fun and won the imperial first-year challenge analysing free-trade agreements with a gravity model — your taste is shaped by treating "looks right" as a hypothesis, not a conclusion.

            speak calmly and structured. lead with the assumption, then the implication. flag when you're extrapolating beyond the data. you don't waste words but you don't rush either — accuracy beats speed.

            you care about: clean baselines and explicit assumptions, decompositions that separate what you actually know from what you're guessing, charts that show uncertainty rather than hide it, models that fail loudly when the inputs go out of regime. you're suspicious of: dashboards that round confidence intervals into a single number, "rule of thumb" claims with no source, decisions that mistake correlation for causation, optimisation pushed past the point where the noise dominates the signal.
            """,
            voiceId: "onwK4e9ZLuTAKqWW03F9", // Daniel — Steady Broadcaster · British
            taste: TasteProfile(
                userId: "leonard",
                principles: [
                    samplePrinciple(
                        id: "leonard-data-1",
                        domain: .general,
                        statement: "If you can't name the assumption, you don't have a model — you have a guess.",
                        evidence: "Refuses to act on a forecast without naming the data-generating process.",
                        tags: ["assumptions", "rigor"],
                        authorId: "leonard",
                        confidence: 0.92
                    ),
                    samplePrinciple(
                        id: "leonard-data-2",
                        domain: .general,
                        statement: "Show the uncertainty — single-number forecasts are theater.",
                        evidence: "VAR forecasts always reported with confidence bands, never point estimates alone.",
                        tags: ["uncertainty", "charts"],
                        authorId: "leonard",
                        confidence: 0.88
                    ),
                    samplePrinciple(
                        id: "leonard-code-1",
                        domain: .code,
                        statement: "Models should fail loudly when inputs go out of regime.",
                        evidence: "Adds explicit guards on input ranges before any prediction call.",
                        tags: ["robustness", "error handling"],
                        authorId: "leonard",
                        confidence: 0.85
                    ),
                    samplePrinciple(
                        id: "leonard-writing-1",
                        domain: .writing,
                        statement: "Lead with the assumption, then the implication — never the other way round.",
                        evidence: "Reorders memos to put the model's preconditions before its conclusions.",
                        tags: ["structure", "argument"],
                        authorId: "leonard",
                        confidence: 0.83
                    )
                ],
                updatedAt: hackathonEpoch
            )
        )
    }

    /// Magdalena Blyskosz — Co-Founder @ Middle Bridge, BD @ Flying
    /// Bisons, NYU Abu Dhabi BBA. Polish, lives between Abu Dhabi /
    /// Riyadh / Tokyo / Stockholm. Founded Open Coffee Youth (2k+
    /// students, 10+ countries), TEDx speaker, ex-VP of Violet Ventures.
    /// Cross-border BD across Gulf / CEE / East Asia. Voice: "Alice"
    /// (Engaging · British) — warm, confident, networking energy. Accent:
    /// magenta-rose.
    static var magdalenaBundle: PersonaBundle {
        PersonaBundle(
            id: "magdalena",
            displayName: "Magdalena",
            role: "Co-Founder · Middle Bridge",
            avatar: .imageFile(filename: "magda.jpeg"),
            accentColorHex: "#C84B86",
            soul: """
            you are magdalena. you co-founded middle bridge to help growth-stage companies expand across the gulf, central europe, and east asia, and your work is built on the belief that the most valuable partnerships are the ones across borders — but only if you actually understand the room you're walking into. you've moved between abu dhabi, riyadh, tokyo, warsaw, and stockholm enough times to know that "global strategy" decks always undersell what cultural context, trust, and unspoken rules actually decide.

            speak warmly and with momentum. you're a connector by reflex — you pattern-match across people, ecosystems, and timing. when you give feedback, ground it in *who* the audience is and *where* they sit before talking about the artifact itself. you're not afraid to be encouraging; you also won't let a fuzzy positioning slide because politeness shouldn't cost the user later.

            you care about: who the message is actually for, market and cultural fit before tactics, brand presence that signals seriousness without pretending, copy that respects the reader's time, partnerships that compound over years rather than transactions that win this quarter. you're suspicious of: generic startup voice that could be any company, a deck that doesn't name the audience, "global" claims with no specific market behind them, decoration that obscures the substance, anything that would read as cold or transactional in a region where relationships are the asset.
            """,
            voiceId: "Xb7hH8MSUJpSbSDYk0k2", // Alice — Engaging · British
            taste: TasteProfile(
                userId: "magdalena",
                principles: [
                    samplePrinciple(
                        id: "magdalena-bd-1",
                        domain: .general,
                        statement: "Name the audience before debating the artifact — region and role first.",
                        evidence: "Reframes design / copy reviews around \"who is this for, in which market\".",
                        tags: ["audience", "positioning"],
                        authorId: "magdalena",
                        confidence: 0.92
                    ),
                    samplePrinciple(
                        id: "magdalena-writing-1",
                        domain: .writing,
                        statement: "Avoid generic startup voice — copy should sound like it could only be this company.",
                        evidence: "Strikes \"supercharge / unlock / accelerate\" boilerplate during reviews.",
                        tags: ["copy", "voice"],
                        authorId: "magdalena",
                        confidence: 0.88
                    ),
                    samplePrinciple(
                        id: "magdalena-design-1",
                        domain: .design,
                        statement: "Brand presence should signal seriousness without performing it.",
                        evidence: "Pushes for confident type and restrained color over neon attention-grabbing.",
                        tags: ["brand", "polish"],
                        authorId: "magdalena",
                        confidence: 0.85
                    ),
                    samplePrinciple(
                        id: "magdalena-product-1",
                        domain: .general,
                        statement: "Cross-border products fail on cultural detail before they fail on features.",
                        evidence: "Calls out idioms / examples / payment patterns that won't land outside the home market.",
                        tags: ["cross-border", "localization"],
                        authorId: "magdalena",
                        confidence: 0.86
                    )
                ],
                updatedAt: hackathonEpoch
            )
        )
    }

}
