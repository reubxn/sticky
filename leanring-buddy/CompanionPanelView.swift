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

    @State private var emailInput: String = ""

    /// Drives the breathing animation on the status dot when Sticky is
    /// actively listening / processing / responding. Toggles continuously
    /// while `isVoiceActive` is true.
    @State private var isStatusDotPulsing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroHeader

            if !companionManager.allPermissionsGranted {
                permissionsContent
            } else if !companionManager.hasCompletedOnboarding {
                onboardingContent
            } else {
                mainContent
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
    }

    // MARK: - Hero Header
    //
    // App wordmark on the left, status pill on the right. The wordmark
    // is a custom "Sticky" mark — a small filled pause-bars glyph paired
    // with the app name in tight, ink-weight type. The status pill uses
    // a coral dot that breathes while Sticky is active.

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: ElevenLabsBrand.Spacing.sm) {
                stickyAppWordmark

                Spacer()

                statusPill
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.top, ElevenLabsBrand.Spacing.md)
            .padding(.bottom, ElevenLabsBrand.Spacing.sm)

            Rectangle()
                .fill(ElevenLabsBrand.Colors.hairline)
                .frame(height: 1)
        }
    }

    /// The app's own brand mark — the flat-bottomed orb glyph used in
    /// the menu bar, paired with the "Sticky" wordmark. Same silhouette
    /// as `makeStickyMenuBarIcon` in MenuBarPanelManager so the in-panel
    /// brand reads as the same identity the user clicked from the
    /// status bar.
    private var stickyAppWordmark: some View {
        HStack(spacing: 8) {
            StickyOrbGlyph(size: 18, color: ElevenLabsBrand.Colors.inkPure)

            Text("Sticky")
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkPure)
        }
    }

    /// Status pill — paper card with a colored dot + label. The dot
    /// gently breathes (opacity oscillation) while voice is active so
    /// "I'm listening to you" is unmissable without being noisy.
    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusPillColor)
                .frame(width: 6, height: 6)
                .scaleEffect(isStatusDotPulsing && isVoiceActive ? 1.25 : 1.0)
                .opacity(isStatusDotPulsing && isVoiceActive ? 0.65 : 1.0)
                .animation(
                    isVoiceActive
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                    value: isStatusDotPulsing
                )

            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: statusText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(ElevenLabsBrand.Colors.card))
        .overlay(Capsule().stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1))
        .onAppear { isStatusDotPulsing = true }
        .onChange(of: isVoiceActive) { _ in
            // Re-trigger the breathing loop when activity flips on/off.
            isStatusDotPulsing.toggle()
        }
    }

    private var isVoiceActive: Bool {
        guard companionManager.isOverlayVisible else { return false }
        switch companionManager.voiceState {
        case .listening, .processing, .responding: return true
        case .idle: return false
        }
    }

    private var statusPillColor: Color {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return ElevenLabsBrand.Colors.gradientCoral
        }
        return isVoiceActive
            ? ElevenLabsBrand.Colors.gradientCoral
            : ElevenLabsBrand.Colors.ink
    }

    private var statusText: String {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return "Setup"
        }
        if !companionManager.isOverlayVisible {
            return "Ready"
        }
        switch companionManager.voiceState {
        case .idle:       return "Active"
        case .listening:  return "Listening"
        case .processing: return "Processing"
        case .responding: return "Responding"
        }
    }

    // MARK: - Main Content (onboarded + permissions granted)

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            instructionEyebrow

            settingsGrid

            primaryActionRow

            // Pending review surfaces (teach result card / review stack /
            // saved summary) live below the action area so they don't push
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

            openChatLink

            tasteLibraryLink

            openDashboardLink
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

    // MARK: - Dashboard Link

    /// Opens the full Sticky Dashboard window — sidebar with Tastes,
    /// Team, Profile, Recordings, Chats, Settings. The mini panel is
    /// the quick HUD; the dashboard is where you actually manage
    /// your taste, your team, and your profile.
    private var openDashboardLink: some View {
        Button(action: {
            MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                Text("Open dashboard")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .pointerCursor()
        .nativeTooltip("Personas, team, profile, recordings, chats, settings")
    }

    /// Eyebrow + bold instruction line. Uses SF Symbol glyphs for the
    /// Control and Option modifier keys so the shortcut reads at a
    /// glance the way it appears on the user's keyboard.
    private var instructionEyebrow: some View {
        let headline = Text("Hold ")
            + Text(Image(systemName: "control"))
            + Text(" + ")
            + Text(Image(systemName: "option"))
            + Text("\nto ask anything.")

        return VStack(alignment: .leading, spacing: 4) {
            ElevenLabsEyebrow("PUSH TO TALK")
            headline
                .font(ElevenLabsBrand.Typography.cardTitle(size: 18))
                .tracking(-0.3)
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Settings Grid
    //
    // Persona is the only setting that lives in the panel body. It
    // doubles as the scope control: picking Me runs personal mode,
    // picking Team runs pooled-team mode, picking a teammate borrows
    // their lens entirely. A separate Personal/Team toggle would just
    // duplicate state that CompanionManager already derives from the
    // persona selection (see setPersonaSelection). Model lives in the
    // footer as a discreet selector.

    private var settingsGrid: some View {
        VStack(spacing: ElevenLabsBrand.Spacing.sm) {
            personaControl
        }
    }

    /// Persona picker rendered as a standard dropdown. The trigger row
    /// shows the active persona's avatar + name on the leading edge and
    /// a chevron on the trailing edge. Tapping opens a native Menu with
    /// Me + Team at the top and a Teammates section below — the persona
    /// IS the scope, so no separate Personal/Team toggle is needed.
    private var personaControl: some View {
        let activePersonaBundle = PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)
            ?? PersonaStore.mePseudoPersona
        let teammates = PersonaStore.availableTeammates

        return HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Text("PERSONA")
                .font(ElevenLabsBrand.Typography.eyebrow)
                .tracking(0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

            Spacer()

            Menu {
                personaMenuButton(persona: PersonaStore.mePseudoPersona)
                personaMenuButton(persona: PersonaStore.teamPseudoPersona)
                if !teammates.isEmpty {
                    Divider()
                    Section("Teammates") {
                        ForEach(teammates, id: \.id) { teammate in
                            personaMenuButton(persona: teammate)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    PersonaAvatarView(
                        avatar: activePersonaBundle.avatar,
                        diameter: 20
                    )
                    Text(activePersonaBundle.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerCursor()
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    /// One row in the persona menu. Shows display name + role; selecting
    /// it commits the persona via CompanionManager (which also keeps
    /// tasteScope in sync for .me / .team).
    @ViewBuilder
    private func personaMenuButton(persona: PersonaBundle) -> some View {
        Button(action: {
            companionManager.setPersonaSelection(
                PersonaStore.selectionForWheelPersona(persona)
            )
        }) {
            if let role = persona.role, !role.isEmpty {
                Text("\(persona.displayName) — \(role)")
            } else {
                Text(persona.displayName)
            }
        }
    }

    // MARK: - Primary Action Row
    //
    // Single black pill — the brand CTA — for Start/Stop/Analyzing.
    // Replaces the previous full-width tinted button.

    @ViewBuilder
    private var primaryActionRow: some View {
        switch companionManager.teachSessionState {
        case .idle:
            teachSessionStartButton
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
                    .fill(ElevenLabsBrand.Colors.gradientCoral)
                    .frame(width: 8, height: 8)
                Text("Start Teach Session")
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
            Text("Reviewing your decisions…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
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
        let principleNoun = savedCount == 1 ? "principle" : "principles"

        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)

            Text("Saved \(savedCount) new \(principleNoun)")
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

    // MARK: - Chat Link

    /// Opens the floating chat window. Styled as a discreet text link to
    /// match `tasteLibraryLink` so the two secondary destinations sit
    /// quietly above the footer without competing with the primary CTA.
    private var openChatLink: some View {
        Button(action: {
            MenuBarPanelManager.shared?.openChatWindow()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("Open chat")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .pointerCursor()
        .nativeTooltip("Chat with Sticky in a floating window")
    }

    // MARK: - Library Link

    /// Demoted from a full-width tinted button to a discreet text link
    /// sitting just above the footer. The library is a reference, not a
    /// frequent destination — it shouldn't compete with the primary CTA.
    private var tasteLibraryLink: some View {
        Button(action: {
            MenuBarPanelManager.shared?.openTasteLibraryWindow(
                companionManager: companionManager
            )
        }) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 11, weight: .semibold))
                Text("View memory library")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .pointerCursor()
        .nativeTooltip("See every principle Sticky has learned")
    }

    // MARK: - Onboarding (permissions granted, email not yet submitted)

    @ViewBuilder
    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                ElevenLabsEyebrow("ALMOST READY")
                if !companionManager.hasSubmittedEmail {
                    Text("Drop your email\nto get started.")
                        .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                        .tracking(-0.3)
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If I keep building this, I'll keep you in the loop.")
                        .font(ElevenLabsBrand.Typography.body)
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                } else {
                    Text("You're all set.\nHit Start to meet Sticky.")
                        .font(ElevenLabsBrand.Typography.cardTitle(size: 20))
                        .tracking(-0.3)
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !companionManager.hasSubmittedEmail {
                emailInputCard

                Button(action: {
                    companionManager.submitEmail(emailInput)
                }) {
                    Text("Submit")
                }
                .elevenLabsPrimaryButtonStyle()
                .disabled(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
            } else {
                Button(action: {
                    companionManager.triggerOnboarding()
                }) {
                    Text("Start")
                }
                .elevenLabsPrimaryButtonStyle()
            }
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

    private var emailInputCard: some View {
        TextField("you@email.com", text: $emailInput)
            .textFieldStyle(.plain)
            .font(ElevenLabsBrand.Typography.body)
            .foregroundColor(ElevenLabsBrand.Colors.ink)
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
                        .foregroundColor(ElevenLabsBrand.Colors.onAccent)
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

            HStack(spacing: ElevenLabsBrand.Spacing.md) {
                modelFooterMenu

                Spacer()

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("Quit Sticky")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, 10)
        }
    }

    /// Compact model picker living in the footer. Power users can switch
    /// between Haiku / Sonnet / Opus, but the control no longer competes
    /// for attention with persona / scope / the primary CTA. Renders as
    /// a discreet text+chevron menu trigger styled like "Quit Sticky".
    private var modelFooterMenu: some View {
        let modelDisplayName: String = {
            switch companionManager.selectedModel {
            case "claude-haiku-4-5-20251001": return "Haiku"
            case "claude-sonnet-4-6":         return "Sonnet"
            case "claude-opus-4-6":           return "Opus"
            default:                          return "Model"
            }
        }()

        return Menu {
            Button("Haiku — fastest")  { companionManager.setSelectedModel("claude-haiku-4-5-20251001") }
            Button("Sonnet — balanced") { companionManager.setSelectedModel("claude-sonnet-4-6") }
            Button("Opus — smartest")  { companionManager.setSelectedModel("claude-opus-4-6") }
        } label: {
            HStack(spacing: 4) {
                Text("Model: \(modelDisplayName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .nativeTooltip("Switch the Claude model that powers Sticky")
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
