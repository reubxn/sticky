//
//  CompanionPanelView.swift
//  leanring-buddy
//
//  Editorial-style menu bar panel using the ElevenLabs brand system.
//  Paper background, white cards on paper, black-pill primary CTA, and
//  a hero header that pairs the wordmark with a colored status pill.
//
//  The panel re-uses Clicky's existing AppKit chrome (NSPanel +
//  WarmDropdownBackgroundView) — the background view paints a flat
//  paper surface with a hairline border, and this SwiftUI content sits
//  on top of it.
//

import AVFoundation
import SwiftUI

// MARK: - Legacy Warm Palette Shim
//
// Older components (TeachSessionResultCard, etc.) still reference
// `WarmPalette.*` tokens from the panel's previous warm-rust design.
// Rather than rewrite each of those views in the same pass, we remap
// every old token onto the ElevenLabs brand palette so the visual
// language stays consistent across the panel.
//
// Future cleanup: replace direct WarmPalette references in those files
// with ElevenLabsBrand.* tokens and delete this shim.
enum WarmPalette {
    static let textPrimary    = ElevenLabsBrand.Colors.ink
    static let textSecondary  = ElevenLabsBrand.Colors.inkSecondary
    static let textTertiary   = ElevenLabsBrand.Colors.inkTertiary
    static let accent         = ElevenLabsBrand.Colors.inkPure
    static let surfaceTint    = ElevenLabsBrand.Colors.paperRecessed
    static let surfaceTintStrong = ElevenLabsBrand.Colors.card
    static let separator      = ElevenLabsBrand.Colors.hairline
    static let statusGood     = ElevenLabsBrand.Colors.ink
    static let warning        = ElevenLabsBrand.Colors.gradientCoral
}

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    @ObservedObject private var authenticationManager = AuthenticationManager.shared

    /// Drives the custom persona-picker popover. Replaces the native
    /// `Menu` so we can render avatars, role subtitles, and a sectioned
    /// layout that matches the rest of the panel.
    @State private var isPersonaPickerPresented: Bool = false

    /// Tracks hover over the persona picker's whole paper card so the
    /// surface can subtly lift to advertise that the row is clickable.
    @State private var isHoveringPersonaCard: Bool = false

    /// Hover state for the small footer affordances (Quit, Sign in chip,
    /// model menu). Each gets its own boolean so they animate
    /// independently as the cursor moves between them.
    @State private var isHoveringQuitButton: Bool = false
    @State private var isHoveringSignedInChip: Bool = false

    /// Hover state for the Sticky wordmark in the header. Tapping the
    /// wordmark opens the full dashboard window, so on hover the
    /// trailing arrow nudges to telegraph that the brand is clickable.
    @State private var isHoveringOpenAppRow: Bool = false

    /// Drives the small theme-picker popover anchored on the footer.
    /// Anchored to a footer icon so the panel stays compact: the icon
    /// telegraphs the active mode, tapping opens a 3-row picker.
    @State private var isThemePickerPresented: Bool = false

    /// Tracks hover over the footer's theme button so it gets the same
    /// gentle highlight the Quit power button uses.
    @State private var isHoveringThemeButton: Bool = false

    /// Drives the popover that lets the user pick the hue of their voice
    /// color (the bottom-edge glow shown while holding ctrl+option).
    /// Anchored to a footer icon so it sits next to the theme picker.
    @State private var isVoiceColorPickerPresented: Bool = false

    /// Hover state for the footer's voice-color button — same gentle
    /// highlight pattern as the theme + quit buttons.
    @State private var isHoveringVoiceColorButton: Bool = false

    /// Live observer of the global ThemeManager. Drives the icon shown
    /// on the footer button (sun / moon / split-circle) so the user can
    /// see the active mode without opening the popover.
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if authenticationManager.canAccessProductionFeatures {
                heroHeader

                if !companionManager.allPermissionsGranted {
                    permissionsContent
                } else if !companionManager.hasCompletedOnboarding {
                    onboardingContent
                } else {
                    mainContent
                }
            } else {
                authenticationHeader
                authenticationBoundaryContent
            }

            footerSection
        }
        .frame(width: 380)
        .background(panelBackground)
        // Smoothly animate top-level state transitions — the panel
        // re-flowing between permissions / onboarding / main content
        // and the four-card settings grid resizing as selections change.
        .animation(.easeInOut(duration: 0.22), value: companionManager.allPermissionsGranted)
        .animation(.easeInOut(duration: 0.22), value: companionManager.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.22), value: companionManager.teachSessionState)
        .animation(.easeInOut(duration: 0.22), value: authenticationManager.authenticationState)
    }

    // MARK: - Hero Header
    //
    // App wordmark on the left. The wordmark is a custom "Sticky" mark —
    // a small filled pause-bars glyph paired with the app name in tight,
    // ink-weight type.

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                stickyAppWordmark

                Spacer()

                headerPersonaPicker
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.top, ElevenLabsBrand.Spacing.md)
            .padding(.bottom, ElevenLabsBrand.Spacing.sm)

            Rectangle()
                .fill(ElevenLabsBrand.Colors.hairline)
                .frame(height: 1)
        }
    }

    private var authenticationHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                stickyAppWordmark
                Spacer()
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.top, ElevenLabsBrand.Spacing.md)
            .padding(.bottom, ElevenLabsBrand.Spacing.sm)

            Rectangle()
                .fill(ElevenLabsBrand.Colors.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var authenticationBoundaryContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            switch authenticationManager.authenticationState {
            case .loading:
                authenticationProgressContent(
                    title: "Checking your session…",
                    message: "Sticky will be ready after Convex verifies your Clerk session."
                )
            case .signingOut:
                authenticationProgressContent(
                    title: "Signing out…",
                    message: "Protected features stay locked while access is revoked."
                )
            case .signedOut:
                authenticationActionContent(
                    title: "Sign in to use Sticky.",
                    message: "Continue with Google or a secure email link.",
                    errorMessage: nil
                )
            case .configurationMissing(let message),
                 .signOutFailure(let message),
                 .failure(let message):
                authenticationActionContent(
                    title: "Authentication needs attention.",
                    message: "Ask, Teach, personas, and chat remain locked.",
                    errorMessage: message
                )
            case .authenticated:
                authenticatedAccountConnectedContent
            }
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
    }

    private func authenticationProgressContent(
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.xs) {
                Text(title)
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 18))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(message)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func authenticationActionContent(
        title: String,
        message: String,
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            Text(title)
                .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text(message)
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .padding(ElevenLabsBrand.Spacing.sm)
                    .background(
                        RoundedRectangle(
                            cornerRadius: ElevenLabsBrand.Radius.card,
                            style: .continuous
                        )
                        .fill(ElevenLabsBrand.Colors.paperRecessed)
                    )
            }

            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                if errorMessage != nil {
                    Button("Retry") {
                        authenticationManager.retry()
                    }
                    .buttonStyle(InteractivePressStyle(pressScale: 0.98))
                    .pointerCursor()
                }

                Button("Open sign in") {
                    MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                .pointerCursor()
            }
        }
    }

    private var authenticatedAccountConnectedContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("ACCOUNT CONNECTED")

            Text(authenticationManager.clerkDisplayName ?? "Signed-in user")
                .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            if !authenticationManager.email.isEmpty {
                Text(authenticationManager.email)
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }

            Text("Authentication is ready. Workspace provisioning is the next production slice, so Ask, Teach, personas, chat, and local memory stay unavailable for now.")
                .font(ElevenLabsBrand.Typography.body)
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                Button("Open account") {
                    MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
                }
                .elevenLabsPrimaryButtonStyle(isFullWidth: false)
                .pointerCursor()

                Button("Sign out") {
                    authenticationManager.signOut()
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.98))
                .pointerCursor()
            }
        }
    }

    /// Compact persona picker in the top-right of the header. Shows just
    /// the active persona's avatar + name + chevron — the "PERSONA"
    /// label is omitted because the avatar makes it self-evident.
    /// Reuses the same popover content as the body picker did.
    private var headerPersonaPicker: some View {
        let activePersonaBundle = PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)
            ?? PersonaStore.mePseudoPersona

        return Button(action: { isPersonaPickerPresented.toggle() }) {
            HStack(spacing: 6) {
                PersonaAvatarView(
                    avatar: activePersonaBundle.avatar,
                    diameter: 20,
                    uploadedImageOverridePath: PersonaStore.uploadedProfilePicturePath(forPersonaId: activePersonaBundle.id)
                )
                Text(activePersonaBundle.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(
                        isHoveringPersonaCard
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isHoveringPersonaCard
                        ? ElevenLabsBrand.Colors.paperRecessed
                        : ElevenLabsBrand.Colors.card
                )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isHoveringPersonaCard
                            ? ElevenLabsBrand.Colors.inkTertiary.opacity(0.4)
                            : ElevenLabsBrand.Colors.hairline,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .fixedSize()
        .pointerCursor()
        .onHover { hovering in isHoveringPersonaCard = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringPersonaCard)
        .popover(
            isPresented: $isPersonaPickerPresented,
            arrowEdge: .top
        ) {
            personaPickerContent(activePersonaID: activePersonaBundle.id)
        }
    }

    /// The app's own brand mark — the flat-bottomed orb glyph used in
    /// the menu bar, paired with the "Sticky" wordmark. Same silhouette
    /// as `makeStickyMenuBarIcon` in MenuBarPanelManager so the in-panel
    /// brand reads as the same identity the user clicked from the
    /// status bar. Tapping the wordmark opens the full Sticky dashboard
    /// window — this replaces the standalone "Open Sticky" row that
    /// previously lived in the body of the panel and felt redundant
    /// next to the brand mark.
    private var stickyAppWordmark: some View {
        Button(action: {
            MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
        }) {
            HStack(spacing: 8) {
                StickyOrbGlyph(size: 18, color: ElevenLabsBrand.Colors.inkPure)
                    .offset(y: isHoveringOpenAppRow ? -4 : 0)
                    .animation(
                        isHoveringOpenAppRow
                            ? .spring(response: 0.32, dampingFraction: 0.42)
                            : .spring(response: 0.28, dampingFraction: 0.7),
                        value: isHoveringOpenAppRow
                    )

                Text("Sticky")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.inkPure)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(
                        isHoveringOpenAppRow
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
                    .offset(
                        x: isHoveringOpenAppRow ? 2 : 0,
                        y: isHoveringOpenAppRow ? -2 : 0
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.97))
        .pointerCursor()
        .nativeTooltip("Open the full Sticky app — dashboard, memory, and team views")
        .onHover { hovering in isHoveringOpenAppRow = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringOpenAppRow)
    }

    // MARK: - Main Content (onboarded + permissions granted)

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            instructionEyebrow

            if companionManager.hasVoiceConversationHistory {
                newVoiceChatRow
            }

            // Pending review surfaces (teach result card / review stack /
            // saved summary) live above the activity feed so they don't push
            // the primary controls around.
            if let pendingTeachSessionReview = companionManager.pendingTeachSessionResult {
                TeachSessionResultCard(
                    companionManager: companionManager,
                    pendingReview: pendingTeachSessionReview
                )
            } else if !companionManager.pendingAmbiguousMoments.isEmpty {
                ReviewCardStack(companionManager: companionManager)
            } else if companionManager.lastTeachSessionSavedPrincipleCount > 0
                && companionManager.teachSessionState == .idle {
                teachSessionSavedSummary
            }

            MiniPanelActivityFeed()

            primaryActionRow
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

/// Small "Start fresh chat" affordance that gives the user explicit
    /// control over voice-session boundaries. Tapping it clears the
    /// rolling voice conversation history, mints a new on-disk session
    /// id, and tells `CompanionManager` to inject a one-line note into
    /// the next system prompt so Sticky knows it may have spoken to
    /// the user before but doesn't currently remember the past chat.
    /// Lives just under the push-to-talk instruction so the user sees
    /// it next to the surface it controls without it competing with
    /// the primary CTA.
    private var newVoiceChatRow: some View {
        Button(action: {
            companionManager.beginNewVoiceChat()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                Text("Start fresh voice chat")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.paperRecessed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
        .nativeTooltip("Forget the current voice conversation and start a fresh chat. Sticky will know it may have spoken to you before but doesn't currently remember.")
    }

    /// Eyebrow + bold instruction line. The Control and Option modifier
    /// keys render as small rounded "keycap" chips so the shortcut reads
    /// the way it appears on a physical keyboard rather than as inline
    /// glyphs in a sentence.
    private var instructionEyebrow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ElevenLabsEyebrow("PUSH TO TALK")

            HStack(alignment: .center, spacing: 6) {
                Text("Hold")
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 18))
                    .tracking(-0.3)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                modifierKeyCap(symbolName: "control")

                Text("+")
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 18))
                    .tracking(-0.3)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)

                modifierKeyCap(symbolName: "option")
            }

            Text("to ask anything.")
                .font(ElevenLabsBrand.Typography.cardTitle(size: 18))
                .tracking(-0.3)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A small rounded-rectangle "keycap" rendering of a single modifier
    /// key. Sized to sit inline with the 18pt headline text.
    private func modifierKeyCap(symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .frame(width: 26, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
    }

    /// Body of the persona popover. Two sections separated by a hairline:
    /// the two pseudo-personas (Me, Team) on top, then a `TEAMMATES`
    /// section listing each member. Width is fixed so the layout reads
    /// the same regardless of name length.
    @ViewBuilder
    private func personaPickerContent(activePersonaID: String) -> some View {
        let teammates = PersonaStore.availableTeammates

        VStack(alignment: .leading, spacing: 0) {
            personaPickerRow(
                persona: PersonaStore.mePseudoPersona,
                isSelected: activePersonaID == PersonaStore.mePseudoPersona.id
            )
            personaPickerRow(
                persona: PersonaStore.teamPseudoPersona,
                isSelected: activePersonaID == PersonaStore.teamPseudoPersona.id
            )

            if !teammates.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Text("TEAMMATES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                ForEach(teammates, id: \.id) { teammate in
                    personaPickerRow(
                        persona: teammate,
                        isSelected: activePersonaID == teammate.id
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(ElevenLabsBrand.Colors.card)
    }

    /// Single row inside the persona popover: avatar + name + role +
    /// trailing checkmark when active. Hovering fills the row with a
    /// subtle paper-recessed wash so the click target is obvious.
    @ViewBuilder
    private func personaPickerRow(persona: PersonaBundle, isSelected: Bool) -> some View {
        PersonaPickerRow(
            persona: persona,
            isSelected: isSelected,
            onSelect: {
                companionManager.setPersonaSelection(
                    PersonaStore.selectionForWheelPersona(persona)
                )
                isPersonaPickerPresented = false
            }
        )
    }

    // MARK: - Primary Action Row
    //
    // Single black pill — the brand CTA — for Start/Stop/Analyzing.
    // Replaces the previous full-width tinted button.

    @ViewBuilder
    private var primaryActionRow: some View {
        switch companionManager.teachSessionState {
        case .idle:
            VStack(spacing: 6) {
                teachSessionStartButton
                Text("Narrate a task while you do it. Sticky turns it into notes your team can borrow.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ElevenLabsBrand.Spacing.sm)
            }
        case .recording:
            teachSessionRecordingButton
        case .analyzing:
            teachSessionAnalyzingPill
        }
    }

    private var teachSessionStartButton: some View {
        Button(action: {
            companionManager.startTeachSession()
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ElevenLabsBrand.Colors.tasteAccent)
                    .frame(width: 8, height: 8)
                Text("Show & tell")
            }
        }
        .elevenLabsPrimaryButtonStyle()
    }

    private var teachSessionRecordingButton: some View {
        Button(action: {
            companionManager.stopTeachSession()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Stop")
                Spacer()
                Text(formatTeachSessionElapsed(companionManager.teachSessionElapsedSeconds))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        }
        .elevenLabsPrimaryButtonStyle()
    }

    private var teachSessionAnalyzingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            Text(companionManager.teachAnalyzingStatus ?? "Reviewing your decisions…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .animation(.easeInOut(duration: 0.2), value: companionManager.teachAnalyzingStatus)
            Spacer()
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func formatTeachSessionElapsed(_ elapsedSeconds: Int) -> String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Saved summary

    /// Subtle confirmation toast after a teach session if at least one
    /// confident principle was auto-saved. Stays until the next teach
    /// session starts.
    private var teachSessionSavedSummary: some View {
        let savedCount = companionManager.lastTeachSessionSavedPrincipleCount
        let noteNoun = savedCount == 1 ? "note" : "notes"

        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Text("Saved \(savedCount) new \(noteNoun)")
                .font(ElevenLabsBrand.Typography.bodyStrong)
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Spacer()
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    // MARK: - Onboarding (permissions granted)

    @ViewBuilder
    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                ElevenLabsEyebrow("ALMOST READY")
                Text("You're all set.\nHit Start to meet Sticky.")
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                    .tracking(-0.3)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: {
                companionManager.triggerOnboarding()
            }) {
                Text("Start")
            }
            .elevenLabsPrimaryButtonStyle()
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                ElevenLabsEyebrow(
                    companionManager.hasCompletedOnboarding
                        ? "PERMISSIONS REVOKED"
                        : "WELCOME"
                )
                Text(
                    companionManager.hasCompletedOnboarding
                        ? "Re-grant access\nto keep using Sticky."
                        : "Grant access to\nmeet Sticky."
                )
                .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                .tracking(-0.3)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)

                Text("Nothing runs in the background. Sticky only captures the screen when you press the hotkey.")
                    .font(ElevenLabsBrand.Typography.body)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            VStack(spacing: ElevenLabsBrand.Spacing.xs) {
                permissionCard(
                    label: "Microphone",
                    iconSymbol: "mic",
                    isGranted: companionManager.hasMicrophonePermission,
                    onGrant: requestMicrophonePermission
                )
                permissionCard(
                    label: "Accessibility",
                    iconSymbol: "hand.raised",
                    isGranted: companionManager.hasAccessibilityPermission,
                    onGrant: { _ = WindowPositionManager.requestAccessibilityPermission() }
                )
                permissionCard(
                    label: "Screen Recording",
                    iconSymbol: "rectangle.dashed.badge.record",
                    isGranted: companionManager.hasScreenRecordingPermission,
                    helperText: companionManager.hasScreenRecordingPermission
                        ? nil
                        : "Quit and reopen after granting",
                    onGrant: { _ = WindowPositionManager.requestScreenRecordingPermission() }
                )
                if companionManager.hasScreenRecordingPermission {
                    permissionCard(
                        label: "Screen Content",
                        iconSymbol: "eye",
                        isGranted: companionManager.hasScreenContentPermission,
                        onGrant: { companionManager.requestScreenContentPermission() }
                    )
                }
            }
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

    /// One permission item rendered as a paper card. Granted state shows
    /// an ink check; ungranted state shows a black-pill Grant button on
    /// the trailing edge.
    private func permissionCard(
        label: String,
        iconSymbol: String,
        isGranted: Bool,
        helperText: String? = nil,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Image(systemName: iconSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(
                    isGranted
                        ? ElevenLabsBrand.Colors.ink
                        : ElevenLabsBrand.Colors.gradientCoral
                )
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(ElevenLabsBrand.Typography.bodyStrong)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                if let helperText, !helperText.isEmpty {
                    Text(helperText)
                        .font(ElevenLabsBrand.Typography.caption)
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: onGrant) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.paper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ElevenLabsBrand.Colors.inkPure))
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.92))
                .pointerCursor()
            }
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, ElevenLabsBrand.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        } else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ElevenLabsBrand.Colors.hairline)
                .frame(height: 1)

            // Footer: identity chip on the left, Voice Color + Theme + Quit on the right.
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                if authenticationManager.canAccessProductionFeatures {
                    signedInUserChip
                }

                Spacer()

                if authenticationManager.canAccessProductionFeatures {
                    voiceColorPickerButton
                }

                themePickerButton

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(
                            isHoveringQuitButton
                                ? ElevenLabsBrand.Colors.ink
                                : ElevenLabsBrand.Colors.inkTertiary
                        )
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(
                                    isHoveringQuitButton
                                        ? ElevenLabsBrand.Colors.ink.opacity(0.08)
                                        : Color.clear
                                )
                        )
                        .scaleEffect(isHoveringQuitButton ? 1.08 : 1.0)
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.92))
                .pointerCursor()
                .nativeTooltip("Quit Sticky")
                .onHover { hovering in isHoveringQuitButton = hovering }
                .animation(.easeOut(duration: 0.16), value: isHoveringQuitButton)
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, 10)
        }
    }

    /// Tiny "signed in as X" chip in the footer — clicking opens the
    /// dashboard's Profile tab where the user can edit local profile
    /// details or sign out. It follows Convex's authenticated state.
    @ViewBuilder
    private var signedInUserChip: some View {
        if authenticationManager.canAccessProductionFeatures {
            Button(action: {
                DashboardNavigationState.shared.selectedSection = .profile
                MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
            }) {
                HStack(spacing: 6) {
                    miniSignedInAvatar

                    Text(authenticationManager.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            isHoveringSignedInChip
                                ? ElevenLabsBrand.Colors.ink
                                : ElevenLabsBrand.Colors.inkTertiary
                        )
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        isHoveringSignedInChip
                            ? ElevenLabsBrand.Colors.paperRecessed
                            : Color.clear
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.96))
            .pointerCursor()
            .nativeTooltip("Edit your profile in the dashboard")
            .onHover { hovering in isHoveringSignedInChip = hovering }
            .animation(.easeOut(duration: 0.14), value: isHoveringSignedInChip)
        } else {
            Button(action: {
                MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
            }) {
                Text("Sign in")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(
                        isHoveringSignedInChip
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.94))
            .pointerCursor()
            .onHover { hovering in isHoveringSignedInChip = hovering }
            .animation(.easeOut(duration: 0.14), value: isHoveringSignedInChip)
        }
    }

    /// Tiny circular avatar for the footer chip — uses the local
    /// persona's avatar when one is loaded, otherwise a small initials
    /// circle so the chip stays readable on a fresh install.
    @ViewBuilder
    private var miniSignedInAvatar: some View {
        if let localBundle = PersonaStore.myOwnBundle {
            PersonaAvatarView(
                avatar: localBundle.avatar,
                diameter: 16,
                uploadedImageOverridePath: PersonaStore.uploadedProfilePicturePath(forPersonaId: localBundle.id)
            )
        } else {
            Circle()
                .fill(ElevenLabsBrand.Colors.gradientSky)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Voice Color Picker (footer)

    /// Compact icon button in the footer — a small filled circle in the
    /// user's current voice color. Tapping it opens a popover with a
    /// circular hue wheel so the user can retint their bottom-edge mic
    /// glow live without leaving the panel.
    private var voiceColorPickerButton: some View {
        Button(action: { isVoiceColorPickerPresented.toggle() }) {
            VoiceColorOrb(
                colors: companionManager.userVoiceAuroraColors,
                diameter: 14,
                outlineColor: isHoveringVoiceColorButton
                    ? ElevenLabsBrand.Colors.ink.opacity(0.5)
                    : ElevenLabsBrand.Colors.hairline
            )
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(
                        isHoveringVoiceColorButton
                            ? ElevenLabsBrand.Colors.ink.opacity(0.08)
                            : Color.clear
                    )
            )
            .scaleEffect(isHoveringVoiceColorButton ? 1.08 : 1.0)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.92))
        .pointerCursor()
        .nativeTooltip("Your color — bottom-edge glow while you hold ctrl+option")
        .onHover { hovering in isHoveringVoiceColorButton = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringVoiceColorButton)
        .animation(.easeOut(duration: 0.16), value: companionManager.userVoiceColorHues)
        .popover(
            isPresented: $isVoiceColorPickerPresented,
            arrowEdge: .bottom
        ) {
            VoiceColorPickerPopover(companionManager: companionManager)
        }
    }

    // MARK: - Theme Picker (footer)

    /// Compact icon button in the footer — shows the currently-active
    /// theme mode as a glyph (sun / moon / split-circle). Tapping it
    /// opens a small popover with the three options laid out as rows,
    /// matching the persona popover's row pattern so the two pickers
    /// feel like the same control in two places.
    private var themePickerButton: some View {
        Button(action: { isThemePickerPresented.toggle() }) {
            Image(systemName: themeManager.mode.sfSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    isHoveringThemeButton
                        ? ElevenLabsBrand.Colors.ink
                        : ElevenLabsBrand.Colors.inkTertiary
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(
                            isHoveringThemeButton
                                ? ElevenLabsBrand.Colors.ink.opacity(0.08)
                                : Color.clear
                        )
                )
                .scaleEffect(isHoveringThemeButton ? 1.08 : 1.0)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.92))
        .pointerCursor()
        .nativeTooltip("Appearance — \(themeManager.mode.displayLabel)")
        .onHover { hovering in isHoveringThemeButton = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringThemeButton)
        .animation(.easeOut(duration: 0.16), value: themeManager.mode)
        .popover(
            isPresented: $isThemePickerPresented,
            arrowEdge: .bottom
        ) {
            themePickerPopoverContent
        }
    }

    /// Three-row popover body: System / Light / Dark. Each row is a
    /// button that switches `ThemeManager.shared.mode` and dismisses
    /// the popover. Selected row gets a checkmark.
    private var themePickerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AppThemeMode.allCases) { themeMode in
                ThemePickerPopoverRow(
                    themeMode: themeMode,
                    isSelected: themeManager.mode == themeMode,
                    onSelect: {
                        themeManager.mode = themeMode
                        isThemePickerPresented = false
                    }
                )
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(ElevenLabsBrand.Colors.card)
    }

    // MARK: - Visual Helpers

    private var panelBackground: some View {
        // The actual rounded mask, paper fill, and hairline border are
        // owned by `WarmDropdownBackgroundView` (now a paper surface).
        // SwiftUI background is fully transparent so it doesn't paint
        // anything on top of the AppKit layer.
        Color.clear
    }
}

// MARK: - Sticky Orb Glyph
//
// SwiftUI rendering of the same flat-bottomed orb silhouette used in
// the menu bar (`makeStickyMenuBarIcon` in MenuBarPanelManager): a
// circle with its lower portion cut by a horizontal chord, so the
// glyph reads as "an orb sitting on a surface". Implemented as a
// `Shape` so it scales cleanly and respects the parent's color.

struct StickyOrbShape: Shape {
    /// Fraction of the orb's radius that the flat base sits below
    /// center. ~0.65 leaves most of the sphere visible while still
    /// clearly reading as flat-bottomed. Matches the menu-bar glyph.
    var chordOffsetFraction: CGFloat = 0.65

    func path(in rect: CGRect) -> Path {
        // The orb fills 85% of the bounding box on the shorter axis so
        // the antialiased edge isn't clipped and there's a hint of
        // breathing room around the glyph.
        let orbDiameter = min(rect.width, rect.height) * 0.92
        let radius = orbDiameter / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let chordOffset = radius * chordOffsetFraction
        let halfChord = sqrt(max(0, radius * radius - chordOffset * chordOffset))

        // SwiftUI uses y-down coordinates, so "below center" = larger y.
        let chordY = center.y + chordOffset
        let leftChordEnd = CGPoint(x: center.x - halfChord, y: chordY)
        let rightChordEnd = CGPoint(x: center.x + halfChord, y: chordY)

        // Angle (in SwiftUI's y-down convention) from the center to
        // the right chord endpoint. Mirroring across the y-axis gives
        // the left chord endpoint angle.
        let rightAngle = Angle(radians: atan2(chordY - center.y, halfChord))
        let leftAngle = Angle(degrees: 180 - rightAngle.degrees)

        var path = Path()
        path.move(to: rightChordEnd)
        // Trace the arc the long way around — over the top of the
        // circle — to reach the left chord endpoint. With y-down
        // coordinates, that's `clockwise: true` in SwiftUI's API.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: rightAngle,
            endAngle: leftAngle,
            clockwise: true
        )
        path.addLine(to: leftChordEnd)
        path.closeSubpath()
        return path
    }
}

// MARK: - Persona Picker Row
//
// Custom row used by the persona popover. Encapsulates hover state so
// the surrounding view doesn't need a per-row @State.

private struct PersonaPickerRow: View {
    let persona: PersonaBundle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PersonaAvatarView(
                    avatar: persona.avatar,
                    diameter: 28,
                    uploadedImageOverridePath: PersonaStore.uploadedProfilePicturePath(forPersonaId: persona.id)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(persona.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)

                    if let role = persona.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? ElevenLabsBrand.Colors.paperRecessed : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Theme Picker Popover Row
//
// Single row inside the footer's theme popover: glyph + label + (when
// `.system`) a one-line subtitle explaining the auto-follow behavior.
// Hovering fills the row with a paper-recessed wash so the click
// target is obvious. Mirrors the persona-picker row pattern visually
// so the two pickers feel like the same control.

private struct ThemePickerPopoverRow: View {
    let themeMode: AppThemeMode
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: themeMode.sfSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .frame(width: 22)

                Text(themeMode.displayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? ElevenLabsBrand.Colors.paperRecessed : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Voice Color Picker Popover
//
// The footer button's popover. Owns a transient "working hue" — the
// hue currently parked on the wheel — separate from the committed list
// the manager persists. The user spins the wheel to pick a color, taps
// the "+" button to commit it as a chip, and the bottom-edge glow then
// renders that chip's color (or, with multiple chips, an aurora across
// all of them). Tapping a chip removes it. Capped at
// `CompanionManager.maxUserVoiceColorHues` chips.

private struct VoiceColorPickerPopover: View {
    @ObservedObject var companionManager: CompanionManager

    /// Hue currently parked on the wheel (in degrees). Local state
    /// because it doesn't represent a committed selection — the user
    /// has to press "+" to add it to the manager's list. Initialized
    /// from the last committed hue (so opening the popover lands on
    /// "the last color you picked") falling back to the default blue
    /// when the user has cleared the list entirely.
    @State private var workingHueDegrees: Double

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        let initialHue = companionManager.userVoiceColorHues.last
            ?? CompanionManager.defaultUserVoiceColorHue
        _workingHueDegrees = State(initialValue: initialHue)
    }

    private var canAddMoreColors: Bool {
        companionManager.userVoiceColorHues.count < CompanionManager.maxUserVoiceColorHues
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("YOUR COLOR")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

            HueWheel(hueDegrees: $workingHueDegrees, diameter: 160)

            committedColorChipsRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 240)
        .background(ElevenLabsBrand.Colors.card)
    }

    /// Horizontal strip of committed colors with a trailing "+" button
    /// that adds the wheel's current working hue. Tapping a chip removes
    /// it. The "+" is filled with the working color so the user sees
    /// exactly which color is about to land in the strip — once the
    /// list is full it dims and disables.
    private var committedColorChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(companionManager.userVoiceColorHues.enumerated()), id: \.offset) { indexAndHue in
                let chipIndex = indexAndHue.offset
                let chipHue = indexAndHue.element
                CommittedColorChip(
                    hueDegrees: chipHue,
                    onRemove: {
                        companionManager.removeUserVoiceColorHue(at: chipIndex)
                    }
                )
            }
            addColorButton
        }
        .frame(height: 22)
    }

    private var addColorButton: some View {
        Button(action: {
            guard canAddMoreColors else { return }
            companionManager.addUserVoiceColorHue(workingHueDegrees)
        }) {
            ZStack {
                Circle()
                    .fill(
                        canAddMoreColors
                            ? Color(hue: workingHueDegrees / 360.0, saturation: 0.8, brightness: 1.0).opacity(0.85)
                            : ElevenLabsBrand.Colors.paperRecessed
                    )
                Circle()
                    .stroke(
                        canAddMoreColors
                            ? Color.white
                            : ElevenLabsBrand.Colors.hairline,
                        style: StrokeStyle(
                            lineWidth: canAddMoreColors ? 1.5 : 1,
                            dash: canAddMoreColors ? [] : [2, 2]
                        )
                    )
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(
                        canAddMoreColors
                            ? .white
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
                    .shadow(
                        color: canAddMoreColors ? Color.black.opacity(0.3) : .clear,
                        radius: 1, x: 0, y: 0
                    )
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.9))
        .pointerCursor()
        .disabled(!canAddMoreColors)
        .nativeTooltip(
            canAddMoreColors
                ? "Add this color to your aurora"
                : "Aurora is full (\(CompanionManager.maxUserVoiceColorHues) colors max)"
        )
    }
}

/// One committed color in the popover's chip strip. Filled with the
/// hue's color; tap to remove. Hovering reveals an inset "×" so the
/// affordance reads as deletable rather than a static swatch.
private struct CommittedColorChip: View {
    let hueDegrees: Double
    let onRemove: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onRemove) {
            ZStack {
                Circle()
                    .fill(Color(hue: hueDegrees / 360.0, saturation: 0.8, brightness: 1.0))
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                Circle()
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
                if isHovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 0)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.9))
        .pointerCursor()
        .nativeTooltip("Remove this color")
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Voice Color Orb
//
// Small glowing orb shown on the footer button. With one color it reads
// as a flat colored dot; with multiple colors the colors blur into a
// soft gradient orb so the button telegraphs the user's whole aurora at
// a glance. Built from a horizontal `LinearGradient` re-clipped to a
// circle and softly blurred so adjacent colors bleed into each other,
// plus a top-left specular highlight + a subtle outer glow in the
// average color so the dot feels like a lit orb rather than a flat
// swatch.

private struct VoiceColorOrb: View {
    let colors: [Color]
    let diameter: CGFloat
    let outlineColor: Color

    /// Mean of all the colors, used for the outer glow ring so the
    /// "spill" around the orb reads as the aurora's overall hue rather
    /// than locking onto whichever color happened to be first.
    private var averagedColor: Color {
        guard !colors.isEmpty else { return .white }
        var totalRed: CGFloat = 0
        var totalGreen: CGFloat = 0
        var totalBlue: CGFloat = 0
        for color in colors {
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
            totalRed   += nsColor.redComponent
            totalGreen += nsColor.greenComponent
            totalBlue  += nsColor.blueComponent
        }
        let count = CGFloat(colors.count)
        return Color(
            red: Double(totalRed / count),
            green: Double(totalGreen / count),
            blue: Double(totalBlue / count)
        )
    }

    var body: some View {
        ZStack {
            // The colored fill — single color or aurora gradient. Aurora
            // variant is blurred so neighboring colors bleed into one
            // another, then re-clipped to the circle so the blur doesn't
            // soften the orb's silhouette.
            Group {
                if colors.count <= 1 {
                    Circle().fill(colors.first ?? .white)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .blur(radius: max(1, diameter * 0.18))
                        .clipShape(Circle())
                }
            }

            // Top-left specular highlight — sells the "lit orb" feel
            // without painting a full sphere shader.
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.0)
                        ]),
                        center: UnitPoint(x: 0.32, y: 0.30),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )

            Circle()
                .stroke(outlineColor, lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: averagedColor.opacity(0.55), radius: max(2, diameter * 0.25), x: 0, y: 0)
    }
}

// MARK: - Hue Wheel
//
// Circular hue picker used by the footer voice-color popover. The wheel
// itself is the hue spectrum painted as an `AngularGradient` masked into
// a ring (annulus), so the affordance is unambiguous — click or drag
// anywhere on the wheel to retint the user's bottom-edge mic glow live.
// Bound to the hue in degrees (0...360), with 0° at the right (3 o'clock)
// and angle increasing clockwise to match the gradient stops.
//
// Sizing is fixed (no GeometryReader) — `.popover` content on macOS
// can lay out flexibly-sized children unpredictably which interferes
// with click delivery, so we pin everything to a known diameter and
// compute positions from a single center constant.

private struct HueWheel: View {
    @Binding var hueDegrees: Double

    let diameter: CGFloat

    private let ringThickness: CGFloat = 18
    private let handleDiameter: CGFloat = 22

    private var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }
    private var ringCenterRadius: CGFloat { diameter / 2 - ringThickness / 2 }

    private static let hueAngularGradient = AngularGradient(
        gradient: Gradient(colors: [
            Color(hue: 0.0,   saturation: 0.8, brightness: 1.0),
            Color(hue: 0.125, saturation: 0.8, brightness: 1.0),
            Color(hue: 0.25,  saturation: 0.8, brightness: 1.0),
            Color(hue: 0.375, saturation: 0.8, brightness: 1.0),
            Color(hue: 0.5,   saturation: 0.8, brightness: 1.0),
            Color(hue: 0.625, saturation: 0.8, brightness: 1.0),
            Color(hue: 0.75,  saturation: 0.8, brightness: 1.0),
            Color(hue: 0.875, saturation: 0.8, brightness: 1.0),
            Color(hue: 1.0,   saturation: 0.8, brightness: 1.0)
        ]),
        center: .center,
        startAngle: .degrees(0),
        endAngle: .degrees(360)
    )

    var body: some View {
        let handleAngleRadians = hueDegrees * .pi / 180.0
        let handleCenter = CGPoint(
            x: center.x + cos(handleAngleRadians) * ringCenterRadius,
            y: center.y + sin(handleAngleRadians) * ringCenterRadius
        )
        let currentColor = Color(hue: hueDegrees / 360.0, saturation: 0.8, brightness: 1.0)

        return ZStack {
            // Hit-target backdrop so clicks anywhere within the wheel's
            // bounding square register on the gesture, including the
            // hollow middle. Drawing a near-clear color (rather than
            // .clear) keeps SwiftUI's hit-testing happy.
            Color.black.opacity(0.001)

            Circle()
                .strokeBorder(Self.hueAngularGradient, lineWidth: ringThickness)

            Circle()
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            Circle()
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
                .padding(ringThickness)

            // Center swatch — large preview of the currently picked
            // color so the user sees the result alongside the wheel.
            Circle()
                .fill(currentColor)
                .overlay(Circle().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1))
                .padding(ringThickness + 8)

            // Draggable handle pinned at the angle matching the current
            // hue. Filled with the current color so the handle reads as
            // "this is what's selected."
            Circle()
                .fill(currentColor)
                .frame(width: handleDiameter, height: handleDiameter)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                .position(handleCenter)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Rectangle())
        // Use `highPriorityGesture` (not `.gesture`) so the wheel claims
        // the mouseDown / mouseUp pair before SwiftUI's enclosing popover
        // sees the release. Without this, NSPopover treats the unclaimed
        // mouseUp as an outside-tap and dismisses on release.
        // `onEnded` is a no-op but its presence ensures the gesture
        // formally completes at the AppKit layer.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { dragValue in
                    updateHue(forLocation: dragValue.location)
                }
                .onEnded { _ in }
        )
    }

    private func updateHue(forLocation location: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        // Ignore drags that land too close to the center (no meaningful
        // angle there) so a tiny jitter near the middle doesn't snap
        // the handle to a random direction.
        guard hypot(dx, dy) > 4 else { return }
        var angleDegrees = atan2(dy, dx) * 180.0 / .pi
        if angleDegrees < 0 { angleDegrees += 360 }
        hueDegrees = angleDegrees
    }
}

/// Convenience view wrapping `StickyOrbShape` with a fixed size + fill
/// color. Use this as the brand mark inside SwiftUI views (panel
/// header, onboarding hero, etc.).
struct StickyOrbGlyph: View {
    var size: CGFloat = 16
    var color: Color = .black

    var body: some View {
        StickyOrbShape()
            .fill(color)
            .frame(width: size, height: size)
    }
}
