//
//  CompanionPanelView.swift
//  leanring-buddy
//
//  The SwiftUI content hosted inside the menu bar panel. Shows the companion
//  voice status, push-to-talk shortcut, and quick settings. Designed to feel
//  like Loom's recording panel — dark, rounded, minimal, and special.
//

import AVFoundation
import SwiftUI

// MARK: - Warm Dropdown Palette

/// Warm, painterly color palette used throughout the dropdown to match
/// the walnut→rust gradient + amber glow background. These colors are
/// deliberately *not* tied to the system appearance: the dropdown is
/// always rendered in the warm aesthetic regardless of light/dark mode.
enum WarmPalette {
    /// Soft cream — primary headline text on the warm surface.
    static let textPrimary = Color(red: 1.00, green: 0.94, blue: 0.86)
    /// Warm peach — body / secondary copy.
    static let textSecondary = Color(red: 0.93, green: 0.78, blue: 0.59)
    /// Muted faded peach — tertiary captions, status text, icon tints.
    static let textTertiary = Color(red: 0.78, green: 0.58, blue: 0.40)
    /// Amber accent — buttons, selected pills, focus states.
    static let accent = Color(red: 1.00, green: 0.62, blue: 0.18)
    /// Slight cream overlay — used as subtle row / chip fills on the
    /// gradient. `Color.primary.opacity` would resolve to the system
    /// label color which would break the warm look in light mode.
    static let surfaceTint = Color(red: 1.00, green: 0.94, blue: 0.86).opacity(0.10)
    /// Stronger cream overlay — used for selected state in segmented
    /// pickers (Sonnet/Opus, Personal/Team) so the chosen pill stands
    /// out clearly against the warm gradient.
    static let surfaceTintStrong = Color(red: 1.00, green: 0.94, blue: 0.86).opacity(0.18)
    /// Faint amber hairline — dividers, button outlines.
    static let separator = Color(red: 1.00, green: 0.66, blue: 0.32).opacity(0.22)
    /// Status dot color when "good" — keeps a green hue but warmed
    /// toward lime so it doesn't clash with the rust background.
    static let statusGood = Color(red: 0.62, green: 0.86, blue: 0.40)
    /// Status dot / row icon color when warning attention is needed.
    static let warning = Color(red: 1.00, green: 0.74, blue: 0.20)
}

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @State private var emailInput: String = ""
    /// Whether the custom voice picker popover is open. Anchored to the
    /// trigger button in `voicePickerRow`.
    @State private var isVoicePickerOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Rectangle()
                .fill(WarmPalette.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            permissionsCopySection
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 12)

                modelPickerRow
                    .padding(.horizontal, 16)

                voicePickerRow
                    .padding(.horizontal, 16)

                // Scope picker — Personal vs Team taste. Always visible
                // because every voice question now has the saved taste
                // profile prepended to the system prompt; the user picks
                // here whether that means just their own principles or
                // their personal principles unioned with the team's.
                tasteScopePickerRow
                    .padding(.horizontal, 16)

                personaPickerRow
                    .padding(.horizontal, 16)

                teachSessionControlRow
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                if let pendingTeachSessionReview = companionManager.pendingTeachSessionResult {
                    TeachSessionResultCard(
                        companionManager: companionManager,
                        pendingReview: pendingTeachSessionReview
                    )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                } else if !companionManager.pendingAmbiguousMoments.isEmpty {
                    ReviewCardStack(companionManager: companionManager)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                } else if companionManager.lastTeachSessionSavedPrincipleCount > 0
                    && companionManager.teachSessionState == .idle {
                    teachSessionSavedSummary
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }

            if !companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                settingsSection
                    .padding(.horizontal, 16)
            }

            if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                startButton
                    .padding(.horizontal, 16)
            }

            // Show Sticky toggle — hidden for now
            // if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            //     Spacer()
            //         .frame(height: 16)
            //
            //     showStickyCursorToggleRow
            //         .padding(.horizontal, 16)
            // }

            // "View Library" row — gated on onboarding+permissions so we
            // don't tempt the user into the library before they've granted
            // microphone/screen-recording (the library is empty anyway).
            if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                tasteLibraryRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            Spacer()
                .frame(height: 12)

            Rectangle()
                .fill(WarmPalette.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(panelBackground)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            HStack(spacing: 8) {
                // Animated status dot
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusDotColor.opacity(0.6), radius: 4)

                Text("Sticky")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmPalette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Permissions Copy

    @ViewBuilder
    private var permissionsCopySection: some View {
        if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Text(modeAwareTopInstructionCopy)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted && !companionManager.hasSubmittedEmail {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop your email to get started.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
                Text("If I keep building this, I'll keep you in the loop.")
                    .font(.system(size: 11))
                    .foregroundColor(WarmPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet Sticky.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            // Permissions were revoked after onboarding — tell user to re-grant
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions needed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WarmPalette.textSecondary)

                Text("Some permissions were revoked. Grant all four below to keep using Sticky.")
                    .font(.system(size: 11))
                    .foregroundColor(WarmPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Sticky.")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WarmPalette.textSecondary)

                Text("Grant the permissions below to get started. Nothing runs in the background — Sticky only captures the screen when you press the hotkey.")
                    .font(.system(size: 11))
                    .foregroundColor(WarmPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Email + Start Button

    @ViewBuilder
    private var startButton: some View {
        if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            if !companionManager.hasSubmittedEmail {
                VStack(spacing: 8) {
                    TextField("Enter your email", text: $emailInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(WarmPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .fill(WarmPalette.surfaceTint)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .stroke(WarmPalette.separator, lineWidth: 0.5)
                        )

                    Button(action: {
                        companionManager.submitEmail(emailInput)
                    }) {
                        Text("Submit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                                    .fill(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          ? WarmPalette.accent.opacity(0.4)
                                          : WarmPalette.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .disabled(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button(action: {
                    companionManager.triggerOnboarding()
                }) {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                                .fill(WarmPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }

    // MARK: - Permissions

    private var settingsSection: some View {
        VStack(spacing: 2) {
            Text("Permissions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(WarmPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            microphonePermissionRow

            accessibilityPermissionRow

            screenRecordingPermissionRow

            if companionManager.hasScreenRecordingPermission {
                screenContentPermissionRow
            }

        }
    }

    private var accessibilityPermissionRow: some View {
        let isGranted = companionManager.hasAccessibilityPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? WarmPalette.textTertiary : WarmPalette.warning)
                    .frame(width: 16)

                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WarmPalette.statusGood)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.statusGood)
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: {
                        // Triggers the system accessibility prompt (AXIsProcessTrustedWithOptions)
                        // on first attempt, then opens System Settings on subsequent attempts.
                        WindowPositionManager.requestAccessibilityPermission()
                    }) {
                        Text("Grant")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(WarmPalette.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()

                    Button(action: {
                        // Reveals the app in Finder so the user can drag it into
                        // the Accessibility list if it doesn't appear automatically
                        // (common with unsigned dev builds).
                        WindowPositionManager.revealAppInFinder()
                        WindowPositionManager.openAccessibilitySettings()
                    }) {
                        Text("Find App")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WarmPalette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .stroke(WarmPalette.separator, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var screenRecordingPermissionRow: some View {
        let isGranted = companionManager.hasScreenRecordingPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? WarmPalette.textTertiary : WarmPalette.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Recording")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(WarmPalette.textSecondary)

                    Text(isGranted
                         ? "Only takes a screenshot when you use the hotkey"
                         : "Quit and reopen after granting")
                        .font(.system(size: 10))
                        .foregroundColor(WarmPalette.textTertiary)
                }
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WarmPalette.statusGood)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.statusGood)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS screen recording prompt on first
                    // attempt (auto-adds app to the list), then opens System Settings
                    // on subsequent attempts.
                    WindowPositionManager.requestScreenRecordingPermission()
                }) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WarmPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private var screenContentPermissionRow: some View {
        let isGranted = companionManager.hasScreenContentPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? WarmPalette.textTertiary : WarmPalette.warning)
                    .frame(width: 16)

                Text("Screen Content")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WarmPalette.statusGood)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.statusGood)
                }
            } else {
                Button(action: {
                    companionManager.requestScreenContentPermission()
                }) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WarmPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private var microphonePermissionRow: some View {
        let isGranted = companionManager.hasMicrophonePermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? WarmPalette.textTertiary : WarmPalette.warning)
                    .frame(width: 16)

                Text("Microphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WarmPalette.statusGood)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.statusGood)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS microphone permission dialog on
                    // first attempt. If already denied, opens System Settings.
                    let status = AVCaptureDevice.authorizationStatus(for: .audio)
                    if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WarmPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private func permissionRow(
        label: String,
        iconName: String,
        isGranted: Bool,
        settingsURL: String
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? WarmPalette.textTertiary : WarmPalette.warning)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WarmPalette.statusGood)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.statusGood)
                }
            } else {
                Button(action: {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WarmPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }



    // MARK: - Show Sticky Cursor Toggle

    private var showStickyCursorToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(WarmPalette.textTertiary)
                    .frame(width: 16)

                Text("Show Sticky")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isClickyCursorEnabled },
                set: { companionManager.setClickyCursorEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(WarmPalette.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    private var speechToTextProviderRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic.badge.waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(WarmPalette.textTertiary)
                    .frame(width: 16)

                Text("Speech to Text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WarmPalette.textSecondary)
            }

            Spacer()

            Text(companionManager.buddyDictationManager.transcriptionProviderDisplayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(WarmPalette.textTertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Model Picker

    private var modelPickerRow: some View {
        HStack {
            Text("Model")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()

            HStack(spacing: 0) {
                // Haiku first because it's the new default — fastest TTFT,
                // most appropriate for short voice replies. Sonnet/Opus are
                // there for users who want higher-quality answers at the
                // cost of a noticeable latency bump.
                modelOptionButton(label: "Haiku", modelID: "claude-haiku-4-5-20251001")
                modelOptionButton(label: "Sonnet", modelID: "claude-sonnet-4-6")
                modelOptionButton(label: "Opus", modelID: "claude-opus-4-6")
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(WarmPalette.surfaceTint.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(WarmPalette.separator, lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Voice Picker

    /// Lets the user pick which ElevenLabs voice Sticky uses for spoken
    /// replies. Tapping the trigger opens a Mac-style popover listing the
    /// free default voices; each row has a play button that previews the
    /// voice with a "Hey, I'm Sticky!" clip so the user can test before
    /// committing. Tapping the row body commits the selection. "Default"
    /// leaves selection unset, falling back to the bundled
    /// `ELEVENLABS_VOICE_ID` from secrets.plist.
    private var voicePickerRow: some View {
        let voices = ElevenLabsTTSClient.freeVoices
        let selectedVoice = voices.first { $0.id == companionManager.selectedVoiceID }
        let triggerLabel = selectedVoice?.displayName ?? "Default"

        return HStack {
            Text("Voice")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()

            Button(action: {
                isVoicePickerOpen.toggle()
                if isVoicePickerOpen {
                    // Warm the disk cache the first time the dropdown
                    // opens so subsequent play taps are instant.
                    companionManager.prefetchAllVoicePreviewsIfNeeded()
                }
            }) {
                HStack(spacing: 4) {
                    Text(triggerLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WarmPalette.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(WarmPalette.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WarmPalette.surfaceTint.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WarmPalette.separator, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .macDropdown(isPresented: $isVoicePickerOpen, width: 320, arrowEdge: .top) {
                // Cap height so the 22-row list scrolls instead of pushing
                // the popover taller than the screen on smaller displays.
                ScrollView(.vertical, showsIndicators: true) {
                    voicePickerPopover(voices: voices)
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(.vertical, 4)
    }

    /// Body of the voice picker popover. Default row at the top, then the
    /// alphabetized list of free voices. Each row has a colored orb
    /// hand-mapped to that voice and a play/stop button to preview
    /// without committing.
    @ViewBuilder
    private func voicePickerPopover(voices: [ElevenLabsFreeVoice]) -> some View {
        DropdownSection("Sticky's voice", showsBottomDivider: true) {
            VoicePickerOrbRow(
                title: "Default",
                subtitle: "Bundled with Sticky",
                orbColor: CompanionManager.stickyDefaultVoiceColor,
                isSelected: companionManager.selectedVoiceID == nil,
                isPreviewing: companionManager.previewingVoiceID == CompanionManager.defaultVoicePreviewSentinel,
                onSelect: {
                    companionManager.setSelectedVoiceID(nil)
                    isVoicePickerOpen = false
                },
                onPreviewToggle: {
                    if companionManager.previewingVoiceID == CompanionManager.defaultVoicePreviewSentinel {
                        companionManager.stopVoicePreview()
                    } else {
                        companionManager.previewVoice(nil)
                    }
                }
            )
        }

        DropdownSection(showsBottomDivider: false) {
            ForEach(voices) { voice in
                VoicePickerOrbRow(
                    title: voice.displayName,
                    subtitle: voice.descriptor,
                    orbColor: Self.orbColor(forVoiceID: voice.id),
                    isSelected: companionManager.selectedVoiceID == voice.id,
                    isPreviewing: companionManager.previewingVoiceID == voice.id,
                    onSelect: {
                        companionManager.setSelectedVoiceID(voice.id)
                        isVoicePickerOpen = false
                    },
                    onPreviewToggle: {
                        if companionManager.previewingVoiceID == voice.id {
                            companionManager.stopVoicePreview()
                        } else {
                            companionManager.previewVoice(voice.id)
                        }
                    }
                )
            }
        }
    }

    /// Voice picker orbs reuse the same palette as Sticky's overlay
    /// chrome so the color you preview here matches what you see in the
    /// overlay when Sticky talks back. Lives on `CompanionManager`.
    private static func orbColor(forVoiceID voiceID: String) -> Color {
        return CompanionManager.voiceColor(forVoiceID: voiceID)
    }

    // MARK: - Reverse Clicky: Persona Picker
    //
    // Surface for the active persona ("who Sticky is wearing right now")
    // plus a discoverability hint about the hold-shift-cmd radial wheel.
    // Tapping the row also opens a flat list as a fallback for users who
    // can't or won't learn the hotkey gesture.

    private var personaPickerRow: some View {
        let activePersonaBundle = PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)
            ?? PersonaStore.mePseudoPersona

        return HStack(spacing: 10) {
            Text("Wearing")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()

            // Native SwiftUI Menu — works reliably inside the non-
            // activating menu-bar NSPanel where the previous custom
            // .popover wasn't getting a chance to display. The trigger
            // label keeps the warm chip aesthetic; the dropdown itself
            // renders as a system menu so the user can always pick a
            // persona without learning the ⇧⌘ wheel hotkey.
            Menu {
                ForEach(PersonaStore.allWheelPersonas, id: \.id) { persona in
                    personaMenuItem(persona: persona)
                }
            } label: {
                HStack(spacing: 8) {
                    PersonaAvatarView(
                        avatar: activePersonaBundle.avatar,
                        diameter: 22
                    )
                    Text(activePersonaBundle.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(WarmPalette.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(WarmPalette.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WarmPalette.surfaceTint.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WarmPalette.separator, lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerCursor()
            .nativeTooltip("hold ⇧⌘ to summon the persona wheel around your cursor")
        }
        .padding(.vertical, 4)
    }

    /// One row inside the persona menu. Native Menu items don't render
    /// multi-line labels or thumbnails, so the role appears as an em-
    /// dashed suffix and the active selection gets a leading checkmark
    /// (using the standard `Label(_:systemImage:)` pattern macOS menus
    /// expect for "currently selected").
    private func personaMenuItem(persona: PersonaBundle) -> some View {
        let isCurrentlyActive = (PersonaStore.wheelPersonaForSelection(companionManager.personaSelection)?.id ?? "") == persona.id

        let menuLabel: String = {
            if let role = persona.role, !role.isEmpty {
                return "\(persona.displayName) — \(role)"
            }
            return persona.displayName
        }()

        return Button(action: {
            companionManager.setPersonaSelection(PersonaStore.selectionForWheelPersona(persona))
        }) {
            if isCurrentlyActive {
                Label(menuLabel, systemImage: "checkmark")
            } else {
                Text(menuLabel)
            }
        }
    }

    // MARK: - Reverse Clicky: Mode-Aware Copy

    /// Top-of-panel push-to-talk instruction. Hold-to-talk is the same
    /// for ask and teach (teach has its own dedicated button below the
    /// scope picker), so we keep this copy single-track.
    private var modeAwareTopInstructionCopy: String {
        return "Hold Control+Option to talk."
    }

    // MARK: - Reverse Clicky: Taste Scope Picker

    private var tasteScopePickerRow: some View {
        HStack {
            Text("Scope")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()

            HStack(spacing: 0) {
                tasteScopeOptionButton(scope: .personal, label: "Personal")
                tasteScopeOptionButton(scope: .team, label: "Team")
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(WarmPalette.surfaceTint.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(WarmPalette.separator, lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }

    private func tasteScopeOptionButton(scope: TasteScope, label: String) -> some View {
        let isSelected = companionManager.tasteScope == scope
        return Button(action: {
            companionManager.setTasteScope(scope)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? WarmPalette.textPrimary : WarmPalette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? WarmPalette.surfaceTintStrong : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Reverse Clicky: Teach Session Controls

    @ViewBuilder
    private var teachSessionControlRow: some View {
        switch companionManager.teachSessionState {
        case .idle:
            teachSessionStartButton
        case .recording:
            teachSessionRecordingControls
        case .analyzing:
            teachSessionAnalyzingRow
        }
    }

    // MARK: - Reverse Clicky: Taste Library

    /// "View Library" row that opens the Sticky Memory window. Styled
    /// like `teachSessionStartButton` so the two sit comfortably together
    /// at the bottom of the panel — same warm cream tint, same medium
    /// corner radius, same icon-then-label layout.
    private var tasteLibraryRow: some View {
        Button(action: {
            // The menu bar panel is the only place this button lives, so
            // we route through `MenuBarPanelManager.shared` to open the
            // window. If the manager hasn't been wired yet (shouldn't
            // happen at runtime), the no-op is the safe fallback.
            MenuBarPanelManager.shared?.openTasteLibraryWindow(
                companionManager: companionManager
            )
        }) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)
                Text("View Library")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(WarmPalette.surfaceTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(WarmPalette.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .nativeTooltip("See every principle Sticky has learned")
    }

    private var teachSessionStartButton: some View {
        Button(action: {
            companionManager.startTeachSession()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(NSColor.systemRed))
                Text("Start Teach Session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(WarmPalette.surfaceTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(WarmPalette.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var teachSessionRecordingControls: some View {
        Button(action: {
            companionManager.stopTeachSession()
        }) {
            HStack(spacing: 8) {
                // Square stop glyph instead of a red dot — the start button
                // already uses a red dot ("begin recording"), so reusing the
                // same affordance for "stop" was visually ambiguous. The
                // SF Symbol stop.fill reads unambiguously as a stop control.
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)

                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WarmPalette.textPrimary)

                Spacer()

                // Elapsed duration is the most important live signal during a
                // teach session — bumped to primary text + monospaced semibold
                // so it carries the weight it deserves instead of fading into
                // the panel as tertiary metadata.
                Text(formatTeachSessionElapsed(companionManager.teachSessionElapsedSeconds))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(WarmPalette.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color(NSColor.systemRed).opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(Color(NSColor.systemRed).opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var teachSessionAnalyzingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)

            Text("Reviewing your decisions…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(WarmPalette.surfaceTint.opacity(0.6))
        )
    }

    private func formatTeachSessionElapsed(_ elapsedSeconds: Int) -> String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Subtle confirmation toast shown after a teach session if at least one
    /// confident principle was auto-saved. Stays until the next teach session
    /// starts. Hidden during recording/analysing so it doesn't compete with
    /// the live controls.
    private var teachSessionSavedSummary: some View {
        let savedCount = companionManager.lastTeachSessionSavedPrincipleCount
        let principleNoun = savedCount == 1 ? "principle" : "principles"

        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmPalette.statusGood)

            Text("Saved \(savedCount) new \(principleNoun) to your taste")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(WarmPalette.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(WarmPalette.statusGood.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .stroke(WarmPalette.statusGood.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func modelOptionButton(label: String, modelID: String) -> some View {
        let isSelected = companionManager.selectedModel == modelID
        return Button(action: {
            companionManager.setSelectedModel(modelID)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? WarmPalette.textPrimary : WarmPalette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? WarmPalette.surfaceTintStrong : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .medium))
                    Text("Quit Sticky")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(WarmPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()

        }
    }

    // MARK: - Visual Helpers

    private var panelBackground: some View {
        // The actual translucent material, rounded mask, and hairline
        // border are owned by the panel's `NSVisualEffectView` content
        // view in `MenuBarPanelManager`. The SwiftUI background is
        // therefore fully transparent so it doesn't paint anything on
        // top of the AppKit material.
        Color.clear
    }

    private var statusDotColor: Color {
        if !companionManager.isOverlayVisible {
            return WarmPalette.textTertiary
        }
        switch companionManager.voiceState {
        case .idle:
            return WarmPalette.statusGood
        case .listening:
            return WarmPalette.accent
        case .processing, .responding:
            return WarmPalette.accent
        }
    }

    private var statusText: String {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return "Setup"
        }
        if !companionManager.isOverlayVisible {
            return "Ready"
        }
        switch companionManager.voiceState {
        case .idle:
            return "Active"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .responding:
            return "Responding"
        }
    }

}

// MARK: - Voice Picker Orb Row

/// One row inside the voice picker popover. Renders a colored gradient
/// orb on the leading edge so each voice has its own visual identity,
/// the title and descriptor in the middle, an optional checkmark when
/// the voice is currently selected, and a play/stop button for
/// previewing without committing the selection.
///
/// Mirrors the layout/hover behavior of `DropdownRow` from the design
/// system, but `DropdownRow`'s leading slot is an SF Symbol in a tinted
/// circle — not the orb-style well we want here — so we don't reuse it.
private struct VoicePickerOrbRow: View {
    let title: String
    let subtitle: String
    let orbColor: Color
    let isSelected: Bool
    let isPreviewing: Bool
    let onSelect: () -> Void
    let onPreviewToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Intentionally NOT wrapped in a Button. SwiftUI doesn't route
        // taps reliably between a parent `Button` and a child `Button`
        // — the parent ends up capturing the play button's tap, which
        // would commit the selection and dismiss the popover whenever
        // the user just wanted to preview. Using `.onTapGesture` on the
        // row + a real `Button` for the play control lets the inner
        // button consume its own taps cleanly.
        HStack(spacing: 10) {
            voiceOrb

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(WarmPalette.accent)
            }

            previewButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? WarmPalette.surfaceTint : .clear)
        )
        .padding(.horizontal, 6)
        // Hit area for "select this voice" — the play button sits on
        // top of this and intercepts its own tap area before it reaches
        // the gesture.
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .pointerCursor()
        .onHover { hovering in isHovering = hovering }
    }

    /// Glossy gradient orb that gives each voice its own visual identity.
    /// A radial highlight in the upper-left + a hairline white edge sells
    /// the "physical sphere" feel against the dark menu material. Sized
    /// to 28pt so it lines up with `DropdownRow`'s standard icon-well
    /// slot — keeps the row height consistent with other panel sections.
    private var voiceOrb: some View {
        ZStack {
            // Soft outer glow — only visible against the translucent
            // dark menu material; on light backgrounds it fades to
            // nearly nothing, which is fine.
            Circle()
                .fill(orbColor.opacity(0.32))
                .frame(width: 30, height: 30)
                .blur(radius: 4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            orbColor.opacity(1.0),
                            orbColor.opacity(0.78),
                            orbColor.opacity(0.62)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 1,
                        endRadius: 16
                    )
                )
                .frame(width: 22, height: 22)
                .overlay(
                    // Specular highlight + hairline edge sell the orb as
                    // a physical sphere instead of a flat disc.
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                        .frame(width: 9, height: 6)
                        .offset(x: -3.5, y: -4)
                        .blur(radius: 1)
                )
        }
        .frame(width: 28, height: 28)
    }

    private var previewButton: some View {
        Button(action: onPreviewToggle) {
            Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isPreviewing ? Color(NSColor.systemRed) : WarmPalette.accent)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .nativeTooltip(isPreviewing ? "Stop preview" : "Preview voice")
    }
}

