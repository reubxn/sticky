# Instinct

A macOS menu bar companion that learns your taste.

Hold a key, talk through a creative decision, and Instinct extracts a reusable taste principle. Saved principles become a personal or team knowledgebase the AI uses later to critique work, suggest improvements, and tell you whether something matches your style.

## What it does

Three modes, switched from the menu bar panel:

- **Ask** — hold ctrl+option, ask a question about what's on screen, get a streamed answer with optional cursor pointing.
- **Teach** — hold ctrl+option, talk through a creative decision ("I made the logo bigger because brand presence matters"). Instinct turns it into a single taste principle for you to Remember or Skip.
- **Apply** — hold ctrl+option, ask anything. Your saved taste principles are injected into the prompt so the answer is grounded in your style. Toggle between Personal and Team profiles.

Taste principles live in `~/Library/Application Support/com.learning-buddy.clicky/taste-profile.json` (and `team-profile.json` for the team profile). Nothing is stored remotely.

## Architecture

- **App type** — menu bar only (`LSUIElement=true`), no dock icon, no main window. Lives in `NSStatusItem` with a custom borderless `NSPanel` for the floating control panel.
- **Framework** — SwiftUI with AppKit bridging for the menu bar panel and full-screen cursor overlay.
- **AI** — Claude (Sonnet 4.6 default, Opus 4.6 optional) via SSE streaming.
- **Speech-to-text** — AssemblyAI real-time streaming over a websocket, with OpenAI and Apple Speech as fallbacks.
- **Text-to-speech** — ElevenLabs (`eleven_flash_v2_5`).
- **Screen capture** — ScreenCaptureKit (macOS 14.2+), multi-monitor support.
- **Voice input** — push-to-talk via `AVAudioEngine` and a system-wide listen-only `CGEvent` tap so modifier-based shortcuts (ctrl+option) are detected reliably in the background.
- **Element pointing** — the model embeds `[POINT:x,y:label:screenN]` tags in replies; a transparent overlay parses them and animates a blue cursor along a bezier arc to the target on the correct monitor.

### API proxy

The app never talks to external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`. Worker var: `ELEVENLABS_VOICE_ID`.

## Build & run

```bash
open leanring-buddy.xcodeproj
```

Select the `leanring-buddy` scheme, set your signing team, ⌘R.

> Do **not** run `xcodebuild` from the terminal — it invalidates TCC permissions (Screen Recording, Accessibility, Microphone) and the app will need to re-request them.

## Worker

```bash
cd worker
npm install

npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

npx wrangler deploy
```

For local development create `worker/.dev.vars` with your keys and run `npx wrangler dev`.

## Project layout

```
leanring-buddy/                  ← macOS app source
  CompanionManager.swift         ← central state machine (voice + taste mode)
  CompanionPanelView.swift       ← menu bar panel UI (mode picker lives here)
  OverlayWindow.swift            ← transparent full-screen overlay (cursor, waveform, text)
  BuddyDictationManager.swift    ← push-to-talk + transcription pipeline
  ClaudeAPI.swift                ← Claude vision + streaming client
  ElevenLabsTTSClient.swift      ← TTS playback
  DesignSystem.swift             ← DS.Colors / DS.CornerRadius / DS.Spacing tokens
  ...
ReverseClicky/                   ← taste-mode modules
  Shared/TasteTypes.swift        ← TasteMode, TastePrinciple, TasteProfile, ...
  Analysis/                      ← teach-mode prompt + principle review card + profile store
  Apply/                         ← apply-mode prompt builder + team profile store
  demo/                          ← seed taste profiles + demo script
worker/                          ← Cloudflare Worker proxy
```

## Privacy

- Capture only happens while you're actively holding ctrl+option. The waveform indicator is visible the entire time.
- No background or always-on capture.
- Screenshots are sent to the Worker proxy in-memory and not retained on disk.
- Taste principles are stored locally only; nothing is added to your profile until you tap **Remember**.
