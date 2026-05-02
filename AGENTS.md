# Clicky - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Reverse Clicky Hackathon (active work — read first)

This repo is currently being forked into **Reverse Clicky**, a hackathon MVP. Clicky helps the user learn; Reverse Clicky flips it to help the AI learn the user's *taste* by capturing short workflow sessions, asking rapid-fire questions about creative decisions, and saving approved principles to a knowledgebase that Clicky later uses to critique work.

### Team and ownership

Three people, ~10 hours, two coding agents in parallel.

- **Reuban** (technical + design) — owns `ReverseClicky/Capture/` AND is the **only** person who edits existing Clicky files. He is the integration owner.
- **Leonardo** (technical) — owns `ReverseClicky/Analysis/` and `ReverseClicky/Apply/`. New files only. Never edits existing Clicky code.
- **Magdalena** (non-technical) — owns `ReverseClicky/demo/` (taste JSON, copy, demo script, test screenshots). Does not run a coding agent.

### Folder structure (frozen at hour 0)

```
ReverseClicky/
  Capture/        ← Reuban only
  Analysis/       ← Leonardo only
  Apply/          ← Leonardo only
  Shared/         ← TasteTypes.swift, frozen — no edits without all three agreeing
  demo/           ← Magdalena only (JSON, copy, scripts)
```

### Anti-conflict rules (CRITICAL — agents must follow)

- **One file = one owner.** Agents may only create or edit files inside their assigned folder.
- Agents may **READ** any file in the repo for context.
- `ReverseClicky/Shared/TasteTypes.swift` is **frozen** after hour 0 — do not edit it.
- The following existing Clicky files may **only** be edited by Reuban (the integration owner): [leanring_buddyApp.swift](leanring-buddy/leanring_buddyApp.swift), [CompanionManager.swift](leanring-buddy/CompanionManager.swift), [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift). If your task seems to require changes there, **stop and write a TODO comment in your own file** describing the integration point. Do not edit the file.
- `ReverseClicky/` is added to Xcode as a **folder reference** (blue folder), not a group. New `.swift` files inside it are picked up automatically and do **not** require `project.pbxproj` edits.
- Branches: `feature/capture` (Reuban), `feature/analysis` (Leonardo). Never cross-merge between feature branches — both rebase on `main`. Reuban merges first, Leonardo rebases and merges second.

### Architecture: hold-to-teach (the actual approach — supersedes session-based capture)

We pivoted away from "start a session, capture screenshots every 4s, analyze 12 frames at the end." Instead, **Reverse Clicky reuses Clicky's existing push-to-talk gesture verbatim** and switches behavior based on a `tasteMode` selector in the menu bar panel.

**The unchanged Clicky flow:** hold ctrl+option → speak → on release, [BuddyDictationManager](leanring-buddy/BuddyDictationManager.swift) finalizes the transcript, [CompanionScreenCaptureUtility](leanring-buddy/CompanionScreenCaptureUtility.swift) captures the current screen, [ClaudeAPI](leanring-buddy/ClaudeAPI.swift) sends transcript + screenshot to Claude, response streams back through [CompanionManager](leanring-buddy/CompanionManager.swift) and gets spoken via [ElevenLabsTTSClient](leanring-buddy/ElevenLabsTTSClient.swift).

**The Reverse Clicky addition:** a `@Published var tasteMode: TasteMode = .ask` on `CompanionManager`. Three cases:

| Mode | User says (held while speaking) | What changes vs. existing Clicky | Output |
|---|---|---|---|
| **`.ask`** (default) | "What's this button do?" | Nothing — current Clicky behavior unchanged. | Streamed reply + TTS + optional `[POINT:...]` cursor. |
| **`.teach`** | "I made the logo bigger because brand presence matters" | Different `systemPrompt` passed to `ClaudeAPI.analyzeImageStreaming` — asks Claude to return a single `TastePrinciple` as JSON. TTS is suppressed. | A review card with one principle: `[Remember]` / `[Skip]`. |
| **`.apply`** | "Does this match my taste?" | Same `systemPrompt` the user already gets, **plus** a taste-context block prepended via `TastePromptBuilder`. | Streamed reply + TTS as usual — but grounded in the user's saved principles. |

**Why this is the right architecture for 10 hours:**

- The hardest piece (multi-frame timeline analysis) disappears. Claude only ever sees one screenshot per teach press.
- The user *speaks their reasoning out loud*, which is exactly what we want to capture — taste is the decision-making process, and verbalizing it makes the principle high-quality. No more guessing what the user "meant" by a layout change.
- The privacy story is automatic: the existing waveform indicator only appears while the user is holding the key. There is no "session is recording in the background" — there is no session.
- Voice and taste are not in conflict. The user can switch modes between presses; nothing parallel is happening.
- Reuban's `Capture/` folder collapses to ~0 lines. Most of the work moves into Leonardo's `Analysis/` (the teach-mode prompt and review card) and `Apply/` (the taste-context injection).

**What this kills from earlier drafts:**

- ❌ 4-second screenshot `Timer` — gone
- ❌ `TasteSessionState` machine, `tasteSessionState` published var — gone
- ❌ Recording-indicator pill in `BlueCursorView` — gone (waveform suffices)
- ❌ `FrameSelector` pure function — gone (only ever 1 frame per press)
- ❌ Session JSON, per-session screenshot directory — gone (we just keep the latest screenshot in memory long enough to send to Claude)
- ❌ Session start/stop button in the panel — replaced by a 3-way mode picker

**What gets added instead:**

- A 3-way segmented control in [CompanionPanelView](leanring-buddy/CompanionPanelView.swift): **Ask / Teach / Apply**.
- A `TasteMode` enum (`.ask`, `.teach`, `.apply`) on `CompanionManager`.
- One branch in `CompanionManager`'s existing Claude call site: pick the system prompt + the post-processing path based on `tasteMode`.
- A `PrincipleReviewCard` SwiftUI view that appears in the panel (or as a small floating card) when teach-mode returns a parsed principle.
- `TasteProfileStore` and `TastePromptBuilder` (unchanged from earlier drafts).

### Reuse map — call existing Clicky APIs, do NOT rebuild

This is the most important section for agents. Every taste-session capability has an existing Clicky surface to call. **If you are about to write a new screenshot system, Claude client, hotkey listener, or design token, stop and use the listed API instead.**

| Capability | Existing Clicky API to call (do NOT rebuild) | Where to use it |
|---|---|---|
| Take a screenshot of all screens | `CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` → `[CompanionScreenCapture]` (each has `imageData: Data`, `isCursorScreen: Bool`, `label: String`). `@MainActor`, async throws. | `Capture/` — wrap in a 4-second timer. Save the cursor-screen frame's `imageData` to disk as JPEG. |
| Send images + prompt to Claude | `ClaudeAPI.analyzeImageStreaming(images:systemPrompt:conversationHistory:userPrompt:onTextChunk:)` — already accepts `[(data: Data, label: String)]` (so you can pass 8–12 frames in one call), takes a custom `systemPrompt`, streams via SSE through the Worker proxy. Non-streaming variant: `analyzeImage(...)`. | `Analysis/SessionAnalyzer` calls this directly with the taste-extraction prompt. `Apply/` calls it with the taste-injected system prompt. **Do not write a new HTTP client.** |
| Worker routes (already deployed) | `POST /chat` (Claude), `POST /tts` (ElevenLabs), `POST /transcribe-token` (AssemblyAI). Defined in [worker/src/index.ts](worker/src/index.ts). Base URL is set in [CompanionManager.swift](leanring-buddy/CompanionManager.swift). | No worker changes needed for MVP. Reverse Clicky uses `/chat` only. |
| Design tokens | `DS.Colors.*` (background, surface1–4, accent, success, warning, destructive, textPrimary/Secondary/Tertiary, overlayCursorBlue), `DS.CornerRadius.*` (small/medium/large/extraLarge/pill), `DS.Spacing.*` (xs–xxxl), `DS.Animation.*` (fast/normal/slow), button styles (`.dsPrimaryButtonStyle()`, `.dsSecondaryButtonStyle()`, `.dsTertiaryButtonStyle()`, `.dsOutlinedButtonStyle()`, `.dsDestructiveButtonStyle()`, `.dsIconButtonStyle(...)`), `.pointerCursor()`, `.nativeTooltip(...)`. | All Reverse Clicky UI must use these tokens — no hardcoded colors or radii. |
| Analytics | `ClickyAnalytics.track*(...)` static methods (PostHog under the hood). Add new methods like `trackTasteSessionStarted()`, `trackPrincipleApproved(...)` if needed. | `CompanionManager` (Reuban) wires these in at session boundaries. |
| Menu bar panel content | [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) — single SwiftUI `VStack` with sections (`panelHeader`, `modelPickerRow`, `settingsSection`, `startButton`, `dmFarzaButton`, `footerSection`). | Reuban inserts a new "Taste Session" section + Personal/Team toggle directly into the VStack. |
| Overlay window (recording indicator) | [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) — covers all screens, transparent. `BlueCursorView` is a SwiftUI ZStack of independent elements (cursor, waveform, spinner, bubbles). | Reuban adds a "Taste Session Active" capsule pill (and/or a screen-edge border) as an additional ZStack element gated on `companionManager.isTasteSessionActive`. **No restructuring needed.** |
| Element pointing during apply mode | Existing `[POINT:x,y:label:screenN]` parsing already drives the cursor overlay (see CompanionManager + OverlayWindow). | Apply-mode prompts can reuse `[POINT:...]` tags for free — Clicky already animates the cursor to them. |

### Reuse map — *partial* fit / known caveats

| Capability | Existing API | Caveat — how to use safely |
|---|---|---|
| Global hotkey (start/stop session) | [GlobalPushToTalkShortcutMonitor.swift](leanring-buddy/GlobalPushToTalkShortcutMonitor.swift) — currently registered as **Control+Option push-to-hold** for voice. Generic CGEvent tap underneath. | **Do NOT modify the existing voice hotkey.** For MVP, start/stop the taste session from a **button in the menu bar panel** (Reuban adds it). A second tap-toggle hotkey is a stretch — only attempt if all critical-path work is done. |
| Central state | [CompanionManager.swift](leanring-buddy/CompanionManager.swift) — already has `voiceState: CompanionVoiceState` (idle/listening/processing/responding) and a lot of overlay/onboarding state. | Add a **parallel** `@Published var tasteSessionState: TasteSessionState` enum (inactive / capturing / analyzing / questioning). **Do not extend `voiceState`** — voice and taste must be independent so users can talk to Clicky during/after a taste session. |
| Local persistence | Currently only `UserDefaults` for small flags (`selectedClaudeModel`, `isClickyCursorEnabled`, `hasCompletedOnboarding`, etc.). **No JSON-on-disk convention exists.** | Reverse Clicky establishes the convention. Use `~/Library/Application Support/com.learning-buddy.clicky/`: `taste-profile.json` (personal), `team-profile.json` (mock team), `sessions/<sessionID>/frame-*.jpg`. `TasteProfileStore` (Leonardo) owns this; create the directory with `FileManager` on first write. |

### What's in scope (with explicit reuse pointers)

- **Mode picker** — 3-way segmented control in `CompanionPanelView` (Ask / Teach / Apply). Persists across launches via `UserDefaults`. Reuban edits `CompanionPanelView` only.
- **Per-press screenshot** — already happens in `CompanionManager`'s existing voice flow. Nothing to add. The captured `Data` is passed straight into `ClaudeAPI.analyzeImageStreaming(...)`.
- **Teach-mode system prompt** — `TasteExtractionPrompt.systemPrompt(transcript:)` returns a prompt instructing Claude to produce a *single* `TastePrinciple` as JSON, given the user's spoken reasoning + the screenshot.
- **Teach-mode response parsing** — `SessionAnalyzer.parsePrinciple(from:)` extracts the JSON from Claude's reply (Claude may wrap it in prose). Returns `TastePrinciple?`.
- **Principle review card** — `PrincipleReviewCard` SwiftUI view shown in the panel (or as a small floating card near the cursor). Two buttons: Remember (`.dsPrimaryButtonStyle()`) and Skip (`.dsTertiaryButtonStyle()`).
- **Personal taste profile** — `taste-profile.json` written via `TasteProfileStore` (Codable + FileManager) at `~/Library/Application Support/com.learning-buddy.clicky/`.
- **Apply mode** — `TastePromptBuilder.tasteSystemPrompt(profile:mode:)` returns a string. Reuban prepends it to whatever `systemPrompt` the existing Claude call site sends — so every voice question in `.apply` mode gets taste context for free.
- **Team taste** — Magdalena hand-writes `team-profile.json`. `TeamTasteProfileStore` reads it; pooling = `personal.principles + team.principles` deduped by `id`.

### What's explicitly cut (do NOT build)

- ❌ Always-on / background capture
- ❌ Periodic screenshot timer (no sessions)
- ❌ Multi-frame analysis (one frame per teach press)
- ❌ Edit button on the review card (Remember / Skip only)
- ❌ Frame visual diffing
- ❌ Real team backend — `team-profile.json` is hand-written
- ❌ Confidence scores rendered in UI (store in JSON, don't show)
- ❌ New hotkey infrastructure — reuse existing ctrl+option push-to-talk
- ❌ New HTTP client, new screenshot system, new design tokens — call existing APIs
- ❌ Recording indicator pill — the existing waveform is the indicator
- ❌ Figma plugin, Cursor extension, fine-tuning, vector DB
- ❌ Autonomous typing / editing into other apps

### Core data shapes (lives in `Shared/TasteTypes.swift`)

All `Codable`.

```swift
enum TasteMode: String, Codable {
  case ask     // current Clicky behavior
  case teach   // extract a TastePrinciple from voice + screenshot
  case apply   // answer using stored taste profile as context
}

enum TasteDomain: String, Codable {
  case design, writing, code, general
}

enum TasteScope: String, Codable {
  case personal
  case team
}

struct TastePrinciple: Codable, Identifiable {
  let id: UUID
  var domain: TasteDomain
  var statement: String        // e.g. "Prefers strong brand presence and clear visual hierarchy."
  var confidence: Double       // stored, not rendered
  var evidence: [String]       // includes the user's spoken reasoning that produced it
  var tags: [String]
  var approved: Bool
  var authorId: String
  var createdAt: Date
  var updatedAt: Date
}

struct TasteProfile: Codable {
  var userId: String
  var principles: [TastePrinciple]
  var updatedAt: Date
}

struct TeamTasteProfile: Codable {
  var teamId: String
  var name: String
  var principles: [TastePrinciple]
  var updatedAt: Date
}
```

`TasteDecision` and `SessionFrame` from earlier drafts are **gone** — there are no sessions and no decision-vs-principle split. Each teach press produces a candidate `TastePrinciple` directly.

### Boundary contracts between owners

These are the **only** function signatures Reuban and Leonardo's code share. Frozen at hour 0.

```swift
// Leonardo provides — Reuban calls in CompanionManager's response handler when tasteMode == .teach
//   `transcript` is the user's finalized speech transcript (already produced by BuddyDictationManager).
//   `screenshotData` is the JPEG `Data` already captured by the existing voice flow.
//   Internally calls ClaudeAPI.analyzeImageStreaming with the teach-mode system prompt
//   and parses the streamed reply into a TastePrinciple.
func analyzeTeachMoment(transcript: String, screenshotData: Data) async throws -> TastePrinciple

// Leonardo provides — Reuban prepends to the existing systemPrompt when tasteMode == .apply
//   `scope` is .personal or .team based on a separate panel toggle.
func tasteSystemPrompt(profile: TasteProfile, scope: TasteScope) -> String

// Leonardo provides — Reuban calls when the user taps Remember on the review card
func appendApprovedPrinciple(_ principle: TastePrinciple) throws
```

Both `analyzeTeachMoment` and any apply-mode work go through `ClaudeAPI.analyzeImageStreaming(...)`. **Leonardo writes no raw HTTP.**

### State

`CompanionManager` gets two new `@Published` properties — both parallel to the existing `voiceState`, neither replaces it:

```swift
@Published var tasteMode: TasteMode = .ask
@Published var tasteScope: TasteScope = .personal       // for apply mode
@Published var pendingPrinciple: TastePrinciple? = nil  // shown in the review card
```

The voice state machine (idle → listening → processing → responding → idle) is unchanged. The branch happens *inside* the existing "responding" handler:

- `tasteMode == .ask` → existing behavior (TTS + cursor pointing).
- `tasteMode == .teach` → suppress TTS, parse JSON, set `pendingPrinciple`. The review card shows automatically.
- `tasteMode == .apply` → existing behavior, but the systemPrompt was prepended with taste context before the call.

### File paths (the new convention)

```
~/Library/Application Support/com.learning-buddy.clicky/
  taste-profile.json
  team-profile.json
```

No `sessions/` directory — there are no sessions. `TasteProfileStore` creates the parent directory on first write.

### Privacy requirements (non-negotiable for demo)

Capture only happens while the user is actively holding ctrl+option (the existing waveform indicator is visible the entire time). No background capture, no hidden recording, local storage only, explicit Remember tap before any principle persists.

---

## Reverse Clicky — Full Project Reference

The section above is the operational summary. Below is the full product spec — read it for nuance about *why* something is built a certain way.

### What we are building

Reverse Clicky is a hackathon MVP built by forking Clicky.

Clicky is an AI companion that helps the user learn. Reverse Clicky flips this: it helps the AI learn the user's taste.

The app captures short, intentional workflow sessions, reviews the user's creative decisions, asks rapid-fire questions, and converts the answers into reusable taste principles. Those principles become a personal or team knowledgebase that Clicky can use later to critique, guide, and suggest improvements.

### Core idea

Taste is not just the final output. Taste is the *decision-making process* behind the output.

| What the user did | What it may mean |
|---|---|
| Made logo bigger | Prefers stronger brand presence |
| Removed gradient | Prefers clean visuals over decoration |
| Shortened headline | Prefers direct, punchy copy |
| Added whitespace | Likes calmer, more breathable layouts |
| Removed abstraction | Prefers explicit readability over premature abstraction |

Bad memory: *"User made the logo bigger."*
Good memory: *"User prefers strong brand presence and clear visual hierarchy."*

The app should not simply remember low-level actions — it should infer principles.

### Hackathon scope

This is a hackathon MVP, not a production product. The goal is to prove the loop:

> start session → capture workflow → extract taste → save principles → use principles later

Build the smallest version that clearly demonstrates the concept.

**Do NOT build:** full background surveillance, always-on passive monitoring, Figma plugin, Cursor extension, fine-tuning, complex vector database, permissions system, complex team admin, autonomous typing/editing into other apps.

### Reuse Clicky first

Reverse Clicky should feel like an extension of Clicky, not a separate product. Reuse:

- macOS companion app shell
- floating companion UI / cursor overlay
- screen / screenshot capture (`CompanionScreenCaptureUtility`)
- AI call pipeline (`ClaudeAPI`)
- voice input if easy
- local app state, response UI

Do not rebuild systems Clicky already has.

### Two modes

**Absorb mode** — the user teaches the AI taste:

1. User starts a taste session (hotkey, e.g. ⌘+Shift+L).
2. App shows a visible recording signifier.
3. App captures screenshots periodically.
4. User works normally.
5. User ends the session.
6. AI reviews the screenshot timeline.
7. AI identifies meaningful creative decisions.
8. AI asks rapid-fire questions.
9. User approves, edits, or ignores suggested principles.
10. Approved principles are saved to the taste knowledgebase.

**Apply mode** — the AI uses the saved knowledgebase. Clicky stays a companion (not an autonomous editor) and can:

- critique the current screen
- suggest improvements
- rank options
- explain whether something matches taste
- generate small pieces of copy / design direction / code advice
- answer "what would our team think?"

### Why session-based capture (not always-on)

Manual start/stop is better for the MVP because: clearer consent, simpler implementation, less creepy, cheaper, easier to demo, avoids unreliable always-on observation.

### Start session

User presses hotkey (e.g. `⌘ + Shift + L`). State: `idle → recording`.

The app **must** show a visible signifier such as a glowing cursor, glowing screen border, or floating "Taste Session Active" pill. The user must always know when screenshots are being captured.

### During session

User works normally — designing a landing page, resizing a logo, rewriting copy, changing spacing, removing decoration, refactoring code, comparing options, editing AI-generated output, etc.

App captures screenshots every 3–5 seconds. Each frame stores:

```ts
type SessionFrame = {
  id: string
  sessionId: string
  timestamp: string
  screenshotPath: string
  activeApp?: string
  windowTitle?: string
}
```

Optional metadata if easy to capture: `keyboardActive`, `mouseActive`, `selectedText`, `clipboardText`.

### End session

User presses hotkey again. State: `recording → analyzing`. Stop screenshot capture and prepare the session for AI analysis.

### Key frame selection

Do NOT send every screenshot to the model. For MVP, select:

- first frame
- last frame
- evenly spaced frames between them

**Target: 8–12 frames max.**

Optional stretch: select frames with largest visual difference, simple image diffing, remove near-duplicates.

### Screenshot analysis

After the session, the AI reviews the selected screenshot timeline and identifies **3–5 meaningful decisions**.

Focus on changes that reveal judgment: stronger hierarchy, increased/decreased brand prominence, clearer layout, simpler copy, less decoration, more whitespace, stronger CTA, simpler code, less abstraction, different tone.

Ignore: loading states, cursor movement, tiny mechanical changes, accidental changes, irrelevant app switching.

### Decision object

```ts
type TasteDecision = {
  id: string
  observedChange: string
  whyItMayMatter: string
  question: string
  candidatePrinciple: string
  domain: "design" | "writing" | "code" | "general"
  confidence: number
}
```

Example:

```json
{
  "id": "d1",
  "observedChange": "The logo became larger and more prominent.",
  "whyItMayMatter": "This may indicate a preference for stronger brand presence or clearer hierarchy.",
  "question": "Should I remember that you prefer stronger brand presence and clear visual hierarchy?",
  "candidatePrinciple": "Prefers strong brand presence and clear visual hierarchy.",
  "domain": "design",
  "confidence": 0.82
}
```

### Rapid-fire questions

After analysis, the app asks the user short questions:

```
I noticed you made the logo more prominent.

Should I remember this?
"Prefers strong brand presence and clear visual hierarchy."

[Remember] [Edit] [Ignore]
```

User can:

- **Remember** — save the principle
- **Edit** — edit the principle before saving (CUT for hackathon MVP — Remember/Skip only)
- **Ignore** / **Skip** — discard it

The user should be able to review a session in **under 60 seconds**.

### Taste knowledgebase

The taste knowledgebase is the core output of the app. Structured list of approved taste principles, stored as local JSON for MVP.

```ts
type TasteProfile = {
  userId: string
  principles: TastePrinciple[]
  updatedAt: string
}

type TastePrinciple = {
  id: string
  domain: "design" | "writing" | "code" | "general"
  statement: string
  confidence: number
  evidence: string[]
  tags: string[]
  approved: boolean
  authorId: string
  createdAt: string
  updatedAt: string
}
```

Example profile:

```json
{
  "userId": "local-user",
  "principles": [
    {
      "id": "p1",
      "domain": "design",
      "statement": "Prefers strong brand presence and clear visual hierarchy.",
      "confidence": 0.82,
      "evidence": ["User enlarged the logo during a taste session."],
      "tags": ["brand", "hierarchy", "design"],
      "approved": true,
      "authorId": "local-user",
      "createdAt": "2026-05-01T18:00:00Z",
      "updatedAt": "2026-05-01T18:00:00Z"
    }
  ],
  "updatedAt": "2026-05-01T18:00:00Z"
}
```

### Personal vs Team taste

App supports two contexts: `[Personal] [Team]`.

- **Personal mode** — uses only the current user's approved principles.
- **Team mode** — uses pooled principles from the team (union, no complex merging).

Example:

```
Alice: strong brand presence, clean layouts
Bob:   high-contrast CTAs, minimal animations

Team Taste: strong brand presence, clean layouts, high-contrast CTAs, minimal animations
```

### Team profile schema

```ts
type TeamTasteProfile = {
  teamId: string
  name: string
  principles: TastePrinciple[]
  members: TeamMember[]
  updatedAt: string
}

type TeamMember = { userId: string; name?: string }
```

### Team pooling logic

When a user approves a principle while connected to a team:

1. Save it to their personal profile.
2. Also add it to the team profile.

```ts
function approvePrinciple(principle, userProfile, teamProfile) {
  userProfile.principles.push(principle)
  if (teamProfile) {
    teamProfile.principles.push({ ...principle, authorId: userProfile.userId })
  }
  saveUserProfile(userProfile)
  saveTeamProfile(teamProfile)
}
```

### Team MVP options

Any of these are acceptable for hackathon demo:

1. **Local mock team** — local `team-profile.json`. Fastest demo. **Use this.**
2. **Export/import** — one user exports a team taste file, another imports. Good enough to prove shared taste.
3. **Simple backend** — only if already easy. Not required.

### Applying taste

"Applying taste" = the AI references the taste knowledgebase when responding. The app does NOT need to directly manipulate other apps.

Example user queries:

- "Does this match my taste?"
- "What would our team think of this?"
- "Which option is more aligned with our style?"
- "How should I improve this?"
- "Rewrite this in my taste."
- "Give me design feedback using the team taste profile."

### Apply mode example responses

**Critique current screen** — "Does this match our team's taste?"

> Not fully. It matches the team's preference for direct copy, but the logo is too small and the layout feels too cluttered. The team profile suggests stronger brand presence, cleaner hierarchy, and more whitespace.

**Suggest improvements** — "How would I improve this?"

> Based on your taste profile:
> 1. Make the logo more prominent.
> 2. Shorten the headline.
> 3. Remove the decorative gradient.
> 4. Add more whitespace around the CTA.

**Rank options** — "Which one is more me?"

> Option B is more aligned with your taste. It has stronger hierarchy, cleaner layout, more direct copy, and less visual noise.

**Generate small output** — "Write a headline in my taste."

> A calmer way to get work done.
>
> I kept it short and avoided startup-style language because that matches your taste profile.

### Important product position

Reverse Clicky is primarily a **companion**, not an autonomous editor. It helps the user design, write, code, and critique. It does NOT need to type into apps or directly change designs for the MVP.

Core value: *the app absorbs taste and makes that taste usable.*

### Knowledgebase usage in AI calls

The taste knowledgebase should be loaded into future AI calls as context. Use personal taste in Personal mode, team taste in Team mode.

The AI should treat principles as **judgment context, not rigid rules**, and should say when evidence is weak or conflicting.

Example context block injected into AI calls:

```
Current taste context:
- Prefers strong brand presence and clear visual hierarchy.
- Prefers short, direct copy over generic startup language.
- Likes calm, spacious layouts.
- Avoids decorative effects unless they add meaning.
```

### Module responsibilities (hold-to-teach architecture)

(Lives under `ReverseClicky/Capture/`, `ReverseClicky/Analysis/`, `ReverseClicky/Apply/`, `ReverseClicky/Shared/` — see ownership rules above.)

**Reuban** edits the existing Clicky integration points (these are the *only* edits to existing files):

- **`CompanionManager.swift`** — add `@Published var tasteMode: TasteMode = .ask`, `@Published var tasteScope: TasteScope = .personal`, `@Published var pendingPrinciple: TastePrinciple? = nil`. Persist `tasteMode` + `tasteScope` to `UserDefaults`. In the existing Claude response handler, branch on `tasteMode`: in `.teach` call `Analysis.analyzeTeachMoment(transcript:screenshotData:)` and assign the result to `pendingPrinciple` (no TTS); in `.apply` call `Apply.tasteSystemPrompt(profile:scope:)` and prepend it to the existing systemPrompt before calling `ClaudeAPI`.
- **`CompanionPanelView.swift`** — add a 3-way segmented Picker (`Ask` / `Teach` / `Apply`) bound to `tasteMode`. When `tasteMode == .apply`, also show a Personal/Team toggle bound to `tasteScope`. When `pendingPrinciple != nil`, render the `PrincipleReviewCard` from the Analysis folder.
- **`leanring_buddyApp.swift`** — likely no edits needed.

`ReverseClicky/Capture/` ends up empty for MVP. (Folder still exists so future work can land there without breaking ownership rules.)

**Leonardo / `Analysis/`:**

- **`TasteExtractionPrompt.swift`** — `static func systemPrompt(transcript: String) -> String`. Returns a prompt that tells Claude: "the user has just spoken `<transcript>` while looking at the attached screenshot. Extract a single TastePrinciple as JSON with the schema shown. If the input is too vague, return `{}`." Pin the JSON schema verbatim.
- **`SessionAnalyzer.swift`** — exposes `analyzeTeachMoment(transcript:screenshotData:) async throws -> TastePrinciple`. Internally calls `ClaudeAPI.analyzeImageStreaming(images: [(screenshotData, "current screen")], systemPrompt: TasteExtractionPrompt.systemPrompt(transcript:), userPrompt: transcript, onTextChunk: { _ in })` and parses the streamed reply (Claude may wrap JSON in prose — extract the first JSON object). **No raw HTTP, no looped multi-frame logic.**
- **`PrincipleReviewCard.swift`** — SwiftUI view bound to a `TastePrinciple`. Displays domain badge + statement + evidence. Two buttons: Remember (`.dsPrimaryButtonStyle()`) calls `TasteProfileStore.appendApprovedPrinciple(...)` and clears `pendingPrinciple`; Skip (`.dsTertiaryButtonStyle()`) just clears it.
- **`TasteProfileStore.swift`** — `Codable` load/save of `taste-profile.json` in Application Support. ~80 lines. First write creates the directory. Public methods: `loadProfile() -> TasteProfile`, `appendApprovedPrinciple(_ principle: TastePrinciple) throws`.

**Leonardo / `Apply/`:**

- **`TastePromptBuilder.swift`** — `static func tasteSystemPrompt(profile: TasteProfile, scope: TasteScope) -> String`. Returns a system prompt block listing approved principles, framed as judgment context (not rigid rules). When `scope == .team`, also reads `team-profile.json` via `TeamTasteProfileStore` and unions principles deduped by `id`.
- **`TeamTasteProfileStore.swift`** — same pattern as `TasteProfileStore` but for `team-profile.json`. For MVP, only `loadTeamProfile() -> TeamTasteProfile?` is needed (Magdalena hand-writes the file).

**What no one writes (because it already exists in Clicky):**

- HTTP client / Claude wire format → use `ClaudeAPI`
- Screenshot mechanics / multi-monitor handling → already happens in the existing voice flow; the screenshot `Data` is in scope when `CompanionManager` calls Claude
- Voice capture / transcription → use `BuddyDictationManager` (already wired)
- Worker proxy / API keys → use existing `/chat` route
- Colors, button styles, radii, animations → use `DS.*`
- Menu bar panel chrome / lifecycle → edit `CompanionPanelView` content only
- Overlay window / cursor / waveform → unchanged; the waveform IS the recording indicator
- Hotkey CGEvent tap → unchanged; ctrl+option already does what we need
- TTS playback → already exists; just suppress it in `.teach` mode

### Suggested project structure (hold-to-teach)

```
ReverseClicky/
  Shared/
    TasteTypes.swift              ← frozen at hour 0 (TasteMode, TasteScope, TasteDomain, TastePrinciple, TasteProfile, TeamTasteProfile)
  Capture/                        ← Reuban — empty for MVP; integration is in existing Clicky files
  Analysis/                       ← Leonardo
    TasteExtractionPrompt.swift   ← teach-mode system prompt + JSON schema
    SessionAnalyzer.swift         ← analyzeTeachMoment(transcript:screenshotData:) → TastePrinciple
    PrincipleReviewCard.swift     ← Remember/Skip card
    TasteProfileStore.swift       ← Codable + FileManager
  Apply/                          ← Leonardo
    TastePromptBuilder.swift      ← injects principles into apply-mode system prompt
    TeamTasteProfileStore.swift   ← reads team-profile.json
  demo/                           ← Magdalena
    taste-profile.json            ← seed: 6–8 opinionated principles
    team-profile.json             ← seed: a fictional second member
    test-cases.md                 ← (transcript, screenshot) pairs for prompt tuning
    demo-script.md                ← timed 3-part walkthrough
    ui-copy.md                    ← exact strings for the mode picker, review card, toasts
```

### Privacy requirements (hard requirements for demo)

Screenshots are sensitive. The MVP must include:

- manual start/stop
- visible recording indicator at all times during capture
- local screenshot storage only
- discard-session option (CUT for MVP — quitting the app discards)
- explicit user approval before saving any principle
- no hidden background recording
- no always-on capture

Suggested UI copy:

```
Taste session active. Screenshots are being captured locally until you stop the session.
```

After session:

```
Review before saving. Nothing is added to your taste profile unless you approve it.
```

### Demo script (3 parts)

**Part 1: Absorb personal taste.** User starts a taste session and edits a landing page — makes logo bigger, removes gradient, shortens headline, adds whitespace, makes CTA more prominent. Ends session.

AI asks:

```
1. You made the logo more prominent. Remember strong brand presence?
2. You removed the gradient. Remember clean visuals over decoration?
3. You shortened the headline. Remember direct copy over startup language?
4. You added whitespace. Remember calm, spacious layouts?
```

User approves. Taste profile fills in with design + writing principles.

**Part 2: Pool team taste.** Switch to Team mode. Add or mock another member's taste (e.g. "high-contrast CTAs, minimal animations"). Team taste = union of both members.

**Part 3: Apply team taste.** Show a different design. User asks: *"Does this match our team's taste?"*

Clicky responds with a critique grounded in the pooled principles. **This proves the whole loop.**

### MVP success criteria

The MVP succeeds if it demonstrates:

1. User can start/stop a taste session.
2. Screenshots are captured during the session.
3. AI identifies meaningful creative decisions.
4. AI asks rapid-fire questions.
5. User approves taste principles.
6. Personal taste profile updates.
7. Team profile pools approved principles.
8. Clicky uses personal/team taste to critique or suggest improvements.

### Build priority

1. Session start/stop state
2. Screenshot capture using Clicky
3. Visible recording indicator
4. Key frame selection
5. Session analysis
6. Rapid-fire question UI
7. Personal taste profile JSON
8. Apply mode using personal taste
9. Team taste JSON
10. Apply mode using team taste
11. Demo polish

### Final one-liner

> Reverse Clicky is a hackathon MVP that turns short workflow sessions into a personal or team taste knowledgebase, then lets Clicky act as a companion that critiques and guides work according to that learned taste.

---

## Overview

macOS menu bar companion app. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel with companion voice controls. Uses push-to-talk (ctrl+option) to capture voice input, transcribes it via AssemblyAI streaming, and sends the transcript + a screenshot of the user's screen to Claude. Claude responds with text (streamed via SSE) and voice (ElevenLabs TTS). A blue cursor overlay can fly to and point at UI elements Claude references on any connected monitor.

All API keys live on a Cloudflare Worker proxy — nothing sensitive ships in the app.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **AI Chat**: Claude (Sonnet 4.6 default, Opus 4.6 optional) via Cloudflare Worker proxy with SSE streaming
- **Speech-to-Text**: AssemblyAI real-time streaming (`u3-rt-pro` model) via websocket, with OpenAI and Apple Speech as fallbacks
- **Text-to-Speech**: ElevenLabs (`eleven_flash_v2_5` model) via Cloudflare Worker proxy
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk via `AVAudioEngine` + pluggable transcription-provider layer. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Element Pointing**: Claude embeds `[POINT:x,y:label:screenN]` tags in responses. The overlay parses these, maps coordinates to the correct monitor, and animates the blue cursor along a bezier arc to the target.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `ClickyAnalytics.swift`

### API Proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Fetches a short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID`

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the blue cursor companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

**Transient Cursor Mode**: When "Show Clicky" is off, pressing the hotkey fades in the cursor overlay for the duration of the interaction (recording → response → TTS → optional pointing), then fades it out automatically after 1 second of inactivity.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~89 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. |
| `CompanionManager.swift` | ~1026 | Central state machine. Owns dictation, shortcut monitoring, screen capture, Claude API, ElevenLabs TTS, and overlay management. Tracks voice state (idle/listening/processing/responding), conversation history, model selection, and cursor visibility. Coordinates the full push-to-talk → screenshot → Claude → TTS → pointing pipeline. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. |
| `CompanionPanelView.swift` | ~761 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~881 | Full-screen transparent overlay hosting the blue cursor, response text, waveform, and spinner. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~100 | Protocol surface and provider factory for voice transcription backends. Resolves provider based on `VoiceTranscriptionProvider` in Info.plist — AssemblyAI, OpenAI, or Apple Speech. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~478 | Streaming transcription provider. Fetches temp tokens from the Cloudflare Worker, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based transcription provider. Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~291 | Claude vision API client with streaming (SSE) and non-streaming modes. TLS warmup optimization, image MIME detection, conversation history support. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~81 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `MacDropdownComponents.swift` | ~265 | Reusable Apple-native dropdown primitives styled like macOS Control Center (Wi-Fi/Focus/Sound). Exports `DropdownVisualEffectView` (NSVisualEffectView wrapper), `MacDropdownContainer` (translucent `.menu` material + rounded corners + hairline border + soft shadow), `DropdownSection`, `DropdownRow` (circular icon well, hover highlight, trailing slot), and a `.macDropdown(isPresented:content:)` view modifier wrapping SwiftUI's `.popover`. Uses native semantic colors so it adapts to light/dark mode. |
| `ClickyAnalytics.swift` | ~121 | PostHog analytics integration for usage tracking. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `worker/src/index.ts` | ~142 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Cloudflare Worker

```bash
cd worker
npm install

# Add secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with your keys)
npx wrangler dev
```

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
