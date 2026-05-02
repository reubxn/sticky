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

    /// Live mock-auth state so the footer's signed-in chip and the
    /// "Sign in" fallback react instantly when the user signs in or
    /// out from the dashboard while the panel is open.
    @ObservedObject private var dashboardMockAuthState = DashboardMockAuthState.shared

    @State private var emailInput: String = ""

    /// Drives the breathing animation on the status dot when Sticky is
    /// actively listening / processing / responding. Toggles continuously
    /// while `isVoiceActive` is true.
    @State private var isStatusDotPulsing: Bool = false

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
    @State private var isHoveringModelMenu: Bool = false

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

            MiniPanelActivityFeed()

            navigationRail
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.top, ElevenLabsBrand.Spacing.md)
        .padding(.bottom, ElevenLabsBrand.Spacing.sm)
    }

    // MARK: - Navigation Rail
    //
    // Three equal tiles — Chat / Memory / Dashboard — replacing the
    // earlier stack of three near-identical text links. The previous
    // layout had three rows that all looked the same (icon + label +
    // up-right arrow), with the markdown-export icon orphaned to the
    // far right of the Memory row. The rail gives each destination
    // equal weight, removes the repeated "↗" decorations, and tucks
    // export into the Memory tile as a small secondary affordance.
    private var navigationRail: some View {
        HStack(spacing: ElevenLabsBrand.Spacing.xs) {
            navigationTile(
                iconSymbol: "bubble.left.and.bubble.right",
                title: "Chat",
                tooltip: "Open Chat inside the dashboard",
                action: {
                    MenuBarPanelManager.shared?.openDashboardWindow(
                        focusedPersonaId: nil,
                        initialSection: .chat
                    )
                }
            )

            navigationTile(
                iconSymbol: "books.vertical",
                title: "Memory",
                tooltip: "See every principle Sticky has learned",
                action: {
                    MenuBarPanelManager.shared?.openDashboardWindow(
                        focusedPersonaId: nil,
                        initialSection: .memory
                    )
                },
                trailingAccessory: AnyView(memoryExportAccessory)
            )

            navigationTile(
                iconSymbol: "square.grid.2x2",
                title: "Dashboard",
                tooltip: "Personas, team, profile, recordings, chats, settings",
                action: {
                    MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
                }
            )
        }
    }

    /// One tile in the navigation rail. Square-ish, icon stacked above
    /// label, paper card with hairline border. Tile fills the available
    /// width so all three rails sit in a perfectly even row regardless
    /// of label length. The optional `trailingAccessory` is laid out in
    /// the top-right corner via overlay so it can't push the centered
    /// icon/label off-axis.
    private func navigationTile(
        iconSymbol: String,
        title: String,
        tooltip: String,
        action: @escaping () -> Void,
        trailingAccessory: AnyView? = nil
    ) -> some View {
        NavigationTile(
            iconSymbol: iconSymbol,
            title: title,
            tooltip: tooltip,
            action: action,
            trailingAccessory: trailingAccessory
        )
    }

    /// Tiny export-to-markdown affordance pinned to the top-right of the
    /// Memory tile. Stops propagation so tapping the icon doesn't also
    /// open the library. Mirrors the same export action that lived on
    /// the old `tasteLibraryLink` row.
    private var memoryExportAccessory: some View {
        MemoryExportAccessoryButton(
            action: { exportPersonalTasteAsMarkdownFromMiniPanel() }
        )
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

    /// Persona picker rendered as a custom popover. Trigger shows the
    /// active persona's avatar + name; tapping opens a paper-styled
    /// dropdown with two sections (Modes, Teammates). Each row renders
    /// the persona avatar, display name, and role — the native `Menu`
    /// can't show avatars, which is why we render our own.
    private var personaControl: some View {
        let activePersonaBundle = PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)
            ?? PersonaStore.mePseudoPersona

        return HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            Text("PERSONA")
                .font(ElevenLabsBrand.Typography.eyebrow)
                .tracking(0.4)
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

            Spacer()

            Button(action: { isPersonaPickerPresented.toggle() }) {
                HStack(spacing: 8) {
                    PersonaAvatarView(
                        avatar: activePersonaBundle.avatar,
                        diameter: 22
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
            }
            .buttonStyle(InteractivePressStyle(pressScale: 0.96))
            .fixedSize()
            .pointerCursor()
            .popover(
                isPresented: $isPersonaPickerPresented,
                arrowEdge: .top
            ) {
                personaPickerContent(activePersonaID: activePersonaBundle.id)
            }
        }
        .padding(.horizontal, ElevenLabsBrand.Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(
                    isHoveringPersonaCard
                        ? ElevenLabsBrand.Colors.paperRecessed
                        : ElevenLabsBrand.Colors.card
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(
                    isHoveringPersonaCard
                        ? ElevenLabsBrand.Colors.inkTertiary.opacity(0.4)
                        : ElevenLabsBrand.Colors.hairline,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHoveringPersonaCard = hovering }
        .animation(.easeOut(duration: 0.16), value: isHoveringPersonaCard)
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
                    .fill(ElevenLabsBrand.Colors.tasteAccent)
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

    /// Opens the system save panel pointing at TASTE.md and writes the
    /// user's personal taste profile as markdown. Shares its renderer
    /// with the Dashboard Profile tab so the file format is identical
    /// regardless of which surface kicked off the export.
    private func exportPersonalTasteAsMarkdownFromMiniPanel() {
        let personalProfile: TasteProfile = {
            do {
                return try TasteProfileStore.loadProfile()
            } catch {
                return TasteProfile(userId: PersonaStore.myPersonaId, principles: [], updatedAt: Date())
            }
        }()
        let localBundle = PersonaStore.myOwnBundle
        DashboardTasteMarkdownExporter.exportPersonalProfileAsMarkdown(
            personalProfile,
            displayName: localBundle?.displayName ?? "Me",
            role: localBundle?.role,
            accentHex: localBundle?.accentColorHex,
            voiceId: localBundle?.voiceId
        )
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

            // Footer is two clear zones separated by a flexible spacer:
            // left = model picker (the only knob the user might toggle
            // mid-session); right = identity (signed-in chip) + a small
            // dot separator + Quit. The dot prevents the chip and Quit
            // from blurring into one ambiguous text run.
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                modelFooterMenu

                Spacer()

                signedInUserChip

                Circle()
                    .fill(ElevenLabsBrand.Colors.hairline)
                    .frame(width: 3, height: 3)

                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            isHoveringQuitButton
                                ? ElevenLabsBrand.Colors.ink
                                : ElevenLabsBrand.Colors.inkTertiary
                        )
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.94))
                .pointerCursor()
                .nativeTooltip("Quit Sticky")
                .onHover { hovering in isHoveringQuitButton = hovering }
                .animation(.easeOut(duration: 0.14), value: isHoveringQuitButton)
            }
            .padding(.horizontal, ElevenLabsBrand.Spacing.md)
            .padding(.vertical, 10)
        }
    }

    /// Tiny "signed in as X" chip in the footer — clicking opens the
    /// dashboard's Profile tab where the user can actually edit their
    /// identity / sign out. Pulls live from the shared mock auth
    /// state so signing out from the dashboard collapses this chip
    /// the next time the panel re-opens.
    @ViewBuilder
    private var signedInUserChip: some View {
        if dashboardMockAuthState.isSignedIn {
            Button(action: {
                DashboardNavigationState.shared.selectedSection = .profile
                MenuBarPanelManager.shared?.openDashboardWindow(focusedPersonaId: nil)
            }) {
                HStack(spacing: 6) {
                    miniSignedInAvatar

                    Text(dashboardMockAuthState.displayName)
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
            PersonaAvatarView(avatar: localBundle.avatar, diameter: 16)
        } else {
            Circle()
                .fill(ElevenLabsBrand.Colors.gradientSky)
                .frame(width: 16, height: 16)
        }
    }

    /// Compact model picker living in the footer. Re-skinned to read
    /// in human terms ("Fast thinker / Balanced / Deep thinker") with
    /// a small shape glyph that matches each model's character — a
    /// triangle for fast, a circle for balanced, a four-point star
    /// for deep. The Claude model id stays the source of truth on
    /// `companionManager.selectedModel`; only the label and glyph
    /// change.
    private var modelFooterMenu: some View {
        let currentModelKind = ModelPickerKind.fromClaudeModelId(companionManager.selectedModel)

        return Menu {
            ForEach(ModelPickerKind.allCases, id: \.self) { modelKind in
                Button(action: {
                    companionManager.setSelectedModel(modelKind.claudeModelId)
                }) {
                    Text("\(modelKind.glyphCharacter)  \(modelKind.shortLabel) — \(modelKind.descriptor)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Explicit "Model" prefix so the footer control reads as
                // "Model: Balanced ▾" instead of two abstract glyphs that
                // gave no hint of what the dropdown changed.
                Text("Model")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .textCase(.uppercase)
                Text(currentModelKind.glyphCharacter)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(currentModelKind.shortLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(
                        isHoveringModelMenu
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkSecondary
                    )
                    .rotationEffect(.degrees(isHoveringModelMenu ? 180 : 0))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    isHoveringModelMenu
                        ? ElevenLabsBrand.Colors.paperRecessed
                        : Color.clear
                )
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .nativeTooltip("Switch the Claude model that powers Sticky")
        .onHover { hovering in isHoveringModelMenu = hovering }
        .animation(.easeOut(duration: 0.18), value: isHoveringModelMenu)
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

// MARK: - Navigation Tile
//
// One tile in the Chat / Memory / Dashboard rail. Encapsulates hover
// state so each tile can independently lift on hover without the
// parent view tracking three booleans. On hover the card swaps from
// `card` → `paperRecessed`, the hairline thickens slightly, and the
// whole tile lifts on a small scale — the same press style on tap.
private struct NavigationTile: View {
    let iconSymbol: String
    let title: String
    let tooltip: String
    let action: () -> Void
    let trailingAccessory: AnyView?

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(isHovering
                          ? ElevenLabsBrand.Colors.paperRecessed
                          : ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(
                        isHovering
                            ? ElevenLabsBrand.Colors.inkTertiary.opacity(0.4)
                            : ElevenLabsBrand.Colors.hairline,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let trailingAccessory {
                    trailingAccessory
                        .padding(4)
                }
            }
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.97))
        .pointerCursor()
        .nativeTooltip(tooltip)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

// MARK: - Memory Export Accessory Button
//
// Small download glyph pinned to the Memory tile. Owns its own hover
// state so the icon + circular well darken when the user is targeting
// it directly, even if the Memory tile around it is also hovered.
private struct MemoryExportAccessoryButton: View {
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    isHovering
                        ? ElevenLabsBrand.Colors.ink
                        : ElevenLabsBrand.Colors.inkTertiary
                )
                .padding(5)
                .background(
                    Circle().fill(
                        isHovering
                            ? ElevenLabsBrand.Colors.hairline
                            : ElevenLabsBrand.Colors.paperRecessed
                    )
                )
                .contentShape(Circle())
                .scaleEffect(isHovering ? 1.08 : 1.0)
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.88))
        .pointerCursor()
        .nativeTooltip("Export your taste as TASTE.md")
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.14), value: isHovering)
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
                PersonaAvatarView(avatar: persona.avatar, diameter: 28)

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
