# Sticky

An AI companion that learns your taste — and your team's — and uses it to critique your work. Lives next to your cursor in the macOS menu bar. Built on top of [Clicky](#about-clicky).

![demo](clicky-demo.gif)

## What it does

Sticky has two halves:

- **Teach** — hold **Control + Option**, talk through a creative decision out loud while looking at your screen ("I made the logo bigger because brand presence matters"), and Sticky distills your reasoning into a reusable taste principle. You approve it with one tap before anything is saved.
- **Apply** — ask Sticky anything ("does this match my taste?", "what would the team think?"), and it answers grounded in the principles you've approved. Replies stream as text, speak via ElevenLabs TTS, and the blue cursor can fly to specific UI elements Sticky points out.

You can also wear a **persona** — borrow a teammate's voice, face, and taste profile, so Sticky critiques as them. Three sample teammates ship in the app.

## Features

- **Teach sessions** — start/stop from the menu bar panel. Sticky listens to your reasoning while capturing screenshots, then offers a stack of candidate principles to keep or skip.
- **Taste library** — a separate floating window listing every principle Sticky has learned, organized by domain (design / writing / code / general).
- **Floating chat window** — for longer back-and-forth conversations with Sticky outside the menu bar panel.
- **Persona wheel** — quick switcher for swapping between Me / Team / teammate personas. Each persona has its own voice, avatar, and taste profile.
- **Personal vs Team taste** — toggle between your private profile and a pooled team profile.
- **Element pointing** — Sticky can embed `[POINT:x,y:label:screenN]` tags in its responses; the cursor animates to the spot on the right monitor.

## Manual setup

### Prerequisites

- macOS 14.2+ (for ScreenCaptureKit)
- Xcode 15+
- Node.js 18+ (for the Cloudflare Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier works)
- API keys for: [Anthropic](https://console.anthropic.com), [AssemblyAI](https://www.assemblyai.com), [ElevenLabs](https://elevenlabs.io)

### 1. Set up the Cloudflare Worker

The Worker is a tiny proxy that holds your API keys. The app talks to the Worker, the Worker talks to the APIs. This way your keys never ship in the app binary.

```bash
cd worker
npm install
```

Now add your secrets. Wrangler will prompt you to paste each one:

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```

For the ElevenLabs voice ID, open `wrangler.toml` and set it there (it's not sensitive):

```toml
[vars]
ELEVENLABS_VOICE_ID = "your-voice-id-here"
```

Deploy it:

```bash
npx wrangler deploy
```

It'll give you a URL like `https://your-worker-name.your-subdomain.workers.dev`. Copy that.

### 2. Run the Worker locally (for development)

If you want to test changes to the Worker without deploying:

```bash
cd worker
npx wrangler dev
```

This starts a local server (usually `http://localhost:8787`) that behaves exactly like the deployed Worker. Create a `.dev.vars` file in the `worker/` directory with your keys:

```
ANTHROPIC_API_KEY=sk-ant-...
ASSEMBLYAI_API_KEY=...
ELEVENLABS_API_KEY=...
ELEVENLABS_VOICE_ID=...
```

Then update the proxy URLs in the Swift code to point to `http://localhost:8787` instead of the deployed Worker URL while developing.

### 3. Update the proxy URLs in the app

The app has the Worker URL hardcoded in a few places. Search for the existing Worker hostname and replace it with your Worker URL. You'll find it in:

- [leanring-buddy/CompanionManager.swift](leanring-buddy/CompanionManager.swift) — Claude chat + ElevenLabs TTS
- [leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift](leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift) — AssemblyAI token endpoint

### 4. Open in Xcode and run

```bash
open leanring-buddy.xcodeproj
```

In Xcode:
1. Select the `leanring-buddy` scheme
2. Set your signing team under Signing & Capabilities
3. Hit **Cmd + R** to build and run

The app appears in your menu bar (not the dock). Click the icon to open the panel, grant the permissions it asks for, and you're good.

### Permissions the app needs

- **Microphone** — for push-to-talk voice capture and teach-session dictation
- **Accessibility** — for the global keyboard shortcut (Control + Option)
- **Screen Recording** — for taking screenshots when you use the hotkey
- **Screen Content** — for ScreenCaptureKit access

## How to use it

1. **Hold Control + Option** anywhere on macOS, speak, and release. Sticky captures a screenshot of your current screen and answers using your stored taste principles. The cursor may fly to elements it points at.
2. **Open the menu bar panel** to start a Teach Session, switch personas, toggle Personal/Team scope, open the chat window, or view the memory library.
3. **Teach Session**: tap *Start Teach Session*, work normally and narrate your creative decisions. Tap *Stop* when done. Sticky shows a stack of candidate principles — Remember the ones that match how you actually think, Skip the rest. Approved principles persist to disk.
4. **Personas**: pick *Me*, *Team*, or any of the bundled teammates. The selected persona's voice, face, and taste profile take over until you switch back.

Taste profiles live locally at `~/Library/Application Support/com.learning-buddy.clicky/`:

- `taste-profile.json` — your personal principles
- `team-profile.json` — the pooled team profile

## Architecture

If you want the full technical breakdown, read [AGENTS.md](AGENTS.md). Short version:

Menu bar app (no dock icon) with several `NSPanel` windows — control panel dropdown, full-screen transparent cursor overlay, floating chat window, taste library window. Push-to-talk streams audio over a websocket to AssemblyAI, sends the transcript + screenshot to Claude via streaming SSE, and plays the response through ElevenLabs TTS. Claude can embed `[POINT:x,y:label:screenN]` tags in its responses to make the cursor fly to specific UI elements across multiple monitors. Teach sessions reuse the same pipeline but use a different system prompt that asks Claude to extract a `TastePrinciple` as JSON. Apply mode prepends a taste-context block (built from your saved principles) to the standard system prompt. All three APIs are proxied through a Cloudflare Worker.

## Project structure

```
leanring-buddy/                       # Swift source
  CompanionManager.swift                # Central state machine
  CompanionPanelView.swift              # Menu bar panel UI
  ClaudeAPI.swift                       # Claude streaming client
  ElevenLabsTTSClient.swift             # Text-to-speech playback
  OverlayWindow.swift                   # Blue cursor overlay
  AssemblyAI*.swift                     # Real-time transcription
  BuddyDictation*.swift                 # Push-to-talk pipeline

  # Teach / Apply (taste)
  TasteTypes.swift                      # Codable shapes (TastePrinciple, TasteProfile, …)
  TasteExtractionPrompt.swift           # Teach-mode system prompt
  SessionAnalyzer.swift                 # Teach-session screenshot → principles
  ReviewCardStack.swift                 # Remember/Skip review UI
  TeachSessionResultCard.swift          # End-of-session summary
  TasteProfileStore.swift               # Personal profile (JSON on disk)
  TeamTasteProfileStore.swift           # Team profile (JSON on disk)
  TastePromptBuilder.swift              # Injects principles into apply-mode prompts
  TasteProfileExporter.swift            # Export/import support
  AppliedPrinciplesChip.swift           # Shows which principles grounded a reply

  # Personas
  PersonaBundle.swift                   # Persona data shape
  PersonaStore.swift                    # Bundled teammates + selection state
  PersonaAvatarView.swift               # Cursor face renderer
  PersonaTasteFileStore.swift           # Per-persona taste files
  PersonaWheelView.swift                # Quick persona switcher
  PersonaWheelHotkeyMonitor.swift       # Global hotkey for the wheel
  VoicePreviewCache.swift               # Pre-rendered voice samples

  # Chat window
  ChatView.swift / ChatViewModel.swift  # Floating chat UI + state
  ChatWindowController.swift            # Window lifecycle
  ChatMarkdownRenderer.swift            # Markdown rendering

  # Taste library window
  TasteLibraryView.swift                # Browse all approved principles
  TasteLibraryWindowController.swift    # Window lifecycle

  personas/                             # Bundled teammate taste files (TASTE.md per persona)

worker/                                 # Cloudflare Worker proxy
  src/index.ts                            # Three routes: /chat, /tts, /transcribe-token

demo/                                   # Demo assets (sample team profile)
AGENTS.md                               # Full architecture doc
CLAUDE.md                               # Agent instructions for working in this repo
```

## About Clicky

Sticky is a fork of [Clicky](https://github.com/the-rebase/clicky), an AI tutor that lives next to your cursor and teaches you things on-screen. Sticky inverts the relationship: instead of teaching you, it learns *from* you, and uses what it learns to critique your work in your voice (or your team's). The underlying companion shell — push-to-talk, screen capture, streaming responses, blue cursor pointing — is all Clicky.
