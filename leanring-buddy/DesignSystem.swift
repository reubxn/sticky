//
//  DesignSystem.swift
//  leanring-buddy
//
//  Centralized design system using a blue accent palette on dark surfaces,
//  with a unified button style system. All colors, button styles, and
//  interaction states are defined here as the single source of truth.
//

import SwiftUI
import AppKit

// MARK: - Design System Namespace

/// The top-level namespace for all design system tokens.
/// Usage: `DS.Colors.background`, `DS.Colors.accent`, etc.
enum DS {

    // MARK: - Color Tokens

    enum Colors {

        // ── Backgrounds ──────────────────────────────────────────────
        // Layered surfaces from deepest to most elevated.
        // Higher surfaces are lighter, creating a sense of depth.

        /// The deepest background — used for the main app window fill.
        static let background = Color(hex: "#101211")

        /// First elevation layer — used for cards, sidebar, top bar backgrounds.
        static let surface1 = Color(hex: "#171918")

        /// Second elevation layer — used for input fields, elevated cards, chat bubbles.
        static let surface2 = Color(hex: "#202221")

        /// Third elevation layer — used for hover backgrounds on interactive elements.
        static let surface3 = Color(hex: "#272A29")

        /// Fourth elevation layer — used for active/pressed states on interactive elements.
        static let surface4 = Color(hex: "#2E3130")

        // ── Borders ──────────────────────────────────────────────────

        /// Subtle border — used for card outlines, dividers, input field borders.
        static let borderSubtle = Color(hex: "#373B39")

        /// Strong border — used for focused inputs, hovered card outlines.
        static let borderStrong = Color(hex: "#444947")

        // ── Text ─────────────────────────────────────────────────────

        /// Primary text — main body text, titles, headings.
        static let textPrimary = Color(hex: "#ECEEED")

        /// Secondary text — descriptions, hints, muted labels.
        static let textSecondary = Color(hex: "#ADB5B2")

        /// Tertiary text — very muted, used for section labels, timestamps, disabled text.
        static let textTertiary = Color(hex: "#6B736F")

        /// Text used on top of the accent fill (#2563eb blue), like the primary button label.
        /// White on #2563eb achieves ~5.1:1 contrast — WCAG AA compliant.
        /// White on #1d4ed8 hover achieves ~6.5:1 — also WCAG AA compliant.
        static let textOnAccent: Color = .white

        // ── Tailwind Blue Scale ─────────────────────────────────────
        // Full Tailwind CSS v4 blue palette for consistent blue usage.
        //
        // Usage guide:
        //   50–100  → Very subtle tinted backgrounds (selected rows, hover fills on dark surfaces)
        //   200–300 → Light text/icons on dark backgrounds, disabled states
        //   400     → Bright accent text, links, icons, chat user bubbles
        //   500     → Mid-tone fills, badges, secondary buttons
        //   600     → Primary action fills (buttons, toggles) — main accent
        //   700     → Hover/pressed state for primary actions
        //   800–900 → Deep backgrounds, dark overlays, header bars
        //   950     → Deepest blue — near-black tinted backgrounds

        static let blue50  = Color(hex: "#eff6ff")
        static let blue100 = Color(hex: "#dbeafe")
        static let blue200 = Color(hex: "#bfdbfe")
        static let blue300 = Color(hex: "#93c5fd")
        static let blue400 = Color(hex: "#60a5fa")
        static let blue500 = Color(hex: "#3b82f6")
        static let blue600 = Color(hex: "#2563eb")
        static let blue700 = Color(hex: "#1d4ed8")
        static let blue800 = Color(hex: "#1e40af")
        static let blue900 = Color(hex: "#1e3a8a")
        static let blue950 = Color(hex: "#172554")

        // ── Accent (derived from blue scale) ───────────────────────
        // The primary fill is Blue 600; hover darkens to Blue 700.

        /// Accent fill — used for solid button backgrounds.
        /// #2563eb → ~5.1:1 contrast with white text (WCAG AA).
        static let accent = blue600

        /// Accent hover — slightly darker blue for hover state.
        /// #1d4ed8 → ~6.5:1 contrast with white text (WCAG AA+).
        static let accentHover = blue700

        /// Accent text — bright blue used for accent-colored text and icons
        /// on dark backgrounds (links, active nav items, highlighted labels).
        static let accentText = blue400

        /// Very subtle accent tint — used for selected item backgrounds (e.g. current step
        /// in the sidebar). Low opacity so it doesn't overpower.
        static let accentSubtle = blue500.opacity(0.10)

        // ── Semantic Colors ──────────────────────────────────────────

        /// Destructive/error actions — delete buttons, error messages, close button hover.
        static let destructive = Color(hex: "#E5484D")        // Radix Red 9

        /// Destructive hover state.
        static let destructiveHover = Color(hex: "#F2555A")   // Radix Red 10

        /// Destructive used for text on dark backgrounds (brighter for readability).
        static let destructiveText = Color(hex: "#FF6369")    // Radix Red 11

        /// Success — checkmarks, granted status, completion indicators.
        /// Independent green so success states are visually distinct from the blue accent.
        static let success = Color(hex: "#34D399")      // Tailwind Emerald 400

        /// Warning — caution messages, manual verification failure explanations.
        static let warning = Color(hex: "#FFB224")            // Radix Amber 9

        /// Warning text — brighter variant for text on dark backgrounds.
        static let warningText = Color(hex: "#F1A10D")        // Radix Amber 11

        /// Info/feature highlight — used for prompt card headers, code highlights.
        /// Lighter than accentText so informational elements are visually distinct
        /// from interactive accent-colored elements.
        static let info = Color(hex: "#70B8FF")               // Radix Blue 9

        /// Inline code text color — slightly brighter blue for monospace code snippets.
        static let codeText = Color(hex: "#9DC2FF")           // Radix Blue 11 variant

        // ── Overlay Cursor ───────────────────────────────────────────

        /// The blue cursor/bubble color used in OverlayWindow.
        /// Kept distinct from the accent since it serves a different purpose
        /// (screen overlay vs in-app UI).
        static let overlayCursorBlue = Color(hex: "#3380FF")

        // ── Floating Button Gradient ─────────────────────────────────

        /// The floating session button gradient colors (unchanged from original —
        /// this gradient is intentionally distinct from the rest of the palette
        /// to make the floating button stand out as a "jewel" on the desktop).
        static let floatingGradientPurple = Color(hex: "#8F46EB")
        static let floatingGradientPink = Color(hex: "#E84D9E")
        static let floatingGradientOrange = Color(hex: "#FF8C33")

        // ── Help Chat ──────────────────────────────────────────────

        /// User message bubble background in the help chat.
        /// Blue 800 — deep blue that's clearly distinct from the dark surface
        /// while keeping white text highly readable (~9:1 contrast).
        static let helpChatUserBubble = blue800

        /// Slightly lighter variant for hover/pressed states on user bubbles.
        static let helpChatUserBubbleHover = blue700

        /// Footer/backdrop behind the floating help chat.
        /// Slightly lighter than the main window background so the chat zone reads
        /// as a distinct docked surface even before the pill input is visible.
        static let helpChatBackdrop = Color(hex: "#212121")

        // ── Disabled State ───────────────────────────────────────────
        // Following Material Design 3's disabled pattern:
        // Container: onSurface at 12% opacity
        // Content: onSurface at 38% opacity

        /// Disabled button/container background.
        static var disabledBackground: Color {
            textPrimary.opacity(0.12)
        }

        /// Disabled text/icon color.
        static var disabledText: Color {
            textPrimary.opacity(0.38)
        }
    }

    // MARK: - Spacing (for reference, not enforced)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radii

    enum CornerRadius {
        /// Small elements like tags, badges.
        static let small: CGFloat = 6
        /// Buttons, input fields, small cards.
        static let medium: CGFloat = 8
        /// Cards, dialogs, chat bubbles.
        static let large: CGFloat = 10
        /// Large panels, permission cards.
        static let extraLarge: CGFloat = 12
        /// Pill-shaped buttons (the continue button).
        static let pill: CGFloat = .infinity
    }

    // MARK: - Animation Durations

    enum Animation {
        /// Quick state changes — hover in/out, press feedback.
        static let fast: Double = 0.15
        /// Standard transitions — content reveal, button state changes.
        static let normal: Double = 0.25
        /// Slower, more dramatic — fade-ins, celebration screen elements.
        static let slow: Double = 0.4
    }

    // MARK: - State Layer Opacities
    // Based on Material Design 3's state layer system.
    // A "state layer" overlays the button's content color at these opacities.

    enum StateLayer {
        /// Hover: subtle highlight to indicate interactivity.
        static let hover: Double = 0.08
        /// Focus: keyboard navigation indicator (slightly stronger than hover).
        static let focus: Double = 0.12
        /// Pressed: active press feedback (same strength as focus).
        static let pressed: Double = 0.12
        /// Dragged: strongest overlay (rarely used).
        static let dragged: Double = 0.16
    }
}

// MARK: - Button Styles

/// Primary button — the main call-to-action per screen.
/// Accent-colored background with white text. One per view maximum.
/// Used for: "start"/"resume", "let's go", "continue", "verify completion".
struct DSPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true

    @State private var isHovered = false

    // Separate state for the scale expansion so it animates on a slower,
    // more gradual timeline (0.6s) than the background color snap (0.15s).
    @State private var isHoverScaleExpanded = false

    // Whether the hover glow shadow is active. Builds up gradually (0.6s)
    // on hover entry, fades out faster (0.3s) on exit.
    @State private var isHoverGlowActive = false

    // Continuously toggles while hovered to drive a gentle breathing pulse
    // in the glow shadow. Creates a living, organic feel — like the button
    // is softly glowing, not just statically lit.
    @State private var isGlowBreathingIn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(DS.Colors.textOnAccent)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, isFullWidth ? 0 : 20)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            // Hover glow — builds up gradually, then gently breathes while hovered.
            // The breathing oscillates opacity and radius on a slow 2.5s loop,
            // creating a candle-flame-like "alive" quality rather than a static highlight.
            .shadow(
                color: DS.Colors.accent.opacity(
                    isHoverGlowActive ? (isGlowBreathingIn ? 0.32 : 0.18) : 0
                ),
                radius: isHoverGlowActive ? (isGlowBreathingIn ? 16 : 10) : 0
            )
            // Hover: gradually expand to 1.03. Press: snap down to 0.97.
            .scaleEffect(configuration.isPressed ? 0.97 : (isHoverScaleExpanded ? 1.03 : 1.0))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                // Background color — fast snap so the button feels responsive
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }

                // Scale — slow, gradual expansion (like the button is swelling)
                withAnimation(.easeInOut(duration: hovering ? 0.6 : 0.3)) {
                    isHoverScaleExpanded = hovering
                }

                // Glow — builds up gradually on entry, fades faster on exit
                withAnimation(.easeInOut(duration: hovering ? 0.6 : 0.3)) {
                    isHoverGlowActive = hovering
                }

                // Breathing glow loop — gentle pulse while hovered.
                // The 2.5s cycle keeps it feeling organic, not mechanical.
                if hovering {
                    withAnimation(
                        .easeInOut(duration: 2.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        isGlowBreathingIn = true
                    }
                } else {
                    // Override the repeating animation with a finite one to stop cleanly
                    withAnimation(.easeOut(duration: 0.3)) {
                        isGlowBreathingIn = false
                    }
                }

                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            // Pressed: brighten slightly beyond hover
            return DS.Colors.accentHover.blendedWithWhite(fraction: DS.StateLayer.pressed)
        } else if isHovered {
            return DS.Colors.accentHover
        } else {
            return DS.Colors.accent
        }
    }
}

/// Secondary button — supporting actions, less visual weight than primary.
/// Surface-colored background with primary text. Used for: action buttons
/// (download, open link), embedded element buttons.
struct DSSecondaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(DS.Colors.textPrimary)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 12)
            .padding(.horizontal, isFullWidth ? 0 : 16)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Colors.surface4
        } else if isHovered {
            return DS.Colors.surface3
        } else {
            return DS.Colors.surface2
        }
    }
}

/// Tertiary/ghost button — low-emphasis actions with subtle hover background.
/// Transparent at rest, shows surface fill on hover. Used for: navigation
/// links, sidebar items, medium-low emphasis actions.
struct DSTertiaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(
                configuration.isPressed
                    ? DS.Colors.accentHover
                    : isHovered
                        ? DS.Colors.accentText
                        : DS.Colors.textSecondary
            )
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Colors.surface3
        } else if isHovered {
            return DS.Colors.surface2
        } else {
            return Color.clear
        }
    }
}

/// Text button — the lowest-emphasis button style. No background on any
/// state, not even hover. Only the text color changes. Used for: "restart",
/// "skip", "cancel", and other truly minimal inline actions where a
/// background would add too much visual weight.
struct DSTextButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 14

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(
                configuration.isPressed
                    ? DS.Colors.textPrimary
                    : isHovered
                        ? DS.Colors.textPrimary
                        : DS.Colors.textTertiary
            )
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

/// Outlined button — medium emphasis, used where a border helps define
/// the button's bounds. Used for: display selector, copy prompt.
struct DSOutlinedButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(DS.Colors.textPrimary)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 12)
            .padding(.horizontal, isFullWidth ? 0 : 16)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                Capsule()
                    .stroke(
                        borderColor(isPressed: configuration.isPressed),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Colors.surface3
        } else if isHovered {
            return DS.Colors.surface2
        } else {
            return DS.Colors.surface1
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed || isHovered {
            return DS.Colors.borderStrong
        } else {
            return DS.Colors.borderSubtle
        }
    }
}

/// Destructive button — for dangerous/irreversible actions (close session, delete).
/// Red-tinted background that intensifies on hover and press.
struct DSDestructiveButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(
                isHovered || configuration.isPressed
                    ? .white
                    : DS.Colors.destructiveText
            )
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                Capsule()
                    .stroke(
                        borderColor(isPressed: configuration.isPressed),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Colors.destructive.opacity(0.40)
        } else if isHovered {
            return DS.Colors.destructive.opacity(0.30)
        } else {
            return DS.Colors.destructive.opacity(0.10)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed || isHovered {
            return DS.Colors.destructive.opacity(0.40)
        } else {
            return DS.Colors.destructive.opacity(0.15)
        }
    }
}

/// Icon-only button — compact circular button for utility actions.
/// Used for: close button (x), send message, small toolbar actions.
struct DSIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var isDestructiveOnHover: Bool = false
    var tooltipText: String? = nil

    /// Controls horizontal alignment of the tooltip relative to the button.
    /// Use `.leading` for buttons near the left edge of the window (tooltip extends right),
    /// `.trailing` for buttons near the right edge (tooltip extends left),
    /// and `.center` for buttons in the middle.
    var tooltipAlignment: Alignment = .center

    @State private var isHovered = false
    @State private var isTooltipVisible = false
    @State private var tooltipShowWorkItem: DispatchWorkItem? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundColor(iconColor(isPressed: configuration.isPressed))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(circleBackgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                Circle()
                    .stroke(circleBorderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .contentShape(Circle())
            // Cursor change via AppKit cursor rects — more reliable than NSCursor.push/pop
            // because cursor rects are managed at the window level and don't conflict
            // with SwiftUI's internal cursor handling.
            .overlay(PointerCursorView())
            .onHover { hovering in
                isHovered = hovering
                // Show the tooltip after a delay (like native tooltips), hide immediately
                tooltipShowWorkItem?.cancel()
                if hovering {
                    let workItem = DispatchWorkItem {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isTooltipVisible = true
                        }
                    }
                    tooltipShowWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
                } else {
                    withAnimation(.easeOut(duration: 0.1)) {
                        isTooltipVisible = false
                    }
                }
            }
            // Custom styled tooltip — positioned above the button with enough gap
            // to not overlap the button. Horizontally aligned based on tooltipAlignment
            // so tooltips near window edges don't clip outside the visible area.
            // Uses .allowsHitTesting(false) so the tooltip doesn't interfere
            // with the button's hover state.
            .overlay(
                Group {
                    if isTooltipVisible, let text = tooltipText, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DS.Colors.surface3.opacity(0.85))
                            )
                            .overlay(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)

                                    RoundedRectangle(cornerRadius: 6)
                                        .trim(from: 0, to: 0.5)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.10),
                                                    Color.white.opacity(0.02)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 0.8
                                        )
                                }
                            )
                            .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 8)
                            .shadow(color: Color.black.opacity(0.26), radius: 4, x: 0, y: 2)
                            .fixedSize()
                            .offset(y: -(size / 2 + 20))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                },
                alignment: tooltipAlignment
            )
    }

    private func iconColor(isPressed: Bool) -> Color {
        if isDestructiveOnHover && (isHovered || isPressed) {
            return .white
        }
        if isPressed {
            return DS.Colors.textPrimary
        } else if isHovered {
            return DS.Colors.textPrimary
        } else {
            return DS.Colors.textSecondary
        }
    }

    private func circleBackgroundColor(isPressed: Bool) -> Color {
        if isDestructiveOnHover {
            if isPressed {
                return DS.Colors.destructive.opacity(0.40)
            } else if isHovered {
                return DS.Colors.destructive.opacity(0.30)
            } else {
                return DS.Colors.surface2
            }
        }
        if isPressed {
            return DS.Colors.surface4
        } else if isHovered {
            return DS.Colors.surface3
        } else {
            return DS.Colors.surface2
        }
    }

    private func circleBorderColor(isPressed: Bool) -> Color {
        if isDestructiveOnHover && (isHovered || isPressed) {
            return DS.Colors.destructive.opacity(0.30)
        }
        if isPressed || isHovered {
            return DS.Colors.borderStrong
        } else {
            return DS.Colors.borderSubtle.opacity(0.5)
        }
    }
}

// MARK: - Convenience View Extensions

extension View {
    /// Applies the primary button style (accent-colored CTA).
    func dsPrimaryButtonStyle(isFullWidth: Bool = true) -> some View {
        self.buttonStyle(DSPrimaryButtonStyle(isFullWidth: isFullWidth))
    }

    /// Applies the secondary button style (surface-colored supporting action).
    func dsSecondaryButtonStyle(isFullWidth: Bool = true) -> some View {
        self.buttonStyle(DSSecondaryButtonStyle(isFullWidth: isFullWidth))
    }

    /// Applies the tertiary/ghost button style (subtle hover background).
    func dsTertiaryButtonStyle() -> some View {
        self.buttonStyle(DSTertiaryButtonStyle())
    }

    /// Applies the text-only button style (no background ever, just color change).
    func dsTextButtonStyle(fontSize: CGFloat = 14) -> some View {
        self.buttonStyle(DSTextButtonStyle(fontSize: fontSize))
    }

    /// Applies the outlined button style (bordered, medium emphasis).
    func dsOutlinedButtonStyle(isFullWidth: Bool = true) -> some View {
        self.buttonStyle(DSOutlinedButtonStyle(isFullWidth: isFullWidth))
    }

    /// Applies the destructive button style (red-tinted danger action).
    func dsDestructiveButtonStyle() -> some View {
        self.buttonStyle(DSDestructiveButtonStyle())
    }

    /// Applies the icon-only button style (compact circle).
    /// `tooltipAlignment` controls where the tooltip sits horizontally relative to the button:
    /// `.leading` for left-edge buttons, `.trailing` for right-edge buttons, `.center` for middle.
    func dsIconButtonStyle(size: CGFloat = 28, isDestructiveOnHover: Bool = false, tooltip: String? = nil, tooltipAlignment: Alignment = .center) -> some View {
        self.buttonStyle(DSIconButtonStyle(size: size, isDestructiveOnHover: isDestructiveOnHover, tooltipText: tooltip, tooltipAlignment: tooltipAlignment))
    }

    /// Attaches the shared pointing-hand cursor treatment used across interactive controls.
    /// Disabled controls can opt out so they keep the default arrow cursor.
    func pointerCursor(isEnabled: Bool = true) -> some View {
        self.overlay {
            if isEnabled {
                PointerCursorView()
            }
        }
    }
}

// MARK: - ElevenLabs Brand Styling
//
// A parallel branding token set inspired by ElevenLabs' visual identity:
//   - Cream/paper light background with near-black foreground
//   - Bold, tight, sans-serif typography
//   - Hard-edged cards with hairline borders and generous whitespace
//   - Saturated gradient meshes (sunset, sky, ember) as feature surfaces
//   - Topographic / clover line motifs overlaid on gradients
//
// Use these tokens for surfaces that should adopt the ElevenLabs look
// (marketing-style cards, hero panels, gradient feature tiles). Existing
// dark UI continues to use the `DS.Colors` palette above; the two systems
// coexist so screens can be migrated independently.

enum ElevenLabsBrand {

    // MARK: - Surfaces & Ink

    enum Colors {
        // Surface + ink tokens are dynamic: they resolve to the warm
        // off-white "paper" palette in light appearance and to a
        // matching warm-dark palette in dark appearance. The same hex
        // values that defined the original light theme stay the
        // light-side of every pair, so nothing visual changes when the
        // app is in light mode.

        /// Paper background — the warm off-white used in ElevenLabs landing
        /// pages and OOH (bus stop, billboard frames). Slightly warmer than
        /// pure white so it reads as printed paper, not a screen. Dark
        /// variant is a warm earthy near-black so the same "warm,
        /// editorial" mood carries over.
        static let paper = Color.appearanceAware(
            lightHex: "#F4F2ED",
            darkHex: "#1B1814"
        )

        /// Pure white card surface — sits on top of `paper` with a hairline
        /// border for the marketing-card look (the audiobook hero card,
        /// the chat preview tile, the voice cards). Dark variant is a
        /// slightly elevated warm-dark surface, mirroring how `card`
        /// sits one step above `paper` in light mode.
        static let card = Color.appearanceAware(
            lightHex: "#FFFFFF",
            darkHex: "#242120"
        )

        /// Subtle paper variation — used for alternating sections or
        /// secondary surfaces that should feel one step recessed from `card`.
        /// Dark variant goes the other direction (deeper than `paper`) so
        /// the same recessed/elevated relationship holds.
        static let paperRecessed = Color.appearanceAware(
            lightHex: "#ECEAE4",
            darkHex: "#13110F"
        )

        /// Near-black ink — the headline + body color. Slightly warm so it
        /// pairs with the paper background instead of feeling clinical.
        /// Flips to a warm off-white in dark mode (matching the light-mode
        /// paper hex, which keeps text and surface color-related so the
        /// whole UI reads as the same warm material in either theme).
        static let ink = Color.appearanceAware(
            lightHex: "#0B0B0B",
            darkHex: "#F4F2ED"
        )

        /// Pure black — used for the wordmark, poster headlines, and the
        /// dark-mode hero surface ("The most realistic voice AI platform").
        /// In dark mode it becomes a near-pure white so the wordmark
        /// stays the punchiest contrast on the surface.
        static let inkPure = Color.appearanceAware(
            lightHex: "#000000",
            darkHex: "#FAFAFA"
        )

        /// Secondary ink — body copy, supporting labels (the small product
        /// description text under "Audiobooks" / "Video Voiceovers").
        static let inkSecondary = Color.appearanceAware(
            lightHex: "#3D3D3B",
            darkHex: "#B0AEA8"
        )

        /// Tertiary ink — captions, metadata ("14m", "2.1k" pills under
        /// voice cards), section eyebrows ("For Creators, Media...").
        static let inkTertiary = Color.appearanceAware(
            lightHex: "#7A7A77",
            darkHex: "#7E7B76"
        )

        /// Hairline border — the thin 1px outlines on cards and the dotted
        /// grid frames inside gradient tiles. Very low contrast so cards
        /// look like printed cuts on paper rather than UI panels.
        static let hairline = Color.appearanceAware(
            lightHex: "#DEDBD3",
            darkHex: "#2D2A26"
        )

        /// A stronger hairline used for hover/focus on the otherwise
        /// almost-invisible default border.
        static let hairlineStrong = Color.appearanceAware(
            lightHex: "#B9B5AB",
            darkHex: "#45413B"
        )

        /// White overlay text — used on top of saturated gradient surfaces
        /// (the bus-stop poster, the dark hero, the wordmark on the OOH
        /// billboard). Always white because the gradient surfaces it
        /// sits on don't change with the app theme.
        static let onAccent = Color.white

        // MARK: - Gradient Mesh Stops
        //
        // ElevenLabs uses a recurring set of mesh-gradient stops that
        // appear across web, OOH, social, and event collateral. We expose
        // them as named stops so individual gradients can recombine them.

        /// Soft sky blue — the upper-left of the bus-stop poster and the
        /// "british narration" voice tile.
        static let gradientSky = Color(hex: "#A6C3F2")

        /// Cool periwinkle — the deeper blue used in the voice card mesh
        /// gradients ("Engaging characters for video games").
        static let gradientPeriwinkle = Color(hex: "#7C8BD9")

        /// Blush pink — the soft pink that appears in the audiobook hero
        /// card and the voice cards.
        static let gradientBlush = Color(hex: "#F5C8D1")

        /// Hot coral — the warm red-orange that defines the Summit 25
        /// posters and the lanyard speaker badge.
        static let gradientCoral = Color(hex: "#E8593A")

        /// Sunset orange — the "Bring your stories to life" tile and the
        /// audiobook card warm corner.
        static let gradientSunset = Color(hex: "#F1A06A")

        /// Goldenrod — sits between sunset and blush, used to make the
        /// warm gradients feel multi-stop rather than flat.
        static let gradientGoldenrod = Color(hex: "#F2D08A")

        /// Lavender — the cooler edge of the chat-preview gradient and
        /// some social tiles.
        static let gradientLavender = Color(hex: "#C9B6E8")

        /// Taste accent — the amber-orange used by Reverse Clicky's
        /// teach-mode edge glow and any panel/dashboard surface that
        /// signals taste-capture (Start Teach Session dot, Active pill
        /// while voice is engaged, permission-warning icons, the
        /// selection bar in the dashboard sidebar). Picked to match the
        /// edge glow at OverlayWindow.swift's `.teachRecording` mode so
        /// the same hue carries across surfaces.
        static let tasteAccent = Color(hex: "#FFA94D")

        // MARK: - Dark Hero
        //
        // For the "most realistic voice AI platform" trade-show wall and
        // any inverted hero surfaces that flip ink → paper.

        static let darkHero = Color(hex: "#0A0A0A")
        static let darkHeroInk = Color(hex: "#F4F2ED")
        static let darkHeroHairline = Color.white.opacity(0.10)
    }

    // MARK: - Typography
    //
    // ElevenLabs uses a tightly tracked geometric sans (close to Inter
    // Display / NeueHaasGrotesk). On macOS we map to SF Pro with weights
    // and tracking that approximate the brand's dense, confident voice.

    enum Typography {
        /// Display — the giant poster headline ("ElevenLabs Summit 25",
        /// "The most realistic voice AI platform").
        static func display(size: CGFloat = 56) -> Font {
            .system(size: size, weight: .bold, design: .default)
        }

        /// Hero headline — landing-page-scale title, tighter and slightly
        /// lighter than display ("Generate high-quality AI audio...").
        static func hero(size: CGFloat = 36) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        /// Card title — the headline inside a feature card ("Epic voices
        /// for british narration", "Bring your stories to life").
        static func cardTitle(size: CGFloat = 22) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        /// Eyebrow — the small all-caps / sentence-case category label
        /// above a hero ("For Creators, Media & Entertainment",
        /// "Collections", "Top picks").
        static let eyebrow = Font.system(size: 11, weight: .medium, design: .default)

        /// Body — running paragraph text inside cards and product
        /// descriptions.
        static let body = Font.system(size: 14, weight: .regular, design: .default)

        /// Body emphasis — used for the small bold product names
        /// ("Audiobooks", "Video Voiceovers", "Podcasts").
        static let bodyStrong = Font.system(size: 14, weight: .semibold, design: .default)

        /// Caption — metadata pills ("14m", "2.1k"), timestamps,
        /// fine-print legal.
        static let caption = Font.system(size: 11, weight: .medium, design: .default)
    }

    // MARK: - Shape

    enum Radius {
        /// Pills and metadata chips — almost-circle.
        static let pill: CGFloat = 999
        /// Card corner — the audiobook hero card, voice cards, billboard
        /// frame. Subtle but present, so cards still read as "printed".
        static let card: CGFloat = 14
        /// Tight corner for inner elements (the chat bubbles inside the
        /// preview card).
        static let chip: CGFloat = 10
        /// Hard / near-zero — used by some posters where corners are
        /// effectively right-angle.
        static let crisp: CGFloat = 2
    }

    // MARK: - Spacing
    //
    // ElevenLabs marketing uses generous whitespace — closer to print
    // editorial than typical product UI. These steps are intentionally
    // larger than `DS.Spacing` so card padding feels airy.

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 72
    }

    // MARK: - Gradient Presets
    //
    // The four meshes that recur across ElevenLabs' brand surfaces.
    // Implemented as `LinearGradient`s with multiple stops; for a fuller
    // mesh look, layer the topographic overlay (`Overlays.cloverGrid`) on
    // top.

    enum Gradients {
        /// Sunset mesh — coral → sunset → goldenrod → blush. The Summit 25
        /// poster, the lanyard speaker badge.
        static let sunset = LinearGradient(
            stops: [
                .init(color: Colors.gradientCoral, location: 0.0),
                .init(color: Colors.gradientSunset, location: 0.45),
                .init(color: Colors.gradientGoldenrod, location: 0.75),
                .init(color: Colors.gradientBlush, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Sky-to-blush mesh — the bus-stop poster gradient (cool top-right
        /// fading to warm bottom-left).
        static let skyBlush = LinearGradient(
            stops: [
                .init(color: Colors.gradientSky, location: 0.0),
                .init(color: Colors.gradientLavender, location: 0.5),
                .init(color: Colors.gradientBlush, location: 0.85),
                .init(color: Colors.gradientSunset, location: 1.0)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )

        /// Ember mesh — saturated red-orange used as the warm corner of
        /// voice cards ("british narration").
        static let ember = LinearGradient(
            stops: [
                .init(color: Colors.gradientCoral, location: 0.0),
                .init(color: Colors.gradientSunset, location: 0.6),
                .init(color: Colors.gradientGoldenrod, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Cool mesh — the periwinkle/sky/blush mix used in "video games"
        /// and "stories to life" voice tiles.
        static let cool = LinearGradient(
            stops: [
                .init(color: Colors.gradientPeriwinkle, location: 0.0),
                .init(color: Colors.gradientSky, location: 0.4),
                .init(color: Colors.gradientLavender, location: 0.75),
                .init(color: Colors.gradientBlush, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Shadow

    enum Shadow {
        /// The soft drop shadow on white cards floating over paper.
        /// Subtle — under 6px blur — so cards read as printed pieces.
        static func card<V: View>(_ view: V) -> some View {
            view.shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - ElevenLabs Card Container
//
// The signature "white card on paper" frame. Hairline border, subtle
// shadow, large internal padding. Use this as the chrome for any
// content that should feel like an editorial card on the brand site.

struct ElevenLabsCard<Content: View>: View {
    var padding: CGFloat = ElevenLabsBrand.Spacing.lg
    var radius: CGFloat = ElevenLabsBrand.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        ElevenLabsBrand.Shadow.card(
            content()
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(ElevenLabsBrand.Colors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Topographic Clover Overlay
//
// The recurring line motif overlaid on every gradient surface — clover
// shapes inside a 3x3 grid with crosshairs at the cell intersections.
// Drawn procedurally at low opacity so it can layer on any gradient.

struct ElevenLabsCloverOverlay: View {
    var lineColor: Color = Color.white.opacity(0.55)
    var gridDivisions: Int = 3

    var body: some View {
        GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(gridDivisions)
            let cellHeight = geo.size.height / CGFloat(gridDivisions)

            ZStack {
                // Grid lines — crosshair frame dividing the surface into
                // a 3x3 layout (matches the dotted grid on ElevenLabs
                // gradient cards).
                Path { path in
                    for column in 1..<gridDivisions {
                        let xPosition = CGFloat(column) * cellWidth
                        path.move(to: CGPoint(x: xPosition, y: 0))
                        path.addLine(to: CGPoint(x: xPosition, y: geo.size.height))
                    }
                    for row in 1..<gridDivisions {
                        let yPosition = CGFloat(row) * cellHeight
                        path.move(to: CGPoint(x: 0, y: yPosition))
                        path.addLine(to: CGPoint(x: geo.size.width, y: yPosition))
                    }
                }
                .stroke(lineColor.opacity(0.4), lineWidth: 0.6)

                // Clover shapes — one inside each grid cell. Built from
                // four overlapping circles arranged in a quatrefoil so the
                // outline traces the petal-like silhouette ElevenLabs uses
                // on its OOH and voice tiles.
                ForEach(0..<gridDivisions, id: \.self) { row in
                    ForEach(0..<gridDivisions, id: \.self) { column in
                        let centerX = (CGFloat(column) + 0.5) * cellWidth
                        let centerY = (CGFloat(row) + 0.5) * cellHeight
                        let petalRadius = min(cellWidth, cellHeight) * 0.22

                        ZStack {
                            ForEach(0..<4, id: \.self) { petalIndex in
                                let angleRadians = Double(petalIndex) * .pi / 2
                                let offsetX = CGFloat(cos(angleRadians)) * petalRadius
                                let offsetY = CGFloat(sin(angleRadians)) * petalRadius
                                Circle()
                                    .stroke(lineColor, lineWidth: 0.7)
                                    .frame(width: petalRadius * 2, height: petalRadius * 2)
                                    .position(x: centerX + offsetX, y: centerY + offsetY)
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - ElevenLabs Gradient Tile
//
// The signature voice-card / poster tile: a saturated gradient with the
// clover-grid overlay and (optionally) a centered wordmark or label.
// Use for hero tiles, feature surfaces, or large empty-state art.

struct ElevenLabsGradientTile<Label: View>: View {
    var gradient: LinearGradient
    var radius: CGFloat = ElevenLabsBrand.Radius.card
    var showsOverlay: Bool = true
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(gradient)

            if showsOverlay {
                ElevenLabsCloverOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }

            label()
        }
    }
}

extension ElevenLabsGradientTile where Label == EmptyView {
    init(gradient: LinearGradient,
         radius: CGFloat = ElevenLabsBrand.Radius.card,
         showsOverlay: Bool = true) {
        self.init(gradient: gradient, radius: radius, showsOverlay: showsOverlay) {
            EmptyView()
        }
    }
}

// MARK: - ElevenLabs Eyebrow Label

struct ElevenLabsEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(ElevenLabsBrand.Typography.eyebrow)
            .tracking(0.2)
            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
    }
}

// MARK: - ElevenLabs Primary Button
//
// Pill-shaped, pure-black fill with white label — the "Try a call"
// button on the voice cards. Inverts to white-on-black on hover.

struct ElevenLabsPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(
                isHovered ? ElevenLabsBrand.Colors.inkPure : ElevenLabsBrand.Colors.paper
            )
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, 10)
            .padding(.horizontal, isFullWidth ? 0 : 18)
            .background(
                Capsule()
                    .fill(isHovered ? ElevenLabsBrand.Colors.paper : ElevenLabsBrand.Colors.inkPure)
            )
            .overlay(
                Capsule()
                    .stroke(ElevenLabsBrand.Colors.inkPure, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: DS.Animation.fast), value: configuration.isPressed)
            .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension View {
    /// Applies the ElevenLabs-style pill button (black fill, white label,
    /// inverts on hover). Use for primary CTAs on light brand surfaces.
    func elevenLabsPrimaryButtonStyle(isFullWidth: Bool = true) -> some View {
        self.buttonStyle(ElevenLabsPrimaryButtonStyle(isFullWidth: isFullWidth))
    }
}

// MARK: - Interactive Press Style
//
// A lightweight ButtonStyle that adds a satisfying "press" micro-animation
// to any button without changing its visual chrome. Scales the label down
// on press and snaps back via a spring on release. Use this for chip-style
// controls (segmented pills, dropdown triggers) where the surrounding
// visuals don't need a full button treatment but should still respond
// tactilely to clicks.

struct InteractivePressStyle: ButtonStyle {
    /// How far down to scale the label while pressed. 0.94 is gentle —
    /// noticeable but not theatrical. Use a smaller number (0.88-0.92)
    /// for big buttons that should feel weighty.
    var pressScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : 1.0)
            // Spring response on release gives a little playful overshoot;
            // the press itself uses a faster ease-out so the down-state
            // feels immediate, not laggy.
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.32, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}

// MARK: - Buddy Composer Visual Style

enum BuddyComposerVisualStyle {
    static let waveformLeadingColor = Color(hex: "#F3FBFF")
    static let waveformTrailingColor = Color(hex: "#8FD2FF")
    static let waveformGlowColor = Color(hex: "#AEE3FF")
}

// MARK: - Pointer Cursor (AppKit Bridge)

/// Uses AppKit's cursor rect system to reliably show a pointing hand cursor.
/// More reliable than NSCursor.push()/pop() inside SwiftUI's .onHover because
/// cursor rects are managed at the window level and don't conflict with
/// SwiftUI's internal cursor handling.
private class PointerCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private struct PointerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return PointerCursorNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Invalidate cursor rects when the view updates (e.g., resizes)
        // so AppKit recalculates the cursor area.
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

// MARK: - I-Beam Cursor (AppKit Bridge)

/// Uses AppKit's cursor rect system to reliably show an I-beam (text selection) cursor.
/// Same approach as PointerCursorView — cursor rects are managed at the window level
/// and don't conflict with SwiftUI's internal cursor handling.
/// Unlike NSCursor.push()/pop() in .onHover, this avoids cursor stack imbalance
/// when the mouse moves quickly between views.
private class IBeamCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    /// Pass through all mouse events so the TextField underneath still receives
    /// focus, clicks, and text selection. Cursor rects are registered with the
    /// window (via resetCursorRects) and work independently of hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

struct IBeamCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return IBeamCursorNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Invalidate cursor rects when the view updates (e.g., resizes)
        // so AppKit recalculates the cursor area.
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

// MARK: - Native Tooltip

/// Uses AppKit's `NSView.toolTip` to show a tooltip on hover.
/// SwiftUI's `.help()` conflicts with `.onHover` tracking areas, so
/// this bridges directly to AppKit's tooltip system which works independently.
private class NativeTooltipNSView: NSView {
    /// Tooltip overlays sit on top of Buttons in `.overlay(...)`. NSView's
    /// default hitTest returns self, which swallows the click before the
    /// underlying SwiftUI Button can receive it. Returning nil makes this
    /// view click-through (same pattern as PointerCursorNSView).
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private struct NativeTooltipView: NSViewRepresentable {
    let tooltip: String

    func makeNSView(context: Context) -> NSView {
        let view = NativeTooltipNSView()
        view.toolTip = tooltip
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = tooltip
    }
}

extension View {
    /// Attaches a native macOS tooltip that works even alongside `.onHover`.
    func nativeTooltip(_ text: String?) -> some View {
        if let text = text, !text.isEmpty {
            return AnyView(self.overlay(NativeTooltipView(tooltip: text)))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - Color Utilities

extension Color {
    /// Builds a SwiftUI `Color` that resolves to a different hex value in
    /// light vs. dark appearance. Backed by `NSColor(name:dynamicProvider:)`
    /// so the resolved color updates automatically whenever a hosting
    /// view's `effectiveAppearance` changes (which happens when we set
    /// `NSApp.appearance` from the ThemeManager, or when the user flips
    /// macOS appearance in System Settings while we're in `.system` mode).
    static func appearanceAware(lightHex: String, darkHex: String) -> Color {
        let lightNSColor = NSColor.fromHex(lightHex)
        let darkNSColor = NSColor.fromHex(darkHex)

        let dynamicNSColor = NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return darkNSColor
            default:
                return lightNSColor
            }
        }

        return Color(nsColor: dynamicNSColor)
    }

    /// Create a Color from a hex string like "#FF5733" or "FF5733".
    init(hex: String) {
        let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }

    /// Resolves this Color in the currently-active drawing appearance and
    /// returns the underlying `NSColor`. Use this when you need to hand
    /// off to AppKit APIs (CALayer borderColor, CAGradientLayer colors,
    /// NSWindow backgroundColor) that take a concrete CGColor / NSColor
    /// rather than a SwiftUI Color. Pair with
    /// `viewDidChangeEffectiveAppearance` so the layer is repainted
    /// whenever the appearance flips.
    func resolvedNSColor() -> NSColor {
        return NSColor(self)
    }

    /// Returns a lighter version of this color by blending toward white.
    /// `fraction` is 0.0 (no change) to 1.0 (pure white).
    func blendedWithWhite(fraction: Double) -> Color {
        // Convert to NSColor to access RGB components for blending
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return self }

        let red = nsColor.redComponent + (1.0 - nsColor.redComponent) * fraction
        let green = nsColor.greenComponent + (1.0 - nsColor.greenComponent) * fraction
        let blue = nsColor.blueComponent + (1.0 - nsColor.blueComponent) * fraction

        return Color(red: red, green: green, blue: blue)
    }
}

extension NSColor {
    /// Mirror of `Color(hex:)` for AppKit — used by `Color.appearanceAware`
    /// to build the underlying dynamic NSColor without a SwiftUI ↔ AppKit
    /// round trip on every resolution.
    static func fromHex(_ hex: String) -> NSColor {
        let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0

        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
