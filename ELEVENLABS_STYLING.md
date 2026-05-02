# ElevenLabs Branding — Styling Reference

A SwiftUI styling system inspired by ElevenLabs' visual identity. Lives in [leanring-buddy/DesignSystem.swift](leanring-buddy/DesignSystem.swift) under the `ElevenLabsBrand` namespace, alongside the existing dark `DS` palette. The two coexist — adopt this system per-screen without breaking the rest of the app.

---

## Brand Principles

The look is editorial, not product. Think printed magazine, gallery poster, transit OOH — not a dashboard.

1. **Paper, not screen.** Backgrounds are warm off-white (`#F4F2ED`), not pure white. Cards are pure white with hairline borders so they read as paper-on-paper, not panels-on-panels.
2. **Ink, not gray.** Foreground text is near-black (`#0B0B0B`) with deliberate weight — heavy sans for headlines, regular for body. Avoid mid-grays except for tertiary metadata.
3. **Gradient as image, not chrome.** Saturated mesh gradients (sunset, sky-blush, ember, cool) appear inside cards as feature surfaces — never as page backgrounds. Always overlaid with the topographic clover-grid line motif.
4. **Whitespace > decoration.** Padding is closer to print editorial than typical UI density. When in doubt, add air.
5. **Right-angle confidence.** Card corners are subtle (14pt) but present. Pills are fully rounded for buttons and metadata only.
6. **One mark, one wordmark.** The "II + ElevenLabs" lockup is the brand's visual anchor. Don't apply it to UI labels — only as the brand mark.

---

## Tokens

All tokens live under `ElevenLabsBrand.*` in [leanring-buddy/DesignSystem.swift](leanring-buddy/DesignSystem.swift).

### Colors — Surfaces & Ink

| Token | Hex | Use |
|---|---|---|
| `Colors.paper` | `#F4F2ED` | Page background. The warm off-white. |
| `Colors.card` | `#FFFFFF` | Pure white cards floating on paper. |
| `Colors.paperRecessed` | `#ECEAE4` | Alternating sections, secondary surfaces. |
| `Colors.ink` | `#0B0B0B` | Primary text — headlines, body. |
| `Colors.inkPure` | `#000000` | Wordmark, poster headlines, dark hero surface. |
| `Colors.inkSecondary` | `#3D3D3B` | Body copy, supporting labels. |
| `Colors.inkTertiary` | `#7A7A77` | Captions, metadata pills, eyebrows. |
| `Colors.hairline` | `#DEDBD3` | 1px card borders, dotted grid frames. |
| `Colors.hairlineStrong` | `#B9B5AB` | Hover/focus border. |
| `Colors.onAccent` | `#FFFFFF` | Text on top of gradient surfaces or ink fills. |

### Colors — Gradient Mesh Stops

These are the recurring stops that compose every ElevenLabs gradient surface. Recombine them; don't introduce new hues.

| Token | Hex | Where it appears |
|---|---|---|
| `Colors.gradientSky` | `#A6C3F2` | Bus-stop poster top, "british narration" tile |
| `Colors.gradientPeriwinkle` | `#7C8BD9` | "Video games" voice tile, deeper blue mesh |
| `Colors.gradientBlush` | `#F5C8D1` | Audiobook hero card, voice cards |
| `Colors.gradientCoral` | `#E8593A` | Summit 25 posters, lanyard speaker badge |
| `Colors.gradientSunset` | `#F1A06A` | "Bring your stories to life" tile |
| `Colors.gradientGoldenrod` | `#F2D08A` | Multi-stop warmth between sunset and blush |
| `Colors.gradientLavender` | `#C9B6E8` | Cool edge of chat-preview gradient |

### Colors — Dark Hero

Use only for the inverted hero surface ("The most realistic voice AI platform" trade-show wall).

| Token | Hex |
|---|---|
| `Colors.darkHero` | `#0A0A0A` |
| `Colors.darkHeroInk` | `#F4F2ED` |
| `Colors.darkHeroHairline` | white at 10% |

### Typography

Maps to SF Pro on macOS, weighted to approximate ElevenLabs' tightly tracked geometric sans.

| Token | Default size | Weight | Use |
|---|---|---|---|
| `Typography.display(size:)` | 56 | bold | Giant poster headline ("Summit 25"). |
| `Typography.hero(size:)` | 36 | semibold | Landing-page title ("Generate high-quality AI audio…"). |
| `Typography.cardTitle(size:)` | 22 | semibold | Card headline ("Epic voices for british narration"). |
| `Typography.eyebrow` | 11 | medium | Category label above a hero ("For Creators…", "Collections", "Top picks"). |
| `Typography.body` | 14 | regular | Running paragraph text inside cards. |
| `Typography.bodyStrong` | 14 | semibold | Bold product names ("Audiobooks", "Video Voiceovers"). |
| `Typography.caption` | 11 | medium | Metadata pills ("14m", "2.1k"), timestamps. |
| `Typography.wordmark(size:)` | 20 | bold | Brand lockup only. |

For headlines, apply `.tracking(-0.5)` to mimic the dense ElevenLabs setting. For eyebrows apply `.tracking(0.2)`.

### Radius

| Token | Value | Use |
|---|---|---|
| `Radius.pill` | 999 | Buttons, metadata chips. |
| `Radius.card` | 14 | Cards, gradient tiles, billboard frame. |
| `Radius.chip` | 10 | Inner elements (chat bubbles inside preview cards). |
| `Radius.crisp` | 2 | Near-zero corners for poster-style elements. |

### Spacing

Larger than `DS.Spacing` — closer to editorial print rhythm.

| Token | Value |
|---|---|
| `Spacing.xs` | 6 |
| `Spacing.sm` | 12 |
| `Spacing.md` | 20 |
| `Spacing.lg` | 32 |
| `Spacing.xl` | 48 |
| `Spacing.xxl` | 72 |

### Gradients

Four mesh presets implemented as multi-stop `LinearGradient`s. Layer `ElevenLabsCloverOverlay` on top for the full mesh look.

| Token | Composition | Where it appears |
|---|---|---|
| `Gradients.sunset` | Coral → Sunset → Goldenrod → Blush, top-leading → bottom-trailing | Summit 25 posters, lanyard speaker badge |
| `Gradients.skyBlush` | Sky → Lavender → Blush → Sunset, top-trailing → bottom-leading | Bus-stop poster |
| `Gradients.ember` | Coral → Sunset → Goldenrod, top-leading → bottom-trailing | "British narration" voice tile warm corner |
| `Gradients.cool` | Periwinkle → Sky → Lavender → Blush, top-leading → bottom-trailing | "Video games", "Stories to life" voice tiles |

### Shadow

`ElevenLabsBrand.Shadow.card(_:)` applies the signature soft drop shadow on white cards floating over paper. Two layered shadows under 8px radius — subtle, so cards read as printed pieces, not floating UI.

---

## Components

### `ElevenLabsWordmark(size:color:)`

The brand lockup — the "II" pause-bars mark followed by the "ElevenLabs" wordmark.

```swift
ElevenLabsWordmark(size: 24)                                    // ink on paper
ElevenLabsWordmark(size: 20, color: .white)                     // on dark/gradient
```

**Don't** use this as a UI heading. Only as the brand mark in headers, footers, and brand surfaces.

### `ElevenLabsCard { … }`

White card on paper with hairline border and subtle shadow. The default chrome for any editorial content.

```swift
ElevenLabsCard {
    VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
        ElevenLabsEyebrow("For Creators, Media & Entertainment")
        Text("Generate high-quality AI audio for your audiobooks, videos and podcasts")
            .font(ElevenLabsBrand.Typography.hero())
            .foregroundColor(ElevenLabsBrand.Colors.ink)
    }
}
```

Configurable `padding:` and `radius:` if you need to deviate from defaults — but prefer the defaults.

### `ElevenLabsGradientTile(gradient:) { label }`

The signature voice-card / poster tile. A gradient surface with the clover-grid overlay and an optional centered label slot.

```swift
ElevenLabsGradientTile(gradient: ElevenLabsBrand.Gradients.skyBlush) {
    ElevenLabsWordmark(size: 28, color: .white)
}
.frame(height: 220)
```

Pass `showsOverlay: false` to suppress the clover lines if you need a clean gradient (rare — the overlay is part of the brand).

### `ElevenLabsCloverOverlay`

Procedural quatrefoil-on-grid line motif. Layer it manually on any custom gradient when you can't use `ElevenLabsGradientTile`.

```swift
ZStack {
    RoundedRectangle(cornerRadius: 14).fill(myCustomGradient)
    ElevenLabsCloverOverlay(lineColor: .white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
}
```

### `ElevenLabsEyebrow("…")`

The small category label that sits above hero headlines and section titles.

```swift
ElevenLabsEyebrow("Top picks")
```

### `.elevenLabsPrimaryButtonStyle()`

Pill-shaped CTA — black fill with white label, inverts to white-with-black-label on hover. Mirrors the "Try a call" button on voice cards.

```swift
Button("Try a call") { startCall() }
    .elevenLabsPrimaryButtonStyle(isFullWidth: false)
```

---

## Composition Recipes

### Hero card (audiobook landing)

```swift
ZStack {
    ElevenLabsBrand.Colors.paper.ignoresSafeArea()

    VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.lg) {
        ElevenLabsEyebrow("For Creators, Media & Entertainment")
        Text("Generate high-quality AI audio for your audiobooks, videos and podcasts")
            .font(ElevenLabsBrand.Typography.hero())
            .tracking(-0.5)
            .foregroundColor(ElevenLabsBrand.Colors.ink)

        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.lg) {
            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
                Text("Audiobooks").font(ElevenLabsBrand.Typography.bodyStrong)
                Text("Our ElevenReader app narrates articles, PDFs, ePubs…")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }
            ElevenLabsGradientTile(gradient: ElevenLabsBrand.Gradients.cool)
                .frame(width: 360, height: 220)
        }
    }
    .padding(ElevenLabsBrand.Spacing.xl)
}
```

### Voice card (the "Try a call" Lilly/Jonathan/Lucian/Jennifer cards)

```swift
ElevenLabsCard(padding: ElevenLabsBrand.Spacing.md) {
    VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
        Circle()
            .fill(ElevenLabsBrand.Gradients.cool)
            .frame(width: 140, height: 140)

        HStack(spacing: ElevenLabsBrand.Spacing.xs) {
            Text("14m").font(ElevenLabsBrand.Typography.caption)
            Text("2.1k").font(ElevenLabsBrand.Typography.caption)
        }
        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

        Text("Lilly")
            .font(ElevenLabsBrand.Typography.cardTitle())
            .foregroundColor(ElevenLabsBrand.Colors.ink)

        Button("Try a call") { /* ... */ }
            .elevenLabsPrimaryButtonStyle()
    }
}
.frame(width: 200)
```

### Dark hero ("The most realistic voice AI platform")

```swift
ZStack {
    ElevenLabsBrand.Colors.darkHero.ignoresSafeArea()

    VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.xl) {
        ElevenLabsWordmark(size: 22, color: ElevenLabsBrand.Colors.darkHeroInk)
        Text("The most realistic voice AI platform")
            .font(ElevenLabsBrand.Typography.display())
            .tracking(-0.5)
            .foregroundColor(ElevenLabsBrand.Colors.darkHeroInk)
    }
    .padding(ElevenLabsBrand.Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
```

### Poster (Summit 25 social tile)

```swift
ElevenLabsGradientTile(gradient: ElevenLabsBrand.Gradients.skyBlush) {
    VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.lg) {
        Text("ElevenLabs\nSummit 25")
            .font(ElevenLabsBrand.Typography.display(size: 64))
            .tracking(-1.0)
            .foregroundColor(ElevenLabsBrand.Colors.inkPure)
            .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()

        ElevenLabsWordmark(size: 32, color: ElevenLabsBrand.Colors.inkPure)
    }
    .padding(ElevenLabsBrand.Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
.aspectRatio(4.0/5.0, contentMode: .fit)
```

---

## Do / Don't

**Do**
- Set page backgrounds to `Colors.paper`, never pure white.
- Wrap discrete content blocks in `ElevenLabsCard`.
- Layer `ElevenLabsCloverOverlay` on every custom gradient surface — it's part of the brand, not optional decoration.
- Use heavy weights for headlines, regular for body. Negative tracking on display sizes.
- Use the gradient stops only in the four named compositions (`sunset` / `skyBlush` / `ember` / `cool`).

**Don't**
- Mix `DS.Colors` (dark accent palette) and `ElevenLabsBrand.Colors` in the same view — pick one identity per surface.
- Use the wordmark as a UI heading or button label.
- Introduce new gradient hues outside the named stops.
- Add drop shadows beyond `Shadow.card(_:)` — the brand reads as flat printed paper, not floating UI.
- Use bright accent colors (the `DS.Colors.accent` blue) on ElevenLabs surfaces. Black-and-white is the default; gradients carry the color story.

---

## Migration Notes

The existing dark UI (`CompanionPanelView`, `OverlayWindow`, etc.) keeps using `DS.*` tokens. Migrate to ElevenLabs styling per-screen:

1. Pick one screen (e.g. a new chat window or the persona wheel).
2. Set its root background to `ElevenLabsBrand.Colors.paper`.
3. Replace `DS.Colors.surface*` fills with `ElevenLabsCard` containers.
4. Replace headline `Text` with `ElevenLabsBrand.Typography.*` fonts.
5. Replace primary CTAs with `.elevenLabsPrimaryButtonStyle()`.
6. Add a hero `ElevenLabsGradientTile` if the screen needs a feature surface.

The rest of the app continues to work unchanged. There's no global theme switch — the two systems are independent by design so you can roll the rebrand out screen by screen.
