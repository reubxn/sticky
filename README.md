<div align="center">

<img src="docs/images/logo.png" alt="Clicky" width="120" />

# Clicky

**A macOS menu bar companion that learns your taste.**

Hold a key, talk through a creative decision, and Clicky extracts a reusable taste principle. Saved principles become a personal or team knowledgebase the AI uses later to critique work, suggest improvements, and tell you whether something matches your style.

<br />

<img src="docs/images/hero.png" alt="Clicky in action" width="820" />

<br />

<sub>macOS 14.2+ &nbsp;·&nbsp; SwiftUI &nbsp;·&nbsp; Claude (Sonnet 4.6 / Opus 4.6) &nbsp;·&nbsp; AssemblyAI &nbsp;·&nbsp; ElevenLabs</sub>

</div>

---

## The 30-second pitch

Most AI tools forget you the moment the conversation ends. Clicky watches *how you make decisions* — what you keep, what you cut, what you reword — and turns that into durable, reusable taste. Next time you ask for feedback, the answer is grounded in your style, not a generic best-practice checklist.

<div align="center">
<img src="docs/images/demo.gif" alt="Full Teach → Remember → Apply loop" width="780" />
</div>

---

## Three modes

Switch between modes from the menu bar panel. Same gesture (hold ctrl+option, speak, release) — different brain.

<table>
<tr>
<td width="33%" valign="top">

### Ask

<img src="docs/images/mode-ask.png" alt="Ask mode" width="100%" />

Hold ctrl+option, ask anything about what's on screen. Streamed answer with optional cursor pointing at the element you're asking about.

</td>
<td width="33%" valign="top">

### Teach

<img src="docs/images/mode-teach.png" alt="Teach mode" width="100%" />

Hold ctrl+option, talk through a creative choice. *"I made the logo bigger because brand presence matters."* Clicky distills it into a single taste principle to Remember or Skip.

</td>
<td width="33%" valign="top">

### Apply

<img src="docs/images/mode-apply.png" alt="Apply mode" width="100%" />

Hold ctrl+option, ask anything. Your saved principles are injected into the prompt so the answer is grounded in your style. Toggle Personal / Team profiles.

</td>
</tr>
</table>

---

## How it works

<div align="center">
<img src="docs/images/architecture.png" alt="Architecture diagram" width="780" />
</div>

1. **Capture** — push-to-talk via `AVAudioEngine` + a system-wide listen-only `CGEvent` tap. While you hold the key, a waveform appears on screen so you always know capture is live.
2. **Transcribe** — AssemblyAI streams the transcript back over a websocket; OpenAI and Apple Speech are fallbacks.
3. **See** — on key release, ScreenCaptureKit grabs the active monitor.
4. **Reason** — transcript + screenshot go to Claude through a Cloudflare Worker proxy. The system prompt depends on the mode you're in.
5. **Persist** — in Teach mode, the JSON principle is shown in a review card. Remember writes it to `~/Library/Application Support/com.learning-buddy.clicky/taste-profile.json`.
6. **Apply** — in Apply mode, every Claude call is preceded by a taste-context block built from your saved principles.

---

## The taste profile

<table>
<tr>
<td width="50%" valign="top">

<img src="docs/images/review-card.png" alt="Principle review card" width="100%" />

After each Teach press, Clicky surfaces a single proposed principle. Two buttons: **Remember** or **Skip**. No editing — keep the loop tight.

</td>
<td width="50%" valign="top">

```json
{
  "id": "p1",
  "domain": "design",
  "statement": "Prefers strong brand presence
                and clear visual hierarchy.",
  "confidence": 0.82,
  "evidence": [
    "User enlarged the logo while saying
     'brand presence matters more than whitespace'."
  ],
  "tags": ["brand", "hierarchy"],
  "approved": true
}
```

Stored locally as JSON. Nothing leaves your machine except the per-press transcript + screenshot to the model.

</td>
</tr>
</table>

---

## Personal vs Team

<div align="center">
<img src="docs/images/personal-team.png" alt="Personal / Team toggle" width="540" />
</div>

In Apply mode, flip between **Personal** (just your principles) and **Team** (the union of everyone's). Team profiles are plain JSON, hand-written or exported — no backend, no admin panel.

---

## API proxy

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS audio |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Short-lived (480s) AssemblyAI websocket token |

Worker secrets: `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`. Worker var: `ELEVENLABS_VOICE_ID`.

---

## Build & run

```bash
open leanring-buddy.xcodeproj
```

Select the `leanring-buddy` scheme, set your signing team, ⌘R.

> Do **not** run `xcodebuild` from the terminal — it invalidates TCC permissions (Screen Recording, Accessibility, Microphone) and the app will need to re-request them.

<details>
<summary><b>Worker setup</b></summary>

```bash
cd worker
npm install

npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

npx wrangler deploy
```

For local development create `worker/.dev.vars` with your keys and run `npx wrangler dev`.

</details>

---

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

---

## Privacy

- Capture only happens while you're actively holding ctrl+option. The waveform indicator is visible the entire time.
- No background or always-on capture.
- Screenshots are sent to the Worker proxy in-memory and not retained on disk.
- Taste principles are stored locally only; nothing is added to your profile until you tap **Remember**.

---

<div align="center">
<sub>Built as a fork of Clicky for the Reverse Clicky hackathon.</sub>
</div>
