# Sticky — Agent Instructions

<!-- Single source of truth for AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## What Sticky is

Sticky is a macOS menu-bar AI companion that wears your team's taste. It lives in the status bar (no dock icon, no main window) and answers in the voice and taste of whichever **persona** the user is currently wearing.

The user's whole interaction with Sticky is shaped by one of three modes — but only one of them, **Ask**, is something the user explicitly invokes. The other two compose on top of it.

### Ask — the main loop

Hold `ctrl + option`, speak, release. On release:

1. [BuddyDictationManager](leanring-buddy/BuddyDictationManager.swift) finalizes the transcript (AssemblyAI streaming).
2. [CompanionScreenCaptureUtility](leanring-buddy/CompanionScreenCaptureUtility.swift) returns a JPEG of every screen. Capture is actually started on key-*down* so it overlaps with the user speaking — see `preflightScreenCaptureTask` in [CompanionManager.swift](leanring-buddy/CompanionManager.swift).
3. The active persona's `TASTE.md` (soul + principles) is composed into the system prompt by `composeVoiceSystemPromptWithTaste()`.
4. [ClaudeAPI](leanring-buddy/ClaudeAPI.swift) streams the reply via SSE.
5. Sentences are dispatched to [ElevenLabsTTSClient](leanring-buddy/ElevenLabsTTSClient.swift) as they finalize so playback starts before Claude is done generating.
6. If the reply contains `[POINT:x,y:label[:screenN]]`, the blue cursor in [OverlayWindow](leanring-buddy/OverlayWindow.swift) flies along a bezier arc to that pixel on the right monitor. Replies can contain **multiple inline `[POINT:...][BUBBLE:...]` pairs** for multi-step pointing — each waypoint fires as the speech segment immediately preceding it begins playing through ElevenLabs, so the cursor stays locked to the spoken sentence. Inline pairs are extracted by the streaming parser in `StreamingResponseState`, attached to their preceding speech segment, and flown via the per-segment `onSegmentStart` hook on [ElevenLabsTTSClient](leanring-buddy/ElevenLabsTTSClient.swift). Single trailing-tag pointing still works the same way as before for the common one-step case.
7. If the reply ends with `[USED:P1,T2]`, those short labels are resolved back to `TastePrinciple` objects and rendered in `AppliedPrinciplesChip` so the user can see which principles informed the answer.
8. If the reply ends with `[ACTION:start_notes]` or `[ACTION:stop_notes]`, Sticky waits for the spoken acknowledgement to finish playing (polls `ElevenLabsTTSClient.isPlaybackChainActive`, hard-capped at 4s) and then calls `startTeachSession()` / `stopTeachSession()`. Lets the user verbally start a notes session ("start taking notes for me") instead of clicking the panel button. Parsed by `parseActionTag(from:)` and fired via `scheduleVoiceActionAfterAcknowledgement(_:)` in [CompanionManager.swift](leanring-buddy/CompanionManager.swift).

### Teach — give the active persona context

The user clicks **Start Teach Session** in the menu bar panel — or asks Sticky verbally ("start taking notes", "watch what i'm doing") — and works normally while narrating. Sticky captures a frame every 4s and runs continuous dictation in the background. The user clicks **Stop** or says "stop taking notes".

[SessionAnalyzer.analyzeTeachSession](leanring-buddy/SessionAnalyzer.swift) picks up to 10 evenly-spaced frames, sends them to Claude with the prompt in [TasteExtractionPrompt.swift](leanring-buddy/TasteExtractionPrompt.swift), and parses the JSON reply into a `TeachSessionResult` (confident principles + ambiguous moments).

The result surfaces as a [TeachSessionResultCard](leanring-buddy/TeachSessionResultCard.swift) inside the panel — checkboxes for confident principles, a hint about ambiguous ones. If the user clicks **Save**, ambiguous moments promote into a [ReviewCardStack](leanring-buddy/ReviewCardStack.swift) (MCQ cards). On approval, principles are appended to the **active persona's** `TASTE.md` via `PersonaTasteFileStore.appendPrinciple(...)` and (legacy) to `taste-profile.json` via `TasteProfileStore.appendApprovedPrinciples(...)`.

Future Ask responses while wearing that persona reflect the new principle immediately — no app restart. The TASTE.md file is re-read every Ask via `PersonaStore.myCurrentBundle()`.

### Apply — automatic, not a mode

There is no "Apply" mode toggle anymore. Every Ask reply is automatically grounded in the active persona's taste:

- `.me` → user's own `taste-profile.json` (legacy) plus their TASTE.md if present
- `.team` pseudo-persona → personal ∪ team profile, plus the team brief from `TeamContextStore`
- `.teammate(id)` → that teammate's bundle only (their soul, their taste, their voice)

`TastePromptBuilder.buildTasteContextBlock(...)` formats principles as `[P1][design] statement` lines with a `[USED:...]` reporting tag at the end so we can show the user which principles Claude leaned on.

### Persona wheel

Hold `shift + cmd` anywhere → a radial picker ([PersonaWheelView](leanring-buddy/PersonaWheelView.swift)) springs around the cursor with one spoke per persona. Move toward a spoke and release to commit. The wheel is rendered inside the existing overlay window — same surface as the cursor — and disappears on release.

A persona switch wipes the rolling voice conversation history (`conversationHistory.removeAll()` in `setPersonaSelection`) so the new persona starts on a blank slate, like talking to a different person.

### Privacy posture

- Voice capture only happens while `ctrl + option` is held — the waveform on the cursor overlay is the recording indicator.
- Teach sessions only capture frames between Start and Stop; the panel shows an elapsed timer the entire time.
- Screenshots are sent to the Worker proxy in-memory and not retained on disk.
- Nothing is added to a persona's `TASTE.md` until the user taps **Remember** on the review card.

---

## Architecture

- **App type**: Menu bar-only (`LSUIElement=true`), no dock icon. Two real windows can open as auxiliary surfaces: the floating chat ([ChatWindowController](leanring-buddy/ChatWindowController.swift)) and the dashboard ([DashboardWindowController](leanring-buddy/DashboardWindowController.swift)).
- **Framework**: SwiftUI (macOS native) with AppKit bridging for the borderless menu bar `NSPanel` and the always-on-top transparent cursor overlay.
- **Pattern**: MVVM with `@StateObject` / `@Published`. `CompanionManager` is the central state machine.
- **AI chat**: Claude (Haiku 4.5 default for voice — TTFT-bound, Sonnet/Opus optional) via Cloudflare Worker proxy with SSE streaming.
- **Speech-to-text**: AssemblyAI streaming v3 over websocket, with OpenAI and Apple Speech as fallbacks. Provider chosen by `VoiceTranscriptionProvider` in Info.plist.
- **Text-to-speech**: ElevenLabs `eleven_flash_v2_5` via the Worker. Sentence-streamed playback so audio starts before generation finishes.
- **Screen capture**: ScreenCaptureKit, multi-monitor, JPEG.
- **Voice input**: Push-to-talk via `AVAudioEngine` + a system-wide listen-only `CGEvent` tap.
- **Element pointing**: Claude embeds `[POINT:x,y:label:screenN]` tags. The overlay parses them, maps coordinates to the correct monitor, and animates the cursor along a bezier arc.
- **Persona wheel hotkey**: separate listen-only `CGEvent` tap on `flagsChanged` for `shift + cmd` ([PersonaWheelHotkeyMonitor](leanring-buddy/PersonaWheelHotkeyMonitor.swift)). Independent of push-to-talk.
- **Concurrency**: `@MainActor` isolation, async/await throughout.
- **Theme**: light/dark/system via `ThemeManager.shared.mode`. Surfaces use the `ElevenLabsBrand.Colors` paper-and-ink palette which resolves dynamically per appearance.

### API proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Worker that holds the real keys as secrets — see [worker/src/index.ts](worker/src/index.ts).

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`. Worker var: `ELEVENLABS_VOICE_ID`. Base URL is hardcoded in [CompanionManager.swift](leanring-buddy/CompanionManager.swift) (`workerBaseURL`).

### Key architecture decisions

**Menu bar panel pattern**: `NSStatusItem` + custom borderless `NSPanel` (non-activating so it doesn't steal focus, click-outside-dismiss via global event monitor). `NSHostingView` bridges the SwiftUI [CompanionPanelView](leanring-buddy/CompanionPanelView.swift) inside.

**Cursor overlay**: full-screen transparent `NSPanel` per screen, joins all Spaces, never steals focus. Holds the blue cursor, the response-text bubble, the waveform, the persona wheel, and the applied-principles chip — all SwiftUI views inside one `BlueCursorView` ZStack.

**Persona-driven voice ID**: when a teammate persona is active, `effectiveTTSVoiceID = activeTeammateBundle.voiceId ?? selectedVoiceID`. Switching persona → next reply speaks in their voice without restarting playback machinery.

**Persona-driven system prompt**: `composeVoiceSystemPromptWithTaste()` branches on `personaSelection`. For `.teammate`, the base "you're sticky" identity paragraph is stripped (`basePromptWithoutIdentityParagraph`) so the model fully inhabits the teammate. For `.me` / `.team`, principles are formatted with `[Pn]` / `[Tn]` short labels and a trailing `[USED:...]` instruction.

**Shared URLSession for AssemblyAI**: a single long-lived `URLSession` is shared across all streaming sessions (owned by the provider, not the session). Per-session URLSessions corrupt the OS connection pool and cause "Socket is not connected" errors after rapid reconnects.

**Transient cursor mode**: when `isClickyCursorEnabled` is off, holding push-to-talk fades the overlay in for the interaction (recording → response → TTS → optional pointing) and fades it out after 1s of inactivity. The persona wheel hotkey also brings it back transiently.

**Voice and teach sessions are independent state machines**: `voiceState: CompanionVoiceState` (idle / listening / processing / responding) and `teachSessionState: TeachSessionState` (idle / recording / analyzing) live side by side on `CompanionManager`. Don't conflate them — the user can talk to Sticky while a teach session is recording (though the UX doesn't encourage it).

**Persona TASTE.md is the source of truth, not JSON**: `PersonaStore.myCurrentBundle()` re-reads `personas/<id>/TASTE.md` on every Ask so freshly-taught principles become visible without a restart. The legacy `taste-profile.json` is still written by teach mode for the Library window's read path; both writes happen in lockstep and the JSON store can eventually go away.

**Hot-swap personas**: `PersonaTasteFileStore` reads from `~/Library/Application Support/com.learning-buddy.clicky/personas/<id>/TASTE.md` first (overrides), then falls back to the bundled copy. Drop a TASTE.md into Application Support and the wheel picks it up.

---

## Data shapes

Core types live in [TasteTypes.swift](leanring-buddy/TasteTypes.swift). All `Codable`.

```swift
enum TasteScope: String, Codable { case personal, team }
enum TasteDomain: String, Codable { case design, writing, code, general }

struct TastePrinciple: Codable, Identifiable, Equatable {
    let id: String
    var domain: TasteDomain
    var statement: String
    var confidence: Double
    var evidence: [String]
    var tags: [String]
    var approved: Bool
    var authorId: String
    var createdAt: Date
    var updatedAt: Date
}

struct TasteProfile: Codable, Equatable {
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

`PersonaSelection` lives in [PersonaBundle.swift](leanring-buddy/PersonaBundle.swift):

```swift
enum PersonaSelection: Equatable, Hashable {
    case me                       // user's own configured Sticky
    case team                     // user + team taste, plus team brief
    case teammate(id: String)     // borrow another persona's bundle wholesale
}
```

A `PersonaBundle` is parsed from a markdown file by [PersonaTasteFileStore.swift](leanring-buddy/PersonaTasteFileStore.swift) — see that file's header comment for the TASTE.md format.

---

## On-disk layout

```
~/Library/Application Support/com.learning-buddy.clicky/
  taste-profile.json                  ← user's personal taste (legacy JSON, still written)
  team-profile.json                   ← optional shared team taste
  team-context.json                   ← team brief + attached files metadata
  team-files/<filename>               ← attached files raw bytes
  personas/<id>/TASTE.md              ← per-persona override (hot-swap)
  personas/<id>/<avatar>.png|jpg      ← optional avatar override
```

Bundled defaults ship inside the app at `leanring-buddy/personas/<id>/TASTE.md` (folder reference, picked up automatically — no `project.pbxproj` edits needed for new persona files).

---

## Key files

| File | Lines | Purpose |
|------|-------|---------|
| [leanring_buddyApp.swift](leanring-buddy/leanring_buddyApp.swift) | ~89 | App entry. `@NSApplicationDelegateAdaptor` → `CompanionAppDelegate` creates `MenuBarPanelManager`, starts `CompanionManager`, and registers the app as a login item. |
| [CompanionManager.swift](leanring-buddy/CompanionManager.swift) | ~2960 | Central state machine. Owns dictation, push-to-talk monitor, persona-wheel monitor, screen capture, ClaudeAPI, ElevenLabs TTS, overlay manager, voice + teach state, persona selection, taste scope, applied-principles transparency, and the system prompt composer. |
| [MenuBarPanelManager.swift](leanring-buddy/MenuBarPanelManager.swift) | ~780 | `NSStatusItem` + custom borderless `NSPanel` lifecycle. Re-images the menu bar icon when persona changes. Owns the Taste Library window. |
| [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) | ~1460 | SwiftUI menu bar panel content. Hero header with persona picker, push-to-talk instruction, teach session controls, mini activity feed, footer with model picker / theme toggle / sign-in chip / quit. |
| [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift) | ~1780 | One transparent always-on-top `NSPanel` per screen. Hosts `BlueCursorView` (cursor, waveform, response text, applied-principles chip, persona wheel). Handles cursor flight along bezier arcs to `[POINT:...]` targets. |
| [CompanionResponseOverlay.swift](leanring-buddy/CompanionResponseOverlay.swift) | ~217 | The response-text bubble + waveform rendered next to the cursor. |
| [CompanionScreenCaptureUtility.swift](leanring-buddy/CompanionScreenCaptureUtility.swift) | ~135 | Multi-monitor JPEG screenshot via ScreenCaptureKit. |
| [BuddyDictationManager.swift](leanring-buddy/BuddyDictationManager.swift) | ~1090 | Push-to-talk pipeline: mic capture, provider permissions, keyboard/button sessions, finalization. Also owns the long-form dictation used by teach sessions. |
| [BuddyTranscriptionProvider.swift](leanring-buddy/BuddyTranscriptionProvider.swift) | ~109 | Provider protocol + factory. Resolves AssemblyAI / OpenAI / Apple Speech from Info.plist. |
| [AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift) | ~563 | Streaming v3 websocket provider. Fetches a temp token from `/transcribe-token`, streams PCM16. |
| [OpenAIAudioTranscriptionProvider.swift](leanring-buddy/OpenAIAudioTranscriptionProvider.swift) | ~317 | Fallback upload-based provider. |
| [AppleSpeechTranscriptionProvider.swift](leanring-buddy/AppleSpeechTranscriptionProvider.swift) | ~147 | Local fallback using Apple Speech framework. |
| [BuddyAudioConversionSupport.swift](leanring-buddy/BuddyAudioConversionSupport.swift) | ~108 | PCM16 mono conversion + WAV payload helpers. |
| [GlobalPushToTalkShortcutMonitor.swift](leanring-buddy/GlobalPushToTalkShortcutMonitor.swift) | ~132 | Listen-only `CGEvent` tap for `ctrl + option`. |
| [PersonaWheelHotkeyMonitor.swift](leanring-buddy/PersonaWheelHotkeyMonitor.swift) | ~148 | Listen-only `CGEvent` tap for `shift + cmd`. Drives the radial wheel. |
| [PersonaWheelView.swift](leanring-buddy/PersonaWheelView.swift) | ~209 | Radial picker rendered inside the overlay. Spokes laid out clockwise from 12 o'clock. |
| [PersonaStore.swift](leanring-buddy/PersonaStore.swift) | ~495 | Loads persona bundles from TASTE.md (hot-swap > bundled). Holds the synthetic `mePseudoPersona` / `teamPseudoPersona` for the wheel. Sample bundles are last-resort fallbacks if every TASTE.md fails to load. |
| [PersonaTasteFileStore.swift](leanring-buddy/PersonaTasteFileStore.swift) | ~706 | TASTE.md parser + writer. Read-paths fall back from Application Support to bundled. Writes always go to Application Support so reinstalls don't clobber teaching. |
| [PersonaBundle.swift](leanring-buddy/PersonaBundle.swift) | ~171 | `PersonaSelection`, `PersonaAvatar`, `PersonaBundle` types. Hex-string → `Color` parser. |
| [PersonaAvatarView.swift](leanring-buddy/PersonaAvatarView.swift) | ~187 | Renders initials / SF Symbol / image-file avatars at any size. |
| [TasteTypes.swift](leanring-buddy/TasteTypes.swift) | ~87 | Core data shapes: `TastePrinciple`, `TasteProfile`, `TeamTasteProfile`, `AmbiguousMoment`, `TeachSessionResult`, `TeachSessionState`, `PendingTeachSessionReview`. |
| [SessionAnalyzer.swift](leanring-buddy/SessionAnalyzer.swift) | ~185 | Picks ≤10 evenly-spaced frames, calls `ClaudeAPI.analyzeImageStreaming` with the teach prompt, walks the response for the first balanced JSON object, decodes into `TeachSessionResult`. |
| [TasteExtractionPrompt.swift](leanring-buddy/TasteExtractionPrompt.swift) | ~103 | System + user prompt for teach analysis. Pinned JSON schema lives here. |
| [TastePromptBuilder.swift](leanring-buddy/TastePromptBuilder.swift) | ~197 | Builds the taste-context block with `[P1]` / `[T1]` short labels + the trailing `[USED:...]` reporting instruction. Parses `[USED:...]` back out of replies. |
| [TasteProfileStore.swift](leanring-buddy/TasteProfileStore.swift) | ~203 | Codable load / save / append / delete on `taste-profile.json`. |
| [TeamTasteProfileStore.swift](leanring-buddy/TeamTasteProfileStore.swift) | ~70 | Read `team-profile.json` (best-effort; nil on missing/malformed). |
| [TeamContextStore.swift](leanring-buddy/TeamContextStore.swift) | ~296 | Persists the team brief + attached files. Used by team-mode prompts. |
| [TeamContextPromptBuilder.swift](leanring-buddy/TeamContextPromptBuilder.swift) | ~86 | Formats the team brief + file catalog into a prompt block. Inlines small text bodies, names-only for big/binary files. |
| [TasteProfileExporter.swift](leanring-buddy/TasteProfileExporter.swift) | ~225 | Export/import for sharing taste profiles between teammates. |
| [DashboardTasteMarkdownExporter.swift](leanring-buddy/DashboardTasteMarkdownExporter.swift) | ~141 | Export a persona's taste to markdown for the dashboard. |
| [ClaudeAPI.swift](leanring-buddy/ClaudeAPI.swift) | ~309 | Vision + SSE-streaming Claude client. TLS warmup. JPEG/PNG MIME detection. Multi-image, conversation-history, custom system-prompt support. |
| [OpenAIAPI.swift](leanring-buddy/OpenAIAPI.swift) | ~142 | OpenAI GPT vision client (alternative provider). |
| [ElevenLabsTTSClient.swift](leanring-buddy/ElevenLabsTTSClient.swift) | ~371 | TTS playback via `AVAudioPlayer`. Sentence-chained queue. Per-voice metadata. Publishes `currentPowerLevel` for the edge-glow aurora. |
| [VoicePreviewCache.swift](leanring-buddy/VoicePreviewCache.swift) | ~128 | On-disk cache of "Hey, it's Sticky!" preview clips for each voice. Background prefetched on first picker open. |
| [ElementLocationDetector.swift](leanring-buddy/ElementLocationDetector.swift) | ~335 | Detects UI element locations (legacy — most pointing now goes through Claude's `[POINT:...]` tag). |
| [DesignSystem.swift](leanring-buddy/DesignSystem.swift) | ~1470 | Two coexisting palettes: `DS.*` (older blue-on-dark tokens still used by parts of the overlay) and `ElevenLabsBrand.*` (paper-and-ink editorial system used by panel + chat + dashboard). Both are dynamic for light/dark via `ThemeManager`. |
| [MacDropdownComponents.swift](leanring-buddy/MacDropdownComponents.swift) | ~265 | Reusable Apple-native dropdown primitives styled like macOS Control Center. |
| [ThemeManager.swift](leanring-buddy/ThemeManager.swift) | ~181 | Single source of truth for light/dark/system theme. Persists to UserDefaults, applies to `NSApp.appearance`. |
| [ChatWindowController.swift](leanring-buddy/ChatWindowController.swift) | ~174 | Floating chat `NSWindow` (real, resizable). Singleton; one persistent `ChatViewModel` for the lifetime of the app. |
| [ChatView.swift](leanring-buddy/ChatView.swift) | ~529 | ChatGPT-style centered chat surface. Per-message persona avatar + screenshot attachment. |
| [ChatViewModel.swift](leanring-buddy/ChatViewModel.swift) | ~506 | Chat send pipeline. Independent ClaudeAPI instance from voice. Captures a fresh screenshot on every send. Reads active persona from injected `CompanionManager`. |
| [ChatMarkdownRenderer.swift](leanring-buddy/ChatMarkdownRenderer.swift) | ~481 | Custom markdown-on-screen renderer for chat replies. |
| [ChatHistorySidebar.swift](leanring-buddy/ChatHistorySidebar.swift) | ~414 | Left rail inside the dashboard's Chat tab. Lists archived sessions; tap to load into the live transcript. |
| [DashboardWindowController.swift](leanring-buddy/DashboardWindowController.swift) | ~170 | Dashboard `NSWindow` lifecycle. Hide-on-close so re-opens are instant. |
| [DashboardView.swift](leanring-buddy/DashboardView.swift) | ~141 | Dashboard root. Two-column layout — sidebar + section content. Mock auth gate. |
| [DashboardSidebar.swift](leanring-buddy/DashboardSidebar.swift) | ~164 | Sidebar nav. Sections: Chat, Memory, Tastes, Team, Profile, Settings. |
| [DashboardNavigationState.swift](leanring-buddy/DashboardNavigationState.swift) | ~72 | `DashboardSection` enum + shared `selectedSection` / `focusedPersonaId`. |
| [DashboardLiveChatView.swift](leanring-buddy/DashboardLiveChatView.swift) | ~37 | Embeds the same `ChatView` + `ChatViewModel` the floating chat uses, side by side with `ChatHistorySidebar`. One transcript, two surfaces. |
| [DashboardMemoryView.swift](leanring-buddy/DashboardMemoryView.swift) | ~52 | Embeds the Taste Library inline in the dashboard. |
| [DashboardTastesView.swift](leanring-buddy/DashboardTastesView.swift) | ~160 | Persona list (renamed "Tastes" in the UI; underlying type is still `PersonaBundle`). |
| [DashboardPersonaDetailView.swift](leanring-buddy/DashboardPersonaDetailView.swift) | ~314 | Read-only persona detail page. |
| [DashboardTeamView.swift](leanring-buddy/DashboardTeamView.swift) | ~228 | Team brief + attached files editor. Writes through `TeamContextStore`. |
| [DashboardProfileView.swift](leanring-buddy/DashboardProfileView.swift) | ~339 | Mock-auth profile page. |
| [DashboardRecordingHistoryStore.swift](leanring-buddy/DashboardRecordingHistoryStore.swift) | ~117 | Codable on-disk archive of "you taught Sticky X" rows. Powers the mini panel's recent-activity feed. |
| [DashboardChatHistoryStore.swift](leanring-buddy/DashboardChatHistoryStore.swift) | ~175 | Codable on-disk archive of chat sessions. |
| [DashboardSettingsView.swift](leanring-buddy/DashboardSettingsView.swift) | ~260 | Theme toggle, model picker, voice picker, transcription provider info, etc. |
| [DashboardMockAuthState.swift](leanring-buddy/DashboardMockAuthState.swift) | ~104 | Mock email-only auth. Any non-empty email signs in. |
| [DashboardSectionHeader.swift](leanring-buddy/DashboardSectionHeader.swift) | ~87 | Shared section header with eyebrow + title + subtitle. |
| [DashboardModelPickerKind.swift](leanring-buddy/DashboardModelPickerKind.swift) | ~82 | Voice vs chat model picker enum. |
| [TasteLibraryView.swift](leanring-buddy/TasteLibraryView.swift) | ~654 | Browse / delete saved principles. Used in the Memory tab and the standalone library window. |
| [TasteLibraryWindowController.swift](leanring-buddy/TasteLibraryWindowController.swift) | ~148 | Standalone library window (opened from the menu bar panel). |
| [TeachSessionResultCard.swift](leanring-buddy/TeachSessionResultCard.swift) | ~347 | The Save / Discard card shown in the panel after a teach session analyzes. Checkboxes for confident principles + ambiguous-moment hint. |
| [ReviewCardStack.swift](leanring-buddy/ReviewCardStack.swift) | ~509 | MCQ card stack for ambiguous moments. Approve / type-your-own / skip / undo. |
| [AppliedPrinciplesChip.swift](leanring-buddy/AppliedPrinciplesChip.swift) | ~150 | Cursor-overlay chip listing principles Claude leaned on (parsed from `[USED:...]`). |
| [MiniPanelActivityFeed.swift](leanring-buddy/MiniPanelActivityFeed.swift) | ~340 | Recent-activity rows in the menu bar panel. Merges teach moments + chat sessions. |
| [WindowPositionManager.swift](leanring-buddy/WindowPositionManager.swift) | ~262 | Permission helpers (Accessibility, Screen Recording). |
| [AppBundleConfiguration.swift](leanring-buddy/AppBundleConfiguration.swift) | ~62 | Reads runtime config from Info.plist. |
| [worker/src/index.ts](worker/src/index.ts) | ~142 | Cloudflare Worker proxy. Three routes: `/chat`, `/tts`, `/transcribe-token`. |
| [leanring-buddy/personas/](leanring-buddy/personas/) | — | Bundled persona TASTE.md files (currently `reuban`, `leonard`, `magdalena`). Folder reference — drop a new `<id>/TASTE.md` and it ships in the next build. |

---

## Build & run

```bash
open leanring-buddy.xcodeproj
```

Select the `leanring-buddy` scheme, set your signing team, ⌘R.

> **Do NOT run `xcodebuild` from the terminal.** It invalidates TCC permissions (Screen Recording, Accessibility, Microphone) and the app will need to re-request them.

Known non-blocking warnings: Swift 6 concurrency warnings, deprecated `onChange` warnings in [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift). **Do not attempt to fix these.**

### Cloudflare Worker

```bash
cd worker
npm install

npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

npx wrangler deploy
```

Local dev: create `worker/.dev.vars` with the keys, then `npx wrangler dev`.

---

## Code style & conventions

### Naming

Clarity over concision.

- A developer with zero context should immediately understand a name.
- No single-letter variables. Use `originalQuestionLastAnsweredDate`, not `originalAnswered`.
- Keep names stable across call sites — `currentCardData` stays `currentCardData` when passed, not `card` or `cardData`.

### Code clarity

- Clear is better than clever. More lines is fine when it improves readability.
- When a name alone can't fully explain something, add a comment about *why*, not what.
- Default to writing no comments. Only add one when the WHY is non-obvious — a hidden constraint, a subtle invariant, a workaround.
- Don't reference the current task / fix / caller in a comment ("added for the X flow", "used by Y") — that belongs in the PR description.

### Swift / SwiftUI

- SwiftUI for all UI unless a feature is AppKit-only (`NSPanel` for floating windows, `NSStatusItem` for the menu bar).
- All UI state updates on `@MainActor`.
- async/await everywhere; no completion handlers in new code.
- `NSPanel` / `NSWindow` bridged into SwiftUI via `NSHostingView`.
- All buttons must show a pointer cursor on hover (`.pointerCursor()`).
- For any interactive element, explicitly think through hover behavior — cursor, visual feedback, whether hover should communicate clickability.

### Design system

- Use `ElevenLabsBrand.*` tokens for new menu bar / panel / chat / dashboard surfaces — `Colors.paper`, `Colors.card`, `Colors.ink`, `Colors.hairline`, `Spacing.{xs..xxl}`, `Radius.card`, `Typography.*`. They're appearance-aware (light/dark).
- Use `DS.*` tokens (`DS.Colors.overlayCursorBlue`, `DS.CornerRadius.*`, `DS.Spacing.*`, `DS.Animation.*`) for the overlay / cursor / waveform / blue-on-dark surfaces.
- No hardcoded colors or radii in new code.

### Don't

- Don't add features, refactor, or "improve" beyond what was asked.
- Don't add docstrings, comments, or type annotations to code you didn't change.
- Don't try to fix the known non-blocking warnings.
- Don't rename the project directory or scheme — the "leanring" typo is legacy and intentional.
- Don't run `xcodebuild` from the terminal.
- Don't add backwards-compatibility shims, feature flags, or migration code unless explicitly asked.

---

## Common gotchas

- **Persona switching wipes voice conversation history.** Intentional — see `setPersonaSelection`. Switching mid-conversation feels like talking to a different person.
- **TASTE.md ids are derived from a slug of the statement.** Editing a statement changes its id. That's intentional; the wording moved enough to be a new principle.
- **Trailing-tag order is `[POINT:...]` → `[BUBBLE:...]` → `[USED:...]` → `[ACTION:...]`.** All four parsers anchor to end-of-string, so they're stripped in reverse order (ACTION first, then USED, then BUBBLE, then POINT) so each tag is sitting at end-of-string when its regex runs. The prompt instructs Claude to emit them in that left-to-right order. `[BUBBLE:caption]` only appears alongside a `[POINT:x,y:label]` — it sets `detectedElementBubbleText` so the cursor speech bubble carries Claude's own callout instead of a generic "right here!". `[ACTION:start_notes]` / `[ACTION:stop_notes]` is fired AFTER the spoken acknowledgement drains, because `startTeachSession()` calls `stopPlayback()` and would otherwise cut Claude off mid-word.
- **Multi-step pointing tags inline.** `[USED:...]` and `[ACTION:...]` are reply-level — they only appear at the very end of the reply and are terminal in the streaming parser (everything after them is dropped). `[POINT:...][BUBBLE:...]` pairs can appear *inline* — the streaming parser in `StreamingResponseState` extracts each pair, attaches the resulting `PointingWaypoint` to the speech segment that preceded it, and the cursor flies when that segment begins playing (via `ElevenLabsTTSClient.enqueueAudioData(_:forEpoch:onSegmentStart:)`). The trailing-tag flight in the response handler is skipped when `streamingResponseState.didConsumeAnyInlineWaypoint` is true, so inline waypoints don't double-fly. `Self.stripAllInlinePointBubblePairs(from:)` cleans any inline tag characters out of the spoken text before `dispatchAnyTrailingText` runs — without it, partial tag strings could leak into ElevenLabs as audio.
- **Claude (Haiku 4.5) is the default voice model.** Sonnet/Opus are pickable from the panel. Haiku's TTFT is roughly 2-3× faster, which dominates the perceived latency budget for spoken replies. Don't change the default unless asked.
- **Screenshot capture starts on key-down**, not key-up. The release handler awaits the preflight task. If you add a new code path that wants a screenshot during the response pipeline, await `preflightScreenCaptureTask` rather than calling `captureAllScreensAsJPEG` again.
- **`personaSelection` and `tasteScope` are kept in sync.** `setPersonaSelection(.me)` forces scope to `.personal`; `.team` forces scope to `.team`; `.teammate` leaves it alone. Don't mutate `tasteScope` directly — go through `setTasteScope` so the UserDefaults key stays right.
- **Onboarding is permanently disabled.** `hasCompletedOnboarding` always returns `true`. Do not re-introduce the onboarding gate without an explicit ask.

---

## Git workflow

- Branches: `feature/description` or `fix/description`.
- Commit messages: imperative mood, concise, the "why" not the "what".
- Don't force-push to `main`.
- The Sparkle updater is currently disabled (see `startSparkleUpdater` is commented out in [leanring_buddyApp.swift](leanring-buddy/leanring_buddyApp.swift)). Don't re-enable without asking.

---

## Self-update

When you make changes that affect the information in this file, update it.

1. **New files**: add to the Key files table with purpose + approximate line count.
2. **Deleted files**: remove the row.
3. **Architecture changes**: update the relevant section.
4. **New conventions**: add to the appropriate conventions section.
5. **Significant line-count drift** (>50 lines): update the row.

Don't update for minor edits, bug fixes, or changes that don't affect documented architecture or conventions.
