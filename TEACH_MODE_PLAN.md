# Teach Mode — Plan

Hackathon MVP. Supersedes the hold-to-teach spec in [CLAUDE.md](CLAUDE.md). Coding agents are fast — the whole thing should ship in a few hours, not a full day.

## Shape in one sentence

Teach mode is **Loom-style**: click a button, narrate while you work, click to stop. Claude analyses transcript + screenshots and returns confident principles (auto-saved) plus a small stack of MCQ cards for ambiguous moments. Apply mode then uses those principles as context for every Clicky response. Team scope swaps the profile for a shared JSON.

## Three modes (panel toggle)

| Mode | Glow | Behaviour |
|---|---|---|
| **Ask** | blue | Existing Clicky, unchanged. |
| **Teach** | amber | Click-to-start session: continuous mic + screenshots. Click-to-stop opens review. |
| **Apply** | green | Existing Clicky, but system prompt is prepended with taste context (personal or team). |

No per-mode hotkeys. No hold-to-teach. No on-disk session folder. No TTS for the review questions.

---

# Build order — biggest wins first

Each item lands as an MVP version that demos, then optionally goes deeper if time remains. Stop at any point and the demo still works.

## 1. The absorb loop (the headline demo) — ~90 min ✅ shipped

Without this, nothing else matters. This is what the whole pitch hangs on.

**MVP (must ship):**
- **Click-to-start / click-to-stop** button in [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift). Bound to a new `teachSessionState` (idle/recording/analyzing/reviewing) on `CompanionManager`.
- **Continuous dictation.** Add a continuous-mode entry point to [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) — same AssemblyAI websocket, opened on session-start, kept open until session-stop, accumulating transcript chunks with word-level timestamps (v3 already returns them — just don't throw them away).
- **Screenshot timer.** Every 4s, call `CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` and store the cursor-screen frame in memory as `(jpegData, timestampSeconds)`. In-memory only — no disk.
- **One Claude call on stop** via existing `ClaudeAPI.analyzeImageStreaming(...)` (it already accepts multi-frame). Send up to 10 evenly-spaced frames + the full timestamped transcript. Prompt asks for JSON:
  ```json
  { "confident": [TastePrinciple, ...], "ambiguous": [{"frameIndex": 4, "question": "...", "options": ["...","...","...","..."], "principleByOption": ["...","...","...","..."]}] }
  ```
- **Save + show.** Confident principles → `TasteProfileStore.appendApprovedPrinciple(...)` automatically. Ambiguous → render the review cards (next item).

**If time:**
- Cap session length at 5 min with a soft warning.
- Toast each auto-saved principle with an Undo affordance.

## 2. Review cards (the magic moment) — ~45 min ✅ MVP shipped

The thing that makes the demo *fun* to watch.

**MVP:**
- A floating SwiftUI card shown in the panel (or near the cursor) when `pendingAmbiguous` is non-empty. One card at a time.
- Frame thumbnail at the top, question + 4 options labeled `1` `2` `3` `4`.
- Keyboard: `1`–`4` saves the matching `principleByOption[i]` and advances. `→` skip. `Esc` ends review (saves what's been answered).
- DS tokens only — `DS.Colors.surface*`, `DS.CornerRadius.*`, `DS.Spacing.*`.

**If time:**
- `←` go back, `T` to type a custom answer, slide-out animation between cards, "3 / 5" progress.

## 3. Apply mode (closes the loop) — ~30 min ✅ shipped (taste injects on every voice query, regardless of mode)

Without this, taste is captured but never used — the demo dies after part 1.

**MVP:**
- `TastePromptBuilder.tasteSystemPrompt(profile:scope:)` returns a string listing approved principles framed as judgment context, not rules.
- In `CompanionManager`'s existing Claude call site: when `tasteMode == .apply`, prepend that string to the existing `systemPrompt` before calling `ClaudeAPI`. One branch, ~5 lines.
- Smoke test: with 3 seeded principles, ask Clicky a generic question and confirm the answer references the principles.

**If time:**
- A "Show what taste is being applied" affordance in the panel (collapsed list of active principles).

## 4. Mode picker + glow (makes the system legible) — ~20 min

**MVP:**
- 3-way segmented control in `CompanionPanelView` bound to `tasteMode`. Persists to `UserDefaults`. ✅ shipped.
- Tint the cursor overlay in [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) based on `tasteMode` — blue / amber / green from `DS.Colors`.

### Directional glow language (use this to differentiate states)

The edge-glow already exists (`currentAudioPowerLevel` and `currentTTSPowerLevel` are wired). What changes is *which edges* glow and what colour, based on mode + voice state.

| Mode + state | Glow source | Reacts to | Colour |
|---|---|---|---|
| **Ask** — holding ctrl+option (listening) | Bottom edge only | Mic input level | Blue (`overlayCursorBlue`) |
| **Ask** — AI responding (TTS playing) | Top edge only | TTS playback level | Different colour from listening — accent/green or warm white. Pick whatever reads as "AI talking back" vs. "I'm listening" |
| **Teach** — recording | All four edges (full screen halo) | Mic input level | Amber (`warning`) — distinct from Ask so the user always knows the mic is open in a different mode |
| **Teach** — analyzing / Apply / idle | No glow | — | — |

Why this shape:
- **Bottom = input, top = output** is a strong directional metaphor. Listening pulls down toward the user; responding flows down from the AI.
- **Different colour** for response vs. listening keeps the two states unmistakable even at a glance.
- **Full-edge halo** in teach mode reads as "the whole environment is being observed" without any extra UI chrome. The audio reactivity reassures the user that transcription is actually happening — silence = no glow movement = something's wrong.
- All three states reuse the same audio-power publishers; only the edge masks and colours change.

**If time:**
- Persistent edge pill `Teaching — 0:42` while a session is active.
- One-line ElevenLabs intro at the start of review (*"Got it — I have 5 quick questions."*).

## 5. Team scope (the boss → employee narrative) — ~20 min ✅ shipped

**MVP:**
- Personal/Team toggle in the panel, visible only when `tasteMode == .apply`. Bound to `tasteScope`.
- `TeamTasteProfileStore.loadTeamProfile()` reads a hand-written `team-profile.json` from `~/Library/Application Support/com.learning-buddy.clicky/`.
- In `TastePromptBuilder`: when `scope == .team`, union team + personal principles deduped by `id`.
- Magdalena hand-writes `team-profile.json` with 4–6 opinionated "boss" principles.

**If time:** nothing. Team is a demo framing, not an engineering problem.

---

## What we are NOT building

- Hold-to-teach (cut entirely)
- Per-mode hotkeys
- On-disk session folders
- Frame diffing or smart frame selection (evenly-spaced is fine)
- Edit-the-principle UI (Remember / Skip / optional type-custom only)
- Websocket reconnect logic (log + carry on)
- TTS for the questions themselves
- Live multi-laptop team sync

## Architectural notes

The only non-trivial change vs. existing Clicky is **continuous dictation**: `BuddyDictationManager` is currently push-to-talk only (open on key-down, close on key-up). Add a sibling entry point that opens on session-start and stays open. Read the file before deciding whether it's a flag or a sibling class.

Everything else reuses what's already there:

| Capability | Reuse |
|---|---|
| Screenshots | `CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` |
| Claude vision (multi-frame) | `ClaudeAPI.analyzeImageStreaming(...)` |
| Glow / cursor overlay | `OverlayWindow` — change tint based on `tasteMode` |
| Design tokens | `DS.Colors.warning` / `success` / `overlayCursorBlue` |
| Panel UI | New section inside `CompanionPanelView`'s VStack |

## Failure modes (cheap, not engineered)

- Malformed JSON from Claude → log, show a single toast ("Couldn't parse the review — narration was saved"), don't crash.
- Websocket drops mid-session → log, keep going with the partial transcript.
- Memory pressure from frames → only an issue past ~5 min sessions; cap and move on.

## Total estimate

~3.5 hours of focused work end-to-end, parallelisable across two coding agents. Demo polish on top.
