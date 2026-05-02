# Edge Glow Redesign — Spec

Self-contained spec for rewriting the screen-edge aurora so it can:

1. Anchor to the **bottom** edge during Ask listening (current behaviour, keep it)
2. Anchor to the **top** edge in a different palette during Ask responding
3. Glow on **all four edges** during Teach recording, mic-reactive

You can hand this to an agent or implement it directly. Nothing in this doc depends on Reverse Clicky logic — the code lives entirely in [OverlayWindow.swift](leanring-buddy/OverlayWindow.swift).

## Why this matters

The current overlay tells the user *something* is happening but doesn't separate input from output, or voice mode from teach mode. The directional language ("glow comes from where the conversation is coming from") is the cheapest way to make all four states unmistakably distinct without adding new chrome.

## Current state (what exists today)

- `EdgeGlowView` (in `OverlayWindow.swift` ~line 962+): a stack of bottom-anchored "ribbons" — each ribbon is a band of colour whose top edge undulates as the sum of two sine waves. Phase shifts continuously, drifts laterally. Reads as an aurora curtain rising from the bottom.
- `EdgeGlowMode` enum: `.listeningToUser` | `.processingThinking` | `.respondingWithAI`. Each has its own palette/motion config in `EdgeGlowModeStyle.style(for:)`.
- All three modes render at the **bottom** edge today. The differentiation between listening / responding is purely palette + motion speed, not direction.
- `BlueCursorView` (in `OverlayWindow.swift` ~line 100+) decides visibility, mode, and audio source via three computed properties: `edgeGlowShouldBeVisible`, `edgeGlowMode`, `edgeGlowAudioPowerLevel`. These are the only places that read `companionManager` state — keep that boundary.
- During Reverse Clicky teach recording, the edge glow already turns on (small change shipped 2026-05-02) and reuses the listening palette. That's the placeholder this redesign replaces.

## The four states

| Mode + state | Edges that glow | Audio source | Palette / energy |
|---|---|---|---|
| **Ask** — listening (user holding ctrl+option) | Bottom only | `currentAudioPowerLevel` (mic) | Cool aurora — current `.listeningToUser` |
| **Ask** — processing (waiting for Claude) | Bottom only | None — synthetic 2.4s pulse | Current `.processingThinking` (cool, calmer) |
| **Ask** — responding (TTS playing) | **Top only** | `currentTTSPowerLevel` | Different from listening — warm skew (current `.respondingWithAI` palette is already pinker, but it's currently bottom-anchored; flip it) |
| **Teach** — recording (continuous dictation) | **All four edges** | `currentAudioPowerLevel` (mic) | Distinct from both Ask states — proposed: amber / warning palette per [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) item #4. Keeps the "I'm in a different mode" message even at a glance. |

States not covered (idle, navigating to element, pointing at element) keep current behaviour.

## Proposed API

Parametrize `EdgeGlowView` so the same ribbon stack can render against any edge anchor with any palette:

```swift
enum EdgeGlowAnchor {
    case bottom
    case top
    case all  // four edges, one ribbon stack per edge
}

enum EdgeGlowMode {
    case listeningToUser     // existing
    case processingThinking  // existing
    case respondingWithAI    // existing — NEW: ALSO defaults to .top anchor
    case teachRecording      // NEW: amber palette, .all anchor
}

struct EdgeGlowView: View {
    let audioPowerLevel: CGFloat
    let mode: EdgeGlowMode
    let anchor: EdgeGlowAnchor
    let pullTarget: CGPoint?  // existing, only meaningful for bottom for now
    // ...
}
```

The mode → anchor mapping can default inside `EdgeGlowView` if the call site doesn't override:

```swift
extension EdgeGlowMode {
    var defaultAnchor: EdgeGlowAnchor {
        switch self {
        case .listeningToUser, .processingThinking: return .bottom
        case .respondingWithAI: return .top
        case .teachRecording: return .all
        }
    }
}
```

Reduce the API surface area exposed to `BlueCursorView` by letting the mode imply the anchor — only override if there's ever a state that wants a non-default edge.

## Required code changes

### 1. `EdgeGlowMode` — add `.teachRecording`

In the `EdgeGlowModeStyle.style(for:)` switch, add a case:

```swift
case .teachRecording:
    return EdgeGlowModeStyle(
        usesSyntheticPulse: false,
        pulsePeriodSeconds: 0,
        phaseSpeedMultiplier: 0.9,
        amplitudeMultiplier: 1.0,
        // amber/warm tilt — boost orange/yellow analogues, cut greens/cyans
        indigoOpacityScale: 0.30,
        blueOpacityScale: 0.20,
        cyanOpacityScale: 0.10,
        greenOpacityScale: 0.55,   // for amber blend
        magentaOpacityScale: 0.60,  // for amber blend
        whiteOpacityScale: 1.0,
        pinkOpacityScale: 0.85
    )
```

Tune the opacity scalars by eye — the existing palette is fixed in the ribbon stack itself, so we're skewing it via per-colour opacity rather than swapping in new colour stops. If amber doesn't land convincingly with this approach, the cleaner option is to add a `tintColor` parameter to the ribbon definitions and let teach mode pass `Color.orange.opacity(...)`.

### 2. Refactor the ribbon math to take an `anchor`

Today every ribbon is a `Path` that draws from `y = baseline - undulation` to `y = screenHeight` (bottom-anchored). Generalise:

- `.bottom`: same as today.
- `.top`: flip the y-axis. Either render the same ribbon and apply `.scaleEffect(y: -1, anchor: .top)`, or rewrite the path to use `y = undulation` to `y = 0`. Scale-effect is the smaller diff but you lose per-ribbon shadow accuracy.
- `.all`: render four `EdgeGlowView` instances stacked in a `ZStack`, one per edge. Use rotation transforms (`rotationEffect(.degrees(90))`, etc.) on the bottom-anchored view to face the left/right edges. **Watch out**: rotated views share the `pullTarget` math which assumes screen coordinates — for `.all`, ignore `pullTarget` (only the bottom edge bends toward the pointing target; sides + top hang straight).

The cleanest internal structure:

```swift
private struct SingleEdgeAurora: View {
    let audioPowerLevel: CGFloat
    let modeStyle: EdgeGlowModeStyle
    let pullTarget: CGPoint?
    var body: some View { /* the existing ribbon stack, bottom-anchored */ }
}

struct EdgeGlowView: View {
    let audioPowerLevel: CGFloat
    let mode: EdgeGlowMode
    let anchor: EdgeGlowAnchor
    let pullTarget: CGPoint?

    var body: some View {
        let style = EdgeGlowModeStyle.style(for: mode)
        switch anchor {
        case .bottom:
            SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: pullTarget)
        case .top:
            SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: nil)
                .scaleEffect(y: -1, anchor: .center)  // mirrors so the curtain hangs down from top
        case .all:
            ZStack {
                SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: nil)  // bottom
                SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: nil)
                    .scaleEffect(y: -1, anchor: .center)  // top
                SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: nil)
                    .rotationEffect(.degrees(90), anchor: .center)  // right
                SingleEdgeAurora(audioPowerLevel: audioPowerLevel, modeStyle: style, pullTarget: nil)
                    .rotationEffect(.degrees(-90), anchor: .center)  // left
            }
        }
    }
}
```

The `.all` case may need each ribbon dimmed (e.g. `.opacity(0.7)`) so four overlapping stacks don't read as a hard outline.

### 3. Update `BlueCursorView`

Three property updates near line 215:

```swift
private var edgeGlowShouldBeVisible: Bool {
    guard buddyIsVisibleOnThisScreen else { return false }
    if companionManager.teachSessionState == .recording { return true }
    switch companionManager.voiceState {
    case .listening, .processing, .responding: return true
    case .idle: return false
    }
}

private var edgeGlowMode: EdgeGlowMode {
    if companionManager.teachSessionState == .recording { return .teachRecording }
    switch companionManager.voiceState {
    case .listening: return .listeningToUser
    case .processing: return .processingThinking
    case .responding: return .respondingWithAI
    case .idle: return .listeningToUser  // unused
    }
}

private var edgeGlowAudioPowerLevel: CGFloat {
    if companionManager.teachSessionState == .recording {
        return companionManager.currentAudioPowerLevel
    }
    switch companionManager.voiceState {
    case .listening: return companionManager.currentAudioPowerLevel
    case .responding: return companionManager.currentTTSPowerLevel
    case .processing, .idle: return 0
    }
}
```

And update the `EdgeGlowView(...)` instantiation around line 275 to pass an anchor. Easiest: add a computed `edgeGlowAnchor` that derives from `edgeGlowMode` via `EdgeGlowMode.defaultAnchor`. That way callers don't have to think about anchor at all.

## Order of work

1. Add `.teachRecording` case to `EdgeGlowMode` and a corresponding `EdgeGlowModeStyle` entry. Build, verify nothing else breaks (the compiler will flag any non-exhaustive switches over `EdgeGlowMode` — there's at least one).
2. Wire `BlueCursorView` to use `.teachRecording` when a teach session is recording. Keep the anchor as `.bottom` for now. Verify teach mode visually changes palette.
3. Extract `SingleEdgeAurora` from the existing `EdgeGlowView` body. No behaviour change. Verify nothing visual changed.
4. Add `EdgeGlowAnchor` enum and the `anchor` parameter on `EdgeGlowView`. Default `.bottom` everywhere. No behaviour change.
5. Implement `.top` rendering. Wire `.respondingWithAI` to use it. Test that the AI's reply now glows from the top edge.
6. Implement `.all` rendering. Wire `.teachRecording` to use it. Test mic-reactivity works on all four edges.
7. Tune opacity scalars and `.all` per-edge dimming until each state reads cleanly. Iterate by eye.

Steps 1–2 are independently shippable — you can land that in a small PR and pause. Steps 3–7 build on each other.

## Risks / things to watch

- **Top-anchored ribbons via `scaleEffect(y: -1)`** might flip shadows weirdly. If the responding glow looks "wrong" rather than "mirrored", rewrite the ribbon path math to anchor at top instead of using a transform.
- **All-edges mode is heavy.** Four overlapping ribbon stacks at full opacity will dominate the screen and probably hurt frame rate. Start with all four at `.opacity(0.5)` and turn up only if it reads as "too subtle."
- **`pullTarget`** (the gravity that bends the bottom curtain toward a pointing target) only works for the bottom edge. Pass `nil` for `.top` and `.all` until/unless we add equivalent math for those edges.
- **State transitions.** When the user goes from listening (bottom glow) to responding (top glow), there's currently a single `.animation(.easeInOut(duration: 0.4), value: companionManager.voiceState)` on the EdgeGlowView. With anchor changes, that crossfade may look like a hard cut from bottom to top rather than a smooth handoff. Consider keeping both anchors mounted with separate opacity drivers if it looks abrupt.
- **Teach session palette tuning.** The opacity-scalar approach to amber may not get there. If after one pass it still reads as "blue-ish weird" rather than amber, the next escalation is a `tintColor` parameter inside `EdgeGlowModeStyle` that overrides the ribbon colours entirely.
- **Don't break Ask listening.** That's the most-used path. Land `.bottom` cleanly first, verify nothing regressed, then move on.

## Out of scope

- Animating the anchor itself (e.g. ribbons sliding from bottom to top during the listening → responding transition). Crossfade is enough for the demo.
- A teach-mode "screen-edge pill" with elapsed time. That's tracked separately under [TEACH_MODE_PLAN.md](TEACH_MODE_PLAN.md) item #4 "If time."
- Mode-aware `pullTarget` (gravity from any edge). Bottom-only is fine.

## Done looks like

A user holding ctrl+option sees a cool aurora glow up from the bottom edge that reacts to their voice. Releasing → the glow stays bottom-anchored but switches to the calmer "thinking" pulse for ~1 second. When the AI replies, the glow flips to the top edge in a noticeably different palette and reacts to the TTS. Switching to Teach mode and clicking Start → an amber halo wraps the entire screen and reacts to the user's voice while they narrate.
