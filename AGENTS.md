# Sticky — Agent Instructions

<!-- Single source of truth for AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## What Sticky is

Sticky is a macOS menu-bar AI companion that wears your team's taste. It lives in the status bar (no dock icon, no main window) and answers in the voice and taste of whichever **persona** the user is currently wearing.

> **Production transition:** This file describes the current local MVP unless a section says otherwise. [PRODUCTION_PLAN.md](PRODUCTION_PLAN.md) is authoritative for planned accounts, workspaces, membership-owned personas, authorization, cloud context, and the removal of Soul/TASTE.md runtime models. Do not treat the current `.team`, `TasteScope`, local-store, or TASTE.md behavior as the target production contract.

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
- **Production backend bootstrap**: Convex owns the initial `profiles`, `workspaces`, `workspaceMembers`, and membership-owned `personas` model. Authorization helpers derive the canonical profile from verified identity and enforce active membership, workspace roles, persona ownership, and workspace-scoped persona use. Application data subscriptions remain deferred.
- **Personal workspace provisioning**: after Convex authenticates and pending Clerk callbacks drain, `AuthenticationManager` calls the idempotent `accounts:provisionCurrent` mutation. Convex derives the profile exclusively from `identity.tokenIdentifier` and transactionally creates or validates one personal workspace, owner membership, and fresh persona. Provisioning has its own generation-bound state and bounded retry; it does not unlock production features.
- **Onboarding Worker request tickets**: PR 4A's merged Convex control plane exposes one authenticated owner-only action that returns a 256-bit opaque bearer once and persists only its SHA-256 digest. Tickets are short-lived, single-use, exact-body-bound, limited to `onboarding_chat`, `onboarding_tts`, and `onboarding_transcribe`, and revalidate the full account/workspace/membership/persona lifecycle plus the denormalized audit relationship at atomic internal consumption. PR 4B adds exactly two Convex HTTP endpoints for consume and completion using timestamped per-request HMAC-SHA256 over the canonical method, path, timestamp, cryptographic request ID, and raw-body digest. Convex accepts current and optional previous key pairs for rotation and never receives ticket plaintext. Completion delivery retries network errors, `408`, `425`, `429`, and `5xx` up to three attempts with the same idempotent body and fresh service-request signatures. PR 4C's actor-backed native client deterministically serializes each strict route DTO once, hashes and issues a fresh ticket for those exact bytes, then streams the unchanged request through the onboarding Worker. Every operation is bound to an immutable authenticated account/workspace/persona context and revalidates it before issuance, after issuance, after response, and during streaming. No onboarding UI is added, production readiness stays locked, and native transport remains unavailable until the development Worker is deployed and its HTTPS origin is supplied through ignored runtime configuration.
- **Structured persona foundation**: PR 5A stores one owner-private onboarding session per persona, bounded immutable turns, append-only versioned records with exact owner-answer provenance, immutable session-operation receipts, and a separate explicitly approved teammate-readable boundary projection. Canonical server-generated fingerprints make retries valid only for the exact normalized request. Active `startOrResume` no-ops store exact nonterminal receipts to preserve mutation-ID uniqueness; new unique no-ops are rejected at the nonterminal cap, which remains one row below the hard limit so terminal completion always retains a reserved slot from active or paused state. One shared bounded graph validator checks every setup, child relationship, version/source link, turn sequence, and lifecycle combination before reads, writes, authorization, or ticket use. Work context plus one communication preference atomically activates the persona and moves setup to `interview`; skipping pauses that same resumable session, while `complete` is permanently terminal for onboarding tickets. Chat ticket consumption base64-encodes byte-length-labelled untrusted values and deterministically fits only that persona's current records and latest turns within both 8,192 characters and UTF-8 bytes; TTS and transcription policy remain unchanged.
- **Production authentication**: Clerk provides native Google and email-link sessions in Keychain. `AuthenticationManager` bridges Clerk into `ConvexClientWithAuth`; protected UI follows Convex auth state rather than Clerk user presence. Native callbacks use exact `com.reuban.sticky://callback` matching until associated domains are available. The development issuer is exactly `https://ruling-katydid-23.clerk.accounts.dev`, and Clerk's Convex integration must issue `aud: convex`.
- **Production-data boundary**: Authentication alone does not start the product. `productionDataReadiness` remains `.awaitingWorkspaceProvisioning` in this PR, so `CompanionManager`, Ask, Teach, personas, floating chat, Taste Library, and Dashboard Chat/Memory/Tastes/Team stay unavailable. Readiness is valid only as `.ready(userID:authGeneration:workspaceID:)` matching the current identity, generation, and workspace. PR 3 may call `markCurrentAuthenticatedWorkspaceReady(workspaceID:)` only after provisioning production-scoped storage. Auth or readiness loss increments lifecycle generations, cancels in-flight work, clears in-memory captures/messages, stops playback/hotkeys/overlays, and hides legacy windows.
- **Auth operation generations**: Account generations protect identity-bound retry/login work; callback epochs independently preserve a valid callback across cached-user discovery and account transitions. Explicit sign-out invalidates callbacks. Sign-out completion is publisher-driven and has a distinct bounded retry failure state.
- **Runtime auth configuration**: ClerkKit 1.3.2 ignores a second `Clerk.configure` call. Normal Retry uses `refreshEnvironment()` and `refreshClient()`. If public runtime values changed on disk, the app must show restart-required and must not replace the Convex client in-process.
- **Authenticated interim surface**: Authenticated users see verified Clerk identity, personal-workspace provisioning progress or status, dedicated provisioning retry, and sign-out. Existing Profile and Settings views remain hidden because they mix in legacy TASTE export or controls for disabled local companion features.

### API proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Worker that holds the real keys as secrets — see [worker/src/index.ts](worker/src/index.ts).

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`. Worker var: `ELEVENLABS_VOICE_ID`. Base URL is hardcoded in [CompanionManager.swift](leanring-buddy/CompanionManager.swift) (`workerBaseURL`).

The default `clicky-proxy` deployment remains legacy-only. The separate
`sticky-onboarding-dev` environment closes those routes and exposes only
`POST /v1/onboarding/chat`, `POST /v1/onboarding/tts`, and
`POST /v1/onboarding/transcribe-token`. These routes require
`Authorization: StickyTicket <opaque>`, consume the exact body binding before
provider access, use only server-derived policy, stream provider bodies, and
report sanitized completion through `ctx.waitUntil`. The native base URL is
read from `OnboardingWorkerBaseURL`; it is intentionally absent until the
development environment is deployed.

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
  profiles/<clerk-user-id>/profile-picture.* ← temporary Clerk-user-scoped local profile image
```

Persona bundles are loaded only from TASTE.md files in Application Support or the app bundle. There are no baked-in Swift persona fallbacks; if no files are available, the teammate list is empty.

Temporary local display-name, role, and profile-picture overrides are scoped by
verified Clerk user ID. Legacy persona, taste, team, chat-history, and
recording-history stores are unscoped local MVP data and must never render for
authenticated accounts. They remain on disk but inaccessible until their cloud
replacement PRs remove them.

---

## Key files

| File | Lines | Purpose |
|------|-------|---------|
| [PRODUCTION_PLAN.md](PRODUCTION_PLAN.md) | ~755 | Confirmed production product model, Convex data relationships, authorization contract, context rules, test requirements, and dependency-ordered agent/PR roadmap. |
| [CONVEX.md](CONVEX.md) | ~290 | Convex deployment safety, authentication, persona onboarding, ticket context, local setup, generated-file, and secret-handling instructions. |
| [convex/schema.ts](convex/schema.ts) | ~140 | Production account, structured persona, onboarding receipt, boundary projection, and Worker ticket tables with bounded indexes. |
| [convex/validators.ts](convex/validators.ts) | ~470 | Shared account, structured persona, onboarding receipt, boundary, Worker ticket, policy, and completion validators. |
| [convex/accounts.ts](convex/accounts.ts) | ~390 | Authenticated, fail-closed personal-account provisioning, safe default-name repair, and current-account graph query. |
| [convex/accounts.test.ts](convex/accounts.test.ts) | ~580 | Adversarial provisioning tests for idempotency, concurrency, partial repair, claim refresh, lifecycle integrity, orphan rollback, and identity isolation. |
| [convex/requestTickets.ts](convex/requestTickets.ts) | ~80 | Public authenticated onboarding-ticket action that generates and hashes a one-time 256-bit bearer. |
| [convex/workerRequestPolicy.ts](convex/workerRequestPolicy.ts) | ~160 | Versioned onboarding-only scope, payload, quota, expiry, retention, and trusted provider policy. |
| [convex/workerRequestTicketMutations.ts](convex/workerRequestTicketMutations.ts) | ~505 | Internal issuance, atomic consume, lifecycle and audit-integrity revalidation, quota enforcement, and idempotent sanitized completion. |
| [convex/workerRequestTicketCleanup.ts](convex/workerRequestTicketCleanup.ts) | ~115 | Bounded indexed ticket and audit cleanup mutations with fixed-cutoff scheduled continuation. |
| [convex/crons.ts](convex/crons.ts) | ~30 | Hourly triggers for issued-ticket, consumed-tombstone, and audit cleanup. |
| [convex/requestTickets.test.ts](convex/requestTickets.test.ts) | ~1310 | Adversarial request-ticket authorization, strict setup graphs, injection-safe bounded persona context, quota, replay, concurrency, audit integrity, TOCTOU, privacy, rollback, and completion tests. |
| [convex/workerRequestTicketCleanup.test.ts](convex/workerRequestTicketCleanup.test.ts) | ~260 | Retention-boundary, independent audit retention, bounded deletion, and continuation tests. |
| [convex/http.ts](convex/http.ts) | ~180 | Exact HMAC-authenticated Worker consume and completion HTTP routes with bounded strict DTO parsing and generic failures. |
| [convex/workerServiceBridge.ts](convex/workerServiceBridge.ts) | ~340 | Pure canonicalization, HMAC rotation verification, digesting, and strict Worker service payload validation. |
| [convex/workerServiceBridge.test.ts](convex/workerServiceBridge.test.ts) | ~315 | Shared-vector compatibility, canonicalization, current/previous key rotation, timestamp, tamper, malformed DTO, route closure, and plaintext-ticket rejection tests. |
| [convex/authorization.ts](convex/authorization.ts) | ~270 | Deny-by-default identity, membership, role, validated persona usability, and readable boundary projection authorization helpers. |
| [convex/personaFoundation.ts](convex/personaFoundation.ts) | ~810 | Canonical request fingerprints, receipt limits, shared child/setup graph validation, immutable version/record writes, minimum preservation, and publication invalidation. |
| [convex/personaOnboarding.ts](convex/personaOnboarding.ts) | ~895 | Owner-only setup/session/turn APIs, terminal-capacity operation receipts, exact interpretation replay, pause/resume, pagination, and completion. |
| [convex/personaRecords.ts](convex/personaRecords.ts) | ~100 | Owner-only manual structured-record changes and immutable version pagination. |
| [convex/personaBoundarySummaries.ts](convex/personaBoundarySummaries.ts) | ~380 | Fingerprinted owner-controlled boundary publication lifecycle, normalized direct-ID denial, and minimal teammate projection. |
| [convex/personaOnboardingContext.ts](convex/personaOnboardingContext.ts) | ~150 | Deterministic byte-aware 8 KiB onboarding context with base64-encoded untrusted records and turns. |
| [convex/personaOnboarding.test.ts](convex/personaOnboarding.test.ts) | ~1520 | Persona readiness, private interpretation pagination, exact no-op/cross-operation replay, receipt exhaustion/reservation, provenance corruption, existence-oracle, concurrency, rollback, lifecycle, privacy, publication, record/turn caps, and boundary replace/unpublish tests. |
| [convex/auth.config.ts](convex/auth.config.ts) | ~15 | Clerk JWT provider configuration using the deployment's issuer domain and `convex` audience. |
| [convex/identity.ts](convex/identity.ts) | ~30 | Minimal protected query returning verified Clerk identity claims. |
| [convex/identity.test.ts](convex/identity.test.ts) | ~55 | Convex-test coverage for authenticated identity claims and unauthenticated denial. |
| [convex/health.ts](convex/health.ts) | ~20 | Minimal public backend health query. |
| [convex/authorization.test.ts](convex/authorization.test.ts) | ~450 | Edge-runtime Convex test harness covering health, authorization errors, lifecycle denial, relationship integrity, and cross-workspace isolation. |
| [convex/schema.test.ts](convex/schema.test.ts) | ~65 | Runtime and inferred-type tests for personal and team workspace schema requirements. |
| [vitest.config.ts](vitest.config.ts) | ~10 | Vitest configuration for Convex tests in the edge runtime. |
| [leanring_buddyApp.swift](leanring-buddy/leanring_buddyApp.swift) | ~140 | App entry. `@NSApplicationDelegateAdaptor` → `CompanionAppDelegate` creates `MenuBarPanelManager`, gates the `CompanionManager` lifecycle on Convex auth, handles callbacks, and registers the app as a login item. |
| [CompanionManager.swift](leanring-buddy/CompanionManager.swift) | ~3590 | Central state machine. Owns generation-guarded dictation, push-to-talk, Teach, capture, AI/TTS, overlays, and persona state; it cannot start before production data readiness. |
| [MenuBarPanelManager.swift](leanring-buddy/MenuBarPanelManager.swift) | ~780 | `NSStatusItem` + custom borderless `NSPanel` lifecycle. Re-images the menu bar icon when persona changes. Owns the Taste Library window. |
| [CompanionPanelView.swift](leanring-buddy/CompanionPanelView.swift) | ~1680 | SwiftUI menu bar panel content. Shows authentication and personal-workspace provisioning state; legacy persona, Ask, Teach, activity, and settings controls require production data readiness. |
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
| [PersonaStore.swift](leanring-buddy/PersonaStore.swift) | ~100 | Loads persona bundles exclusively from TASTE.md and holds the synthetic `mePseudoPersona` / `teamPseudoPersona` for the wheel. |
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
| [DashboardView.swift](leanring-buddy/DashboardView.swift) | ~220 | Dashboard root. Keeps legacy sections locked behind production readiness and shows authenticated workspace provisioning status. |
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
| [AuthenticationManager.swift](leanring-buddy/AuthenticationManager.swift) | ~1045 | Configures Clerk and authenticated Convex, independently scopes callback/account/provisioning operations, publishes identity/workspace-bound readiness, owns publisher-driven sign-out and bounded retries, and creates generation-invalidated onboarding Worker clients only for the matching provisioned account context. |
| [PersonalAccountBootstrapTypes.swift](leanring-buddy/PersonalAccountBootstrapTypes.swift) | ~40 | Decodable personal-workspace, membership, persona, and setup-state snapshot returned by Convex provisioning. |
| [OnboardingWorkerClient.swift](leanring-buddy/OnboardingWorkerClient.swift) | ~1630 | Actor-backed exact-byte ticket issuer and delegate-streamed native client with synchronized bounded backpressure, lifetime-owned cancellation, proactive generation and buffered-event invalidation, ticket freshness, and strict onboarding chat, TTS, and transcription contracts. |
| [leanring-buddyTests/OnboardingWorkerClientTests.swift](leanring-buddyTests/OnboardingWorkerClientTests.swift) | ~1340 | Native contract tests for Convex wire encoding, deterministic body binding, fresh tickets, production chunking, response limits, post-await and buffered-event invalidation, dropped-stream cleanup, threshold races, cancellation, ticket freshness, origin validation, and SSE streaming. |
| [scripts/configure-auth-runtime.py](scripts/configure-auth-runtime.py) | ~150 | Safely copies public Clerk, Convex, and optional onboarding Worker runtime values from ignored env files into Application Support without displaying them. |
| [scripts/test_configure_auth_runtime.py](scripts/test_configure_auth_runtime.py) | ~55 | Unit tests for accepted and rejected onboarding Worker HTTPS origin ports. |
| [worker/src/index.ts](worker/src/index.ts) | ~165 | Cloudflare Worker entrypoint that keeps the default legacy proxy routes separate from the closed onboarding development route set. |
| [worker/src/onboarding.ts](worker/src/onboarding.ts) | ~770 | Strict ticket-authorized onboarding handlers with trusted policy, streaming, and bounded idempotent completion retry. |
| [worker/src/service-auth.ts](worker/src/service-auth.ts) | ~120 | Per-request Worker-to-Convex HMAC signing and canonical request helpers. |
| [worker/test/onboarding.test.ts](worker/test/onboarding.test.ts) | ~575 | Workers-runtime tests for auth, exact DTOs, replay denial, trusted policy, streaming, completion retry, cancellation, transcription windows, and legacy isolation. |
| [worker/test/service-auth.test.ts](worker/test/service-auth.test.ts) | ~55 | Worker-side deterministic shared-vector digest, canonicalization, and HMAC signing compatibility test. |
| [test-fixtures/workerServiceHmacVector.ts](test-fixtures/workerServiceHmacVector.ts) | ~15 | Non-secret canonical HMAC request vector shared by Worker signing and Convex verification tests. |
| [leanring-buddy/personas/](leanring-buddy/personas/) | — | Optional bundled persona TASTE.md files. Folder reference — drop a new `<id>/TASTE.md` and it ships in the next build. |

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

- **Protected release baseline:** `main` must remain pinned to the verified May 8 baseline (`7792eae`) until Reuban explicitly approves the complete rebuild after end-to-end validation. Do not merge, push, or target incremental work to `main`.
- **Production integration branch:** `feature/production-rebuild` is the base and merge target for all production-rebuild work. Create child branches from it and open incremental PRs back into it.
- **Final release:** Draft PR #26 is the single eventual `feature/production-rebuild` → `main` update. Never mark it ready or merge it without explicit user approval.
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

<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

Before running any Convex command, inspect `CONVEX_DEPLOYMENT` in `.env.local`
and confirm its team, project, and deployment are the intended target. Plain
`convex dev` and the root Convex scripts use that configured deployment and may
mutate a cloud backend. For isolated local validation, explicitly run
`CONVEX_AGENT_MODE=anonymous npx convex dev --once`. Never run `convex deploy`
or `npm run convex:deploy` without explicit user authorization for that
production deployment operation.

<!-- convex-ai-end -->
