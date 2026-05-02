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

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @State private var emailInput: String = ""
    /// Whether the custom voice picker popover is open. Anchored to the
    /// trigger button in `voicePickerRow`.
    @State private var isVoicePickerOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
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

                tasteModePickerRow
                    .padding(.horizontal, 16)

                tasteScopePickerRow
                    .padding(.horizontal, 16)

                if companionManager.tasteMode == .teach {
                    teachingPersonaPickerRow
                        .padding(.horizontal, 16)

                    teachSessionControlRow
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }

                if !companionManager.pendingAmbiguousMoments.isEmpty {
                    ReviewCardStack(companionManager: companionManager)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                } else if companionManager.lastTeachSessionSavedPrincipleCount > 0
                    && companionManager.teachSessionState == .idle {
                    teachSessionSavedSummary
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                if companionManager.tasteMode == .apply,
                   let applyStatusSummary = companionManager.lastApplyEngineStatusSummary {
                    tasteEngineStatusSummary(text: applyStatusSummary)
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

            // Show Clicky toggle — hidden for now
            // if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            //     Spacer()
            //         .frame(height: 16)
            //
            //     showClickyCursorToggleRow
            //         .padding(.horizontal, 16)
            // }

            Spacer()
                .frame(height: 12)

            Divider()
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
                    .foregroundColor(Color.primary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Permissions Copy

    @ViewBuilder
    private var permissionsCopySection: some View {
        if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Text("Hold Control+Option to talk.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted && !companionManager.hasSubmittedEmail {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop your email to get started.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.secondary)
                Text("If I keep building this, I'll keep you in the loop.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet Sticky.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            // Permissions were revoked after onboarding — tell user to re-grant
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions needed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.secondary)

                Text("Some permissions were revoked. Grant all four below to keep using Sticky.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Sticky.")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.secondary)

                Text("Grant the permissions below to get started. Nothing runs in the background — Sticky only captures the screen when you press the hotkey.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                        .foregroundColor(Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                                          ? Color.accentColor.opacity(0.4)
                                          : Color.accentColor)
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
                                .fill(Color.accentColor)
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
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                    .foregroundColor(isGranted ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.systemOrange))
                    .frame(width: 16)

                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(NSColor.systemGreen))
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
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
                                    .fill(Color.accentColor)
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
                            .foregroundColor(Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
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
                    .foregroundColor(isGranted ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.systemOrange))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Recording")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.secondary)

                    Text(isGranted
                         ? "Only takes a screenshot when you use the hotkey"
                         : "Quit and reopen after granting")
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(NSColor.systemGreen))
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
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
                                .fill(Color.accentColor)
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
                    .foregroundColor(isGranted ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.systemOrange))
                    .frame(width: 16)

                Text("Screen Content")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(NSColor.systemGreen))
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
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
                                .fill(Color.accentColor)
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
                    .foregroundColor(isGranted ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.systemOrange))
                    .frame(width: 16)

                Text("Microphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(NSColor.systemGreen))
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
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
                                .fill(Color.accentColor)
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
                    .foregroundColor(isGranted ? Color(NSColor.tertiaryLabelColor) : Color(NSColor.systemOrange))
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(NSColor.systemGreen))
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(NSColor.systemGreen))
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
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }



    // MARK: - Show Clicky Cursor Toggle

    private var showClickyCursorToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .frame(width: 16)

                Text("Show Sticky")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isClickyCursorEnabled },
                set: { companionManager.setClickyCursorEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Color.accentColor)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    private var speechToTextProviderRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic.badge.waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .frame(width: 16)

                Text("Speech to Text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            Text(companionManager.buddyDictationManager.transcriptionProviderDisplayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Model Picker

    private var modelPickerRow: some View {
        HStack {
            Text("Model")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.secondary)

            Spacer()

            HStack(spacing: 0) {
                modelOptionButton(label: "Sonnet", modelID: "claude-sonnet-4-6")
                modelOptionButton(label: "Opus", modelID: "claude-opus-4-6")
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                .foregroundColor(Color.secondary)

            Spacer()

            Button(action: { isVoicePickerOpen.toggle() }) {
                HStack(spacing: 4) {
                    Text(triggerLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                orbColor: Color(NSColor.tertiaryLabelColor).opacity(0.6),
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

    /// Hand-tuned palette mapping every free ElevenLabs voice to its own
    /// orb color. Picked so vocal "warmth" tracks color warmth (deep
    /// voices skew indigo/burnt-orange, bright voices skew coral/magenta,
    /// British voices skew muted/cool, etc). Falls back to a neutral
    /// accent if a new voice ID slips in unmapped.
    private static let voiceOrbPalette: [String: Color] = [
        "pNInz6obpgDQGcFmaJgB": Color(red: 0.34, green: 0.30, blue: 0.74), // Adam      — deep indigo
        "Xb7hH8MSUJpSbSDYk0k2": Color(red: 0.18, green: 0.66, blue: 0.65), // Alice     — teal
        "hpp4J3VqNfWAUOO0d1Us": Color(red: 0.96, green: 0.50, blue: 0.55), // Bella     — coral pink
        "pqHfZKP75CvOlQylNhV4": Color(red: 0.78, green: 0.55, blue: 0.20), // Bill      — bronze
        "nPczCjzI2devNBz1zQrb": Color(red: 0.85, green: 0.45, blue: 0.20), // Brian     — burnt orange
        "N2lVS1w4EtoT3dr4eOWO": Color(red: 0.45, green: 0.60, blue: 0.32), // Callum    — moss green
        "IKne3meq5aSn9XLyUdCD": Color(red: 0.16, green: 0.66, blue: 0.45), // Charlie   — emerald
        "iP95p4xoKVk53GoZ742B": Color(red: 0.35, green: 0.66, blue: 0.92), // Chris     — sky blue
        "onwK4e9ZLuTAKqWW03F9": Color(red: 0.40, green: 0.50, blue: 0.65), // Daniel    — slate blue
        "cjVigY5qzO86Huf0OWal": Color(red: 0.18, green: 0.45, blue: 0.32), // Eric      — forest green
        "JBFqnCBsd6RMkjVDRZzb": Color(red: 0.82, green: 0.42, blue: 0.30), // George    — terracotta
        "SOYHLrjzK2X1ezoPC6cr": Color(red: 0.82, green: 0.20, blue: 0.25), // Harry     — crimson
        "cgSgspJ2msm6clMCkdW9": Color(red: 0.86, green: 0.32, blue: 0.62), // Jessica   — magenta
        "FGY2WhTYpPnrIDTdsKH5": Color(red: 0.62, green: 0.36, blue: 0.80), // Laura     — violet
        "TX3LPaxmHKxFdv7VOQHJ": Color(red: 0.95, green: 0.55, blue: 0.18), // Liam      — orange
        "pFZP5JQG7iQjIQuC4Bku": Color(red: 0.70, green: 0.55, blue: 0.78), // Lily      — lavender
        "XrExE9yKIg1WjnnlVkGX": Color(red: 0.88, green: 0.72, blue: 0.25), // Matilda   — mustard
        "SAz9YHcvj6GT2YYXdXww": Color(red: 0.55, green: 0.62, blue: 0.68), // River     — cool steel
        "CwhRBWXzGAHq8TQ4Fs17": Color(red: 0.55, green: 0.58, blue: 0.30), // Roger     — olive
        "EXAVITQu4vr4xnSDxMaL": Color(red: 0.92, green: 0.45, blue: 0.55), // Sarah     — rose
        "bIHbv24MWmeRgasZH58o": Color(red: 0.50, green: 0.65, blue: 0.50), // Will      — sage
    ]

    private static func orbColor(forVoiceID voiceID: String) -> Color {
        return voiceOrbPalette[voiceID] ?? Color.accentColor
    }

    // MARK: - Reverse Clicky: Taste Mode Picker

    private var tasteModePickerRow: some View {
        HStack {
            Text("Mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.secondary)

            Spacer()

            HStack(spacing: 0) {
                ForEach(TasteMode.allCases, id: \.self) { tasteModeOption in
                    tasteModeOptionButton(tasteModeOption: tasteModeOption)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Reverse Clicky: Taste Scope Picker

    private var tasteScopePickerRow: some View {
        HStack {
            Text("Scope")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.secondary)

            Spacer()

            HStack(spacing: 0) {
                tasteScopeOptionButton(scope: .personal, label: "Personal")
                tasteScopeOptionButton(scope: .team, label: "Team")
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                .foregroundColor(isSelected ? Color.primary : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func tasteModeOptionButton(tasteModeOption: TasteMode) -> some View {
        let isSelected = companionManager.tasteMode == tasteModeOption
        // Disable mode switching mid-session so the user can't accidentally
        // throw away an in-progress teach session by tapping Apply.
        let isDisabled = companionManager.teachSessionState != .idle
            && companionManager.tasteMode != tasteModeOption

        return Button(action: {
            companionManager.setTasteMode(tasteModeOption)
        }) {
            Text(tasteModeOption.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Color.primary : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    private var teachingPersonaPickerRow: some View {
        HStack {
            Text("Teacher")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.secondary)

            Spacer()

            HStack(spacing: 0) {
                ForEach(TasteTeachingPersona.allCases, id: \.self) { teachingPersona in
                    teachingPersonaOptionButton(teachingPersona: teachingPersona)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }

    private func teachingPersonaOptionButton(teachingPersona: TasteTeachingPersona) -> some View {
        let isSelected = companionManager.selectedTeachingPersona == teachingPersona
        let isDisabled = companionManager.teachSessionState != .idle

        return Button(action: {
            companionManager.setSelectedTeachingPersona(teachingPersona)
        }) {
            Text(teachingPersona.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Color.primary : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
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
                    .foregroundColor(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                // Pulsing red dot to make it obvious the mic is open
                Circle()
                    .fill(Color(NSColor.systemRed))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(NSColor.systemRed).opacity(0.6), radius: 4)

                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.primary)

                Spacer()

                Text(formatTeachSessionElapsed(companionManager.teachSessionElapsedSeconds))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                .foregroundColor(Color.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color.primary.opacity(0.06))
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

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(NSColor.systemGreen))

                Text("Saved \(savedCount) new \(principleNoun) to \(companionManager.selectedTeachingPersona.displayName)'s taste")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.secondary)

            Spacer()
            }

            if let teachStatusSummary = companionManager.lastTeachEngineStatusSummary {
                Text(teachStatusSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color(NSColor.systemGreen).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .stroke(Color(NSColor.systemGreen).opacity(0.3), lineWidth: 0.5)
        )
    }

    private func tasteEngineStatusSummary(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(NSColor.systemGreen))

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.secondary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func modelOptionButton(label: String, modelID: String) -> some View {
        let isSelected = companionManager.selectedModel == modelID
        return Button(action: {
            companionManager.setSelectedModel(modelID)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Color.primary : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
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
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if companionManager.hasCompletedOnboarding {
                Spacer()

                Button(action: {
                    companionManager.replayOnboarding()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text("Watch Onboarding Again")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
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
            return Color(NSColor.tertiaryLabelColor)
        }
        switch companionManager.voiceState {
        case .idle:
            return Color(NSColor.systemGreen)
        case .listening:
            return Color(NSColor.systemBlue)
        case .processing, .responding:
            return Color(NSColor.systemBlue)
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
        Button(action: onSelect) {
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
                        .foregroundColor(Color.accentColor)
                }

                previewButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
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
                        .fill(isPreviewing ? Color(NSColor.systemRed) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .nativeTooltip(isPreviewing ? "Stop preview" : "Preview voice")
    }
}

