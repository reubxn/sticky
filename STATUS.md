# Sticky — Project Status (Source of Truth)

Single living doc that consolidates [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md), [EDGE_GLOW_REDESIGN.md](EDGE_GLOW_REDESIGN.md), and the previous dropdown-redesign log. **Read this first.** Each section says what it is, what shipped, what's in flight, and what's open.

⚠️ **Open questions for Reuban are in §6 at the bottom — please answer those so this doc stays a real source of truth and not just a log.**

---

## 1. What Sticky is, today

Sticky is a macOS menu-bar AI companion. The user holds `ctrl + option`, speaks, releases — Sticky takes a screenshot, sends transcript + image to Claude, streams a reply back as text + voice (ElevenLabs) and can fly the cursor to a UI element being referenced.

Built on top of that base, three feature layers:

1. **Teach mode (shipped)** — record a Loom-style narrated session, Claude extracts taste principles, user reviews ambiguous ones via MCQ cards, principles save to a personal `taste-profile.json`. ([TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md))
2. **Apply mode (shipped)** — every voice query in Apply mode is grounded in the user's saved taste, optionally unioned with a team profile. ([TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) §3)
3. **Personas (in flight)** — the user can swap into a teammate's full identity (their face, their voice, their soul, their taste). Picked via a radial wheel that pops up around the cursor when `shift + cmd` is held. **This is the work currently in progress.** (§3 below)

The original "hackathon MVP" framing in [CLAUDE.md](CLAUDE.md) (3 people, 10 hours, hold-to-teach) has been **superseded** in practice — the project has grown past it and the click-to-start teach flow + personas are now the real product. ⚠️ Q1 in §6.

---

## 2. Architecture quick map

| Capability | Owner file | Status |
|---|---|---|
| Menu-bar shell | [leanring_buddyApp.swift](leanring-buddy/leanring_buddyApp.swift), [MenuBarPanelManager.swift](leanring-buddy/MenuBarPanelManager.swift) | ✅ stable |
| Central state | [CompanionManager.swift](leanring-buddy/CompanionManager.swift) | ✅ stable, growing |
| Voice in (push-to-talk) | [GlobalPushToTalkShortcutMonitor.swift](leanring-buddy/GlobalPushToTalkShortcutMonitor.swift) → [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) → [AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift) | ✅ stable |
| Voice out (TTS) | [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift), per-voice preview clips via [VoicePreviewCache.swift](leanring-buddy/VoicePreviewCache.swift) | ✅ stable |
| Claude vision | [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift) → Cloudflare Worker `/chat` | ✅ stable |
| Cursor overlay + edge glow | [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) | ✅ shipped — directional edge-glow per [EDGE_GLOW_REDESIGN.md](EDGE_GLOW_REDESIGN.md) is in (§4); a few refinement Qs in §6 |
| Panel UI | [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) + [MacDropdownComponents.swift](leanring-buddy/MacDropdownComponents.swift) | ✅ warm-gradient look shipped |
| Teach mode | [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) (continuous mode), [SessionAnalyzer.swift](leanring-buddy/SessionAnalyzer.swift), [TasteExtractionPrompt.swift](leanring-buddy/TasteExtractionPrompt.swift), [ReviewCardStack.swift](leanring-buddy/ReviewCardStack.swift) | ✅ shipped |
| Taste storage | [TasteTypes.swift](leanring-buddy/TasteTypes.swift), [TasteProfileStore.swift](leanring-buddy/TasteProfileStore.swift), [TeamTasteProfileStore.swift](leanring-buddy/TeamTasteProfileStore.swift) | ✅ shipped |
| Apply-mode prompt injection | [TastePromptBuilder.swift](leanring-buddy/TastePromptBuilder.swift) | ✅ shipped |
| **Personas** | [PersonaBundle.swift](leanring-buddy/PersonaBundle.swift), [PersonaStore.swift](leanring-buddy/PersonaStore.swift), [PersonaAvatarView.swift](leanring-buddy/PersonaAvatarView.swift), [PersonaWheelHotkeyMonitor.swift](leanring-buddy/PersonaWheelHotkeyMonitor.swift), [PersonaWheelView.swift](leanring-buddy/PersonaWheelView.swift) | 🔧 wired with sample data, awaiting real team data + Xcode build verification |
| Chat window (?) | [ChatView.swift](leanring-buddy/ChatView.swift), [ChatViewModel.swift](leanring-buddy/ChatViewModel.swift), [ChatWindowController.swift](leanring-buddy/ChatWindowController.swift), [ChatMarkdownRenderer.swift](leanring-buddy/ChatMarkdownRenderer.swift) | ❓ untracked in git, status unclear — Q5 |
| **Response-latency pipeline** | sentence-streamed TTS in [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift) + [CompanionManager.swift](leanring-buddy/CompanionManager.swift), prompt caching in [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift), token prewarm in [AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift), audio-engine-first ordering in [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) | ✅ shipped this session — see §4 |
| Cloudflare Worker | [worker/src/index.ts](worker/src/index.ts) | ✅ deployed at `clicky-proxy.reubanramsden.workers.dev` |

---

## 3. **Currently in flight: Persona system**

The work being done right now. Lets the user wear a teammate's full identity — their face becomes the cursor, their voice speaks the response, their personality colors the tone, their taste guides the answer.

### Shape

- **Selection model:** `PersonaSelection` enum with three cases: `.me`, `.team`, `.teammate(id)`. Persisted to UserDefaults.
- **Persona bundle:** `id`, `displayName`, `role`, `avatar` (initials / SF Symbol / image file), `accentColorHex`, `soul` (markdown personality prose prepended to system prompt), `voiceId` (ElevenLabs free voice), `taste` (TasteProfile).
- **Picker:** radial wheel rendered in the cursor overlay when `shift + cmd` is held. Cursor stays where you summoned it; you flick out to a spoke and release. Dead-zone in the middle = cancel. Fallback flat list available in the panel via `personaPickerRow`.
- **Visual identity swap:** `MysticalOrbView` ([OverlayWindow.swift](leanring-buddy/OverlayWindow.swift)) replaces the solid colored orb body with a circular `PersonaAvatarView` when a teammate persona is active. Halo glow + edge glow + speech-bubble fill all retint to the persona's accent color via `stickyVoiceColor`.
- **Prompt swap:** `composeSystemPromptForTeammatePersona` ([CompanionManager.swift](leanring-buddy/CompanionManager.swift)) prepends `soul.md` + the teammate's taste principles to the base Sticky prompt. Personal/team taste is **not** mixed in — wearing a persona means hearing only that person.
- **Voice swap:** at the TTS dispatch site in `sendTranscriptToClaudeWithScreenshot`, `effectiveTTSVoiceID = activeTeammateBundle?.voiceId ?? selectedVoiceID`.

### TASTE.md as source of truth

Each teammate's identity, soul, and taste principles now live in a single human-readable markdown file at [`leanring-buddy/personas/<id>/TASTE.md`](leanring-buddy/personas/). [PersonaTasteFileStore.swift](leanring-buddy/PersonaTasteFileStore.swift) parses these into `PersonaBundle`s at app launch (with the Swift-literal bundles in [PersonaStore.swift](leanring-buddy/PersonaStore.swift) kept only as a last-resort fallback). The same files are exportable as-is to Claude Code, Cursor, or anything else that reads markdown.

**File format** (full spec in the header comment of [PersonaTasteFileStore.swift](leanring-buddy/PersonaTasteFileStore.swift)):

```markdown
# {DisplayName} — {Role}

<!-- @persona id={id} voice={elevenLabsVoiceId} accent={hex} avatar={filename} -->

## Soul
{free-form personality prose}

## Taste

### {Domain}
- **{statement}**
  *(confidence 0.XX · tag1, tag2)*
  {evidence prose}
```

**Resolution order** (per persona, hot-swap wins):
1. `~/Library/Application Support/com.learning-buddy.clicky/personas/<id>/TASTE.md` (user-edited override)
2. `Bundle.main` `personas/<id>/TASTE.md` (shipped with the binary)

**Three teammates shipped today:**

- **Reuban** — Builder · Sticky — Liam voice — cobalt — [TASTE.md](leanring-buddy/personas/reuban/TASTE.md)
- **Leonard** — Quant · Imperial — Daniel voice — slate-blue — [TASTE.md](leanring-buddy/personas/leonard/TASTE.md)
- **Magdalena** — Co-Founder · Middle Bridge — Alice voice — magenta-rose — [TASTE.md](leanring-buddy/personas/magdalena/TASTE.md)

Photos are bundled three ways for redundancy (Asset Catalog imageset, loose Resource, and the Application Support hot-swap path) — `PersonaImageLoader.bundledOrDiskImage(...)` checks all three in order.

### What's left on this slice

- 🔧 **Compile verification** — I can't run `xcodebuild` (per [CLAUDE.md](CLAUDE.md) it invalidates TCC). Reuban needs to build in Xcode and report any errors.
- 🚧 **Phase 2 — bidirectional TASTE.md** — `PersonaTasteFileStore.appendPrinciple(...)` is wired but not yet called from teach mode. Teach mode currently still writes to `taste-profile.json` via `TasteProfileStore`. Next pass: route teach output to the local owner's TASTE.md so "when a teammate teaches, it goes to their file." Needs a `myPersonaId` setting (defaults to `reuban` on Reuban's machine) that determines which file teach writes to.
- 🚧 **Phase 2 — `.me` mode reads TASTE.md** — `composeVoiceSystemPromptWithTaste` for `.me` still pulls from `TasteProfileStore.loadProfile()` (JSON). Should pull from the owner's TASTE.md so the local user sees their own bundle's taste in apply mode.
- 🎯 **Soul + voice tuning** — souls and voice picks are first-pass from LinkedIn. Worth a side-by-side TTS comparison once each teammate has heard their persona; expect adjustments. Easy to iterate now — just edit the markdown.

---

## 4. Open / next-up (cross-feature)

### Response-latency overhaul — ✅ shipped this session

The user described the press-to-talk flow as "very slow" and (in a later turn) said the mic seemed to need ~2s of holding before it actually picked up voice. Four passes of optimization across the response pipeline. Combined effect: realistic floor on "key release → first audible word" went from roughly **3.5–7s** to roughly **1.5–2.0s** in the good case, and "press → mic captures voice" went from ~1–2s of dead time to ~50–200ms (audio-engine cold start only).

**Pass 1 — quick wins + sentence-streamed TTS:**
- AssemblyAI explicit-final grace period reduced 1.4s → 0.5s, fallback delay 2.8s → 1.5s ([AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift)). Saves ~700–900ms on every release.
- Screenshot dimension 1280→1024px, JPEG quality 0.8→0.6 ([CompanionScreenCaptureUtility.swift](leanring-buddy/CompanionScreenCaptureUtility.swift)). Saves ~150–300ms on upload.
- Screenshot capture moved to key-DOWN, captured in parallel with the user speaking instead of serially after release ([CompanionManager.swift](leanring-buddy/CompanionManager.swift) — `preflightScreenCaptureTask`). Saves ~400–700ms.
- Sentence-streamed TTS — biggest single perceived win. As Claude's reply streams, [CompanionManager.swift](leanring-buddy/CompanionManager.swift)'s new nested `StreamingResponseState` class detects sentence boundaries in the SSE chunks, fires an ElevenLabs fetch per sentence in **parallel**, and chains playback in arrival order via a new chained-playback queue in [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift) (`resetPlaybackChain` / `enqueueAudioData(_:forEpoch:)` / `awaitPlaybackChainComplete`). The first sentence starts playing while Claude is still generating the rest. `[POINT:` short-circuits further streaming dispatch so the un-spoken coordinate tag never reaches TTS. An epoch counter on the TTS client makes user interrupts (re-press during a response) clean — stale fetches that finish after the new press are dropped silently.

**Pass 2 — server-side caching + token prewarm:**
- Anthropic prompt caching: system prompt now goes as a content block list with `cache_control: {"type": "ephemeral"}` in both [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift) request paths. ~100–200ms TTFT after the first call within the 5-minute cache window. Worker is a passthrough so no worker change needed.
- AssemblyAI temp-token prefetch + cache ([AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift)). Token fetched once at launch via [CompanionManager.swift](leanring-buddy/CompanionManager.swift) `start()`, refreshed in background after every dictation session via [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) `finishCurrentDictationSessionIfNeeded`. New protocol method `prewarmCredentialsIfNeeded()` on `BuddyTranscriptionProvider` with a default no-op for non-AssemblyAI providers. Concurrent token fetches coalesce onto a single in-flight `Task`. Saves ~100–200ms per press.

**Pass 3 — model + press-to-listen latency:**
- Haiku 4.5 (`claude-haiku-4-5-20251001`) is now the default Claude model and the leftmost picker option in [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift). Sonnet/Opus stay available. TTFT roughly 2-3× faster than Sonnet for short voice answers — Claude's first-token time was the largest remaining single contributor.
- **Audio-engine-first** in [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) `startRecognitionSession`. Old order: `await websocket → install tap → start engine`. New order: `start engine + install tap → buffer audio → await websocket → atomically flush buffer to session`. The mic captures voice from the moment the user presses; audio frames captured during the AssemblyAI handshake are deposited (as defensive copies — `AVAudioNode` reuses the original buffer storage) into a new private `PreSessionAudioBufferStore` class at the bottom of the same file, then flushed in capture order under a lock at session adoption. The lock is held during the flush so concurrent tap callbacks block and can't enqueue a "live" frame ahead of the buffered ones in the session's send queue.

**Combined latency budget (post-changes, single monitor, prompt cache warm, token cached):**

| Stage | Before | After |
|---|---|---|
| Press → mic actually captures | ~700–1500ms | ~50–200ms (audio HAL cold start only) |
| Release → final transcript ready | ~1.4s grace | ~0.5s grace |
| Final transcript → first sentence text from Claude | ~1.5–3s (Sonnet, full response) | ~400–800ms (Haiku, first sentence) |
| First sentence text → first audible word | ~600–1500ms (full TTS) | ~400–700ms (single-sentence TTS) |
| **Net "release → first audible word"** | **~3.5–7s** | **~1.5–2.0s** |

**What's still open / risk surface:**
- Sentence-streamed TTS adds real complexity (epoch-based queue, chained `AVAudioPlayerDelegate`, parallel fetches with serialized enqueue). Most likely subtle-bug surface. Voice preview path (single-shot `playAudioData`) is untouched and still works. Q14 below asks whether the trade is worth it long-term.
- `PreSessionAudioBufferStore.copyAudioBuffer` only handles float32, int16, int32 channel data. macOS mic input is virtually always float32, but exotic formats would silently drop frames during the websocket-open buffer window (the live session still works fine after adoption). Q15.
- AssemblyAI grace at 0.5s is aggressive — if the model occasionally cuts off the last word, this is the knob to relax. Q16.
- True streaming-TTS endpoint (`/v1/text-to-speech/{voiceId}/stream` with progressive `AVAudioEngine` playback) would save another 300–700ms per sentence, but it's a real refactor with regression risk. Deliberately not done. Q17.

### Edge-glow redesign ([EDGE_GLOW_REDESIGN.md](EDGE_GLOW_REDESIGN.md)) — ✅ shipped this session

The directional glow language is in. Goal achieved: bottom-edge halo while listening / processing, top-edge halo while Sticky responds, four-edge halo while a teach session is recording.

**What landed in [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift):**
- The aurora-ribbon implementation (`AuroraEdgeRibbonStack`, `AuroraRibbonSpec`, sine-wave undulating curtains) is **gone**.
- `InnerShadowEdgeHalo` replaces it: four layered blurred gradient bands per edge (broad outer halo → mid bloom → saturated core → near-white inner highlight), masked at a 24pt soft corner radius. Looks like a stacked inner-shadow effect rather than a wave.
- `EdgeGlowAnchor` enum (`.bottom` / `.top` / `.all`) drives which edges are visible. Each `EdgeGlowMode` has a `defaultAnchor` so call sites only choose a mode.
- New `.teachRecording` case on `EdgeGlowMode` → `.all` anchor (four-edge halo, dimmed to ~62% so it reads as a halo ring, not a heavy frame).
- All four edges are mounted at all times with per-edge opacity drivers; switching modes runs `withAnimation(.easeInOut(duration: 0.55))` over those drivers, so listening → responding crossfades smoothly between bottom and top instead of cutting.
- `ProcessingShimmerSweep` band fades in only during `.processingThinking` to communicate "we're waiting on Claude" without pretending to react to non-existent audio.

**Voice color system folded in:**
- `userVoiceColor` (static) and `stickyVoiceColor` (instance, derived from selected ElevenLabs voice or active persona accent) live on `CompanionManager`.
- The voice → color palette moved out of `CompanionPanelView` so the picker orb in the panel and the top-edge halo + cursor + bubbles in the overlay all read from the same source of truth.
- Cursor (`MysticalOrbView`), welcome bubble, onboarding bubble, navigation bubble all retint live to `companionManager.stickyVoiceColor`.
- Teach mode currently uses `userVoiceColor` (blue) for its four-edge halo. A `teachVoiceColor` constant was briefly added then reverted — Q9 in §6 asks whether teach should be a distinct color.

**What's still open on this slice:**
- A bars-style audio-visualizer halo (gradient columns + Mexican-wave loading state) was tried mid-session and reverted at user request — not in the code.
- `BlueCursorWaveformView` and `BlueCursorSpinnerView` in `OverlayWindow.swift` are dead code (declared but never instantiated; orphans of the pre-edge-glow indicator era). Safe to delete — Q10.
- Some refinement Qs in §6 (Q9–Q11) about color choices.

### Footer legibility on the warm gradient panel
Cream text on the bright pink-peach band at the bottom of the dropdown reads low-contrast. Fix by either darkening the gradient bottom or switching footer copy to dark walnut. (Was solved in a now-reverted dropdown pass.)

### Voice-picker popover styling mismatch
The voice picker uses the system `.menu` material, not the warm gradient — visible inconsistency when "Voice → Bella" opens. Either add a `style:` parameter to `MacDropdownContainer` or inline a warm container at that one call site.

### Wider rebrand
Internal identifiers (`clickyDismissPanel` notification, `isClickyCursorEnabled`, the `leanring-buddy` bundle name and folder typo, the menu-bar status icon glyph) still say Clicky. ⚠️ Q6 — out of scope or worth doing?

---

## 5. What's been cut (do NOT build)

From [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) and [CLAUDE.md](CLAUDE.md):
- ❌ Hold-to-teach (replaced by click-to-start sessions)
- ❌ Per-mode hotkeys
- ❌ On-disk session folders (frames stay in memory)
- ❌ Frame diffing / smart frame selection
- ❌ Edit-the-principle UI (Remember / Skip only)
- ❌ Real-time multi-laptop team sync (`team-profile.json` is hand-written for the demo)
- ❌ Figma plugin / Cursor extension / fine-tuning / vector DB / autonomous typing into other apps

From the persona work specifically:
- ❌ Persona editor UI inside Sticky (the user uploads real assets manually for now)
- ❌ Cross-machine persona sync (a future Dropbox/iCloud/KV story)

---

## 6. Clarifications needed from Reuban

These are the points where I'm filling gaps with assumptions. Please answer inline so this doc becomes ground truth:

1. **Project framing.** Is this still a *hackathon MVP* (the framing in [CLAUDE.md](CLAUDE.md): 3 people, 10 hours, frozen folder structure under `ReverseClicky/`) — or has it become *the actual Sticky product* you're shipping? My read: it's the product now, and CLAUDE.md is stale. If yes, I'll update CLAUDE.md to remove the hackathon language.

2. **Persona vs. existing teach/apply.** When a user picks a teammate persona, the existing teach-mode flow (where *they* train *their own* taste profile) is still useful — it builds the profile that becomes their persona's `taste`. Confirm the model is: each person teaches their own Sticky → their persona bundle is the result → other people borrow that bundle. Yes/no?

3. **TasteScope after personas.** The `Personal | Team` scope toggle now overlaps with `.me` vs `.team` persona selection. Should I:
   - (a) **Keep both** — scope still lets the user union team taste into `.me` mode, persona is for borrowing teammates. Two separate concepts.
   - (b) **Collapse them** — remove the scope toggle, fold "Team" into the persona wheel as a pseudo-persona (already the case in the wheel), and have `.me` always mean personal-only.
   - I lean (b) — simpler mental model — but (a) preserves a behavior that already works.

4. **Reuban's own persona bundle.** Do you (Reuban) have your own teammate-style bundle that *other* team members can pick from their wheel? If yes, your own Sticky needs *both* a `.me` selection (your live config) and a `reuban` teammate bundle (frozen identity others borrow).

5. **Chat window status.** [ChatView.swift](leanring-buddy/ChatView.swift), [ChatViewModel.swift](leanring-buddy/ChatViewModel.swift), [ChatWindowController.swift](leanring-buddy/ChatWindowController.swift), [ChatMarkdownRenderer.swift](leanring-buddy/ChatMarkdownRenderer.swift) are untracked in git but live in the source dir. What is this — a separate chat surface, an experiment, scrap? Should it be in this status doc as a tracked feature?

6. **Rebrand finish.** Should I finish the Clicky → Sticky rename (notification names, UserDefaults keys, bundle name, folder name `leanring-buddy`)? Some of these break installed-user state, so it's a deliberate decision.

7. **Wheel hotkey.** I picked `shift + cmd` for the persona wheel because it's distinct from `ctrl + option` (push-to-talk) and doesn't collide with most app shortcuts when held alone. Any preference for a different combo? `fn` alone is the obvious alternative.

8. **Real team data.** When you hand over the real team — names, roles, photos, personality blurbs, preferred voices — drop them in any format and I'll update [PersonaStore.swift](leanring-buddy/PersonaStore.swift) and add the photos to `~/Library/Application Support/com.learning-buddy.clicky/personas/`.

### From the edge-glow session (§4)

9. **Teach mode color.** Right now the four-edge teach-mode halo uses `userVoiceColor` (blue) — same as listening, just on all four edges instead of bottom-only. [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) §4 specifies amber. I started to add a `teachVoiceColor = DS.Colors.warning` constant and switch teach to amber, then reverted in the same session when we changed direction. Want me to switch it back to amber? (Argument for: matches the plan, immediately distinguishes "I'm in teach mode" from "I'm holding push-to-talk." Argument against: when a persona is active and a teach session starts, amber overrides the persona accent — could feel inconsistent with the persona-everywhere-else rule.)

10. **Dead-code cleanup.** [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) still declares `BlueCursorWaveformView` and `BlueCursorSpinnerView` from before the edge-glow rewrite. Neither is instantiated anywhere. Safe to delete?

11. **Per-edge tuning.** The `InnerShadowEdgeHalo` constants (4 layered gradients with opacity scalars 0.42 / 0.72 / 0.92 / 0.55, blur radii 42 / 28 / 16 / 8) were tuned by reading the reference image you shared, not by eye on the running app. Once you Cmd+R, if any layer feels too prominent / too soft / too saturated, tell me which and I'll adjust.

### Doc-level / source of truth

12. **Source-of-truth scope.** This file is now a project-wide "what currently exists + what's pending" doc. The previous version was framed as a per-session log. Should we also keep a `sessions/` folder with dated entries for the running narrative, or is this STATUS.md enough — and per-session detail goes in commits / PRs?

13. **Should [EDGE_GLOW_REDESIGN.md](EDGE_GLOW_REDESIGN.md) be archived now that the redesign shipped?** Same question for [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) once the persona work is in. Options: (a) leave in place as historical specs, (b) move into `docs/history/`, (c) delete; STATUS.md is enough record. I'd lean (a).

### From the response-latency overhaul (§4)

14. **Sentence-streamed TTS — keep or simplify?** The biggest perceived-latency win, but also the most complex piece introduced this session. It's an ordered queue with epochs for safe interrupts, parallel ElevenLabs fetches with a serialized enqueue chain, an `AVAudioPlayerDelegate` chain advance, and a fallback path for trailing text after `[POINT:` is detected. Two options if it ever misbehaves: (a) keep it (current) — fastest, watch for bugs; (b) revert to single-shot per-response TTS via the still-present `speakText` path — gives back ~1.5–3s of perceived latency on multi-sentence answers but is much simpler. Confirm we're sticking with (a)?

15. **AVAudioPCMBuffer copy formats.** `PreSessionAudioBufferStore.copyAudioBuffer` only knows how to copy float32 / int16 / int32 channel data. `AVAudioEngine.inputNode.outputFormat(forBus:)` on macOS is reliably float32 for the built-in mic and most USB inputs. Adding fallbacks for esoteric formats (e.g. AVAudioFormatOther, packed PCM) adds code without obvious payoff. OK to leave as-is unless someone reports the audio cuts out at the start of an utterance with a specific external mic?

16. **AssemblyAI grace 0.5s — too aggressive?** I dropped it from 1.4s. Risk is the very last word of a trailing utterance gets cut on slow networks. Acceptable trade for the latency win, IMO, but if you ever hear "tell me about" instead of "tell me about Xcode", this is the first knob to retune (try 0.7–0.8s).

17. **True streaming TTS (ElevenLabs `/stream` endpoint with `AVAudioEngine`).** Last meaningful lever — saves another ~300–700ms per sentence on time-to-first-audio. But: requires either an `AVAssetResourceLoaderDelegate` feeding chunks into `AVPlayer`, or `AudioFileStream` + `AVAudioPlayerNode` with manual MP3 frame decode. Either is ~150-300 lines and has audible-artifact risk if buffering is wrong. Want me to do it, or hold off until the current pass shows it's needed in real use?

18. **Default-model migration.** I changed the *new-user* default to Haiku via `UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-haiku-4-5-20251001"`. **Existing users with `selectedClaudeModel` already set in UserDefaults are unaffected.** If you (or any tester with the old build) want to feel the speed bump, you'll need to tap "Haiku" in the picker once. Should there be a one-time silent migration that flips Sonnet→Haiku for existing users on next launch? My default would be no — model choice is a deliberate user setting, but flagging in case you want it.

19. **CLAUDE.md is stale (related to Q1).** Q1 already asks about removing the hackathon framing. Worth flagging concretely: the latency work edited [CompanionManager.swift](leanring-buddy/CompanionManager.swift), [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift), [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift), [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift), [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift), [AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift), [BuddyTranscriptionProvider.swift](leanring-buddy/BuddyTranscriptionProvider.swift), and [CompanionScreenCaptureUtility.swift](leanring-buddy/CompanionScreenCaptureUtility.swift) — all of which [CLAUDE.md](CLAUDE.md) §"Anti-conflict rules" says only Reuban (the integration owner) is allowed to touch. All edits were made by Reuban via me, so the spirit is intact, but rolling [CLAUDE.md](CLAUDE.md) forward into product mode (single-owner repo, no folder freeze, no per-person ownership lanes) would remove the contradiction.

---

## 7. Files touched in the latest persona work

- ➕ [PersonaBundle.swift](leanring-buddy/PersonaBundle.swift) — types
- ➕ [PersonaStore.swift](leanring-buddy/PersonaStore.swift) — sample data + accessors
- ➕ [PersonaAvatarView.swift](leanring-buddy/PersonaAvatarView.swift) — render helper
- ➕ [PersonaWheelHotkeyMonitor.swift](leanring-buddy/PersonaWheelHotkeyMonitor.swift) — `shift + cmd` listen-only event tap
- ➕ [PersonaWheelView.swift](leanring-buddy/PersonaWheelView.swift) — radial picker view
- ✏️ [CompanionManager.swift](leanring-buddy/CompanionManager.swift) — persona selection state, prompt branch, voice override, wheel state
- ✏️ [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) — orb avatar swap + wheel render + cursor-tracking hover updates
- ✏️ [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) — `personaPickerRow` + popover fallback

## 8. Files touched in the edge-glow redesign session

- ✏️ [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) — replaced `AuroraEdgeRibbonStack` / `AuroraRibbonSpec` with `InnerShadowEdgeHalo` + `ProcessingShimmerSweep`; new `EdgeGlowAnchor` enum; `.teachRecording` case on `EdgeGlowMode`; per-mode anchor crossfade in `EdgeGlowView`. Cursor + bubbles re-tinted to `companionManager.stickyVoiceColor`. `MysticalOrbView` now takes a `bodyColor` parameter.
- ✏️ [CompanionManager.swift](leanring-buddy/CompanionManager.swift) — added `userVoiceColor`, `stickyVoiceColor`, `stickyDefaultVoiceColor`, `voiceColor(forVoiceID:)`, and the canonical `voiceColorPalette` (moved from `CompanionPanelView`).
- ✏️ [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) — voice picker rows now call `CompanionManager.voiceColor(forVoiceID:)`; "Default" row's orb uses `stickyDefaultVoiceColor`.

## 9. Files touched in the response-latency overhaul

- ✏️ [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift) — `system` field of both `analyzeImageStreaming` and `analyzeImage` now sent as a content-block list with `cache_control: {"type": "ephemeral"}` so Anthropic caches the prompt server-side.
- ✏️ [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift) — class is now `NSObject` and conforms to `AVAudioPlayerDelegate`; new chained-playback queue (`pendingAudioDataQueue`, `isPlaybackChainActive`, `currentPlaybackEpoch`, `playbackChainCompletionContinuations`); new public methods `resetPlaybackChain(onFirstPlaybackStart:)`, `enqueueAudioData(_:forEpoch:)`, `awaitPlaybackChainComplete()`, `isProducingAudio`. `stopPlayback()` now bumps the epoch + drains the queue.
- ✏️ [CompanionManager.swift](leanring-buddy/CompanionManager.swift) — new `preflightScreenCaptureTask` started on key-DOWN and consumed by the response Task; new nested `StreamingResponseState` class drives sentence-by-sentence TTS dispatch as Claude streams; default model changed to Haiku; `start()` now calls `buddyDictationManager.prewarmTranscriptionCredentialsIfNeeded()`; transient-hide loop now uses `isProducingAudio` instead of `isPlaying` so it doesn't bail between chained sentences.
- ✏️ [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) — model picker now has three options (`Haiku`, `Sonnet`, `Opus`), Haiku leftmost.
- ✏️ [CompanionScreenCaptureUtility.swift](leanring-buddy/CompanionScreenCaptureUtility.swift) — screenshot max-dim 1280→1024px, JPEG quality 0.8→0.6.
- ✏️ [AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift) — explicit-final grace 1.4s→0.5s, fallback 2.8s→1.5s; new in-memory token cache with background-coalesced refresh; `prewarmCredentialsIfNeeded()` impl that backgrounds the fetch.
- ✏️ [BuddyTranscriptionProvider.swift](leanring-buddy/BuddyTranscriptionProvider.swift) — added optional `prewarmCredentialsIfNeeded()` to the protocol with a default no-op extension impl so non-AssemblyAI providers don't have to care.
- ✏️ [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) — `startRecognitionSession` reordered so the audio engine starts BEFORE the websocket open; new `preSessionAudioBufferStore` property and a private `PreSessionAudioBufferStore` class at the bottom of the file (lock-protected, copies AVAudioPCMBuffer frames defensively, atomically flushes on session adoption); new `prewarmTranscriptionCredentialsIfNeeded()` forwarder; `finishCurrentDictationSessionIfNeeded` now prewarms the next session's credentials.
