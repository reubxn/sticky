//
//  DashboardSettingsView.swift
//  leanring-buddy
//
//  "Settings" tab — app preferences. The model picker, the Sticky
//  cursor toggle, the push-to-talk hotkey reference (read-only, the
//  hackathon doesn't ship rebinding), and a couple of mocked toggles
//  for the demo (analytics, login at startup). Settings persist to
//  the same UserDefaults keys CompanionManager uses, so flipping
//  them here is a real change the live companion picks up next time
//  it reads the key.
//

import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var companionManager: CompanionManager

    /// Sticky cursor toggle — same key as
    /// `CompanionManager.isClickyCursorEnabled`.
    @State private var isClickyCursorEnabled: Bool = UserDefaults.standard
        .object(forKey: "isClickyCursorEnabled") as? Bool ?? true

    /// Mocked: launch at login. Real launch-at-login already
    /// registers via SMAppService at startup; this toggle is just
    /// a UI placeholder for the dashboard surface.
    @State private var isLaunchAtLoginEnabled: Bool = UserDefaults.standard
        .bool(forKey: "dashboardMockLaunchAtLogin")

    /// Live observer of the global ThemeManager so the appearance card
    /// reflects the active mode and writing it back here propagates
    /// instantly to every other surface (menu bar panel, chat window,
    /// dashboard chrome).
    @ObservedObject private var themeManager = ThemeManager.shared


    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "SETTINGS",
                title: "Sticky preferences.",
                subtitle: "Tune the model, the cursor, and the demo toggles. Changes persist."
            )

            appearanceCard

            modelPickerCard

            cursorAndHotkeyCard

            otherPreferencesCard
        }
    }

    // MARK: - Appearance card

    /// Three-way segmented picker for light / dark / system. Mirrors
    /// the menu bar panel's footer popover but laid out as a full-width
    /// card to match the rest of the settings page.
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("APPEARANCE")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text("Sticky defaults to your macOS system appearance. Pick a side to override it.")
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                appearanceSegmentedPicker
            }
            .padding(ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
    }

    /// Three side-by-side chips that read like a segmented control.
    /// We hand-roll it (instead of using SwiftUI's `Picker(.segmented)`)
    /// because the native segmented control doesn't honor the
    /// paper-and-ink palette under custom appearances.
    private var appearanceSegmentedPicker: some View {
        HStack(spacing: 6) {
            ForEach(AppThemeMode.allCases) { themeMode in
                appearanceSegment(themeMode: themeMode)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func appearanceSegment(themeMode: AppThemeMode) -> some View {
        let isSelected = themeManager.mode == themeMode
        return Button(action: {
            themeManager.mode = themeMode
        }) {
            HStack(spacing: 6) {
                Image(systemName: themeMode.sfSymbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(themeMode.displayLabel)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(
                isSelected
                    ? ElevenLabsBrand.Colors.ink
                    : ElevenLabsBrand.Colors.inkSecondary
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? ElevenLabsBrand.Colors.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected
                            ? ElevenLabsBrand.Colors.hairline
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.96))
        .pointerCursor()
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    // MARK: - Model picker card

    private var modelPickerCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("MODEL")

            VStack(spacing: 6) {
                ForEach(ModelPickerKind.allCases, id: \.self) { modelKind in
                    modelPickerRow(modelKind: modelKind)
                }
            }
            .padding(ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
    }

    private func modelPickerRow(modelKind: ModelPickerKind) -> some View {
        let isSelected = (modelKind.modelId == companionManager.selectedModel)
        return Button(action: {
            companionManager.setSelectedModel(modelKind.modelId)
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                Text(modelKind.glyphCharacter)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkSecondary
                    )
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(modelKind.longLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                    Text(modelKind.descriptor)
                        .font(.system(size: 11))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ElevenLabsBrand.Colors.paperRecessed : Color.clear)
            )
        }
        .buttonStyle(InteractivePressStyle(pressScale: 0.98))
        .pointerCursor()
    }

    // MARK: - Cursor / hotkey card

    private var cursorAndHotkeyCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("CURSOR & HOTKEY")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                togglePreferenceRow(
                    title: "Show Sticky cursor",
                    subtitle: "Floating blue cursor follows your real cursor and points at things Sticky references.",
                    binding: $isClickyCursorEnabled,
                    onChange: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "isClickyCursorEnabled")
                    }
                )

                Divider().background(ElevenLabsBrand.Colors.hairline)

                hotkeyReferenceRow
            }
            .padding(ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
    }

    private var hotkeyReferenceRow: some View {
        HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push to talk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text("Hold control + option, speak, release. Same hotkey for ask, teach, and apply modes.")
                    .font(.system(size: 11))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 4) {
                hotkeyKeycap(symbol: "control")
                Text("+").font(.system(size: 10)).foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
                hotkeyKeycap(symbol: "option")
            }
        }
    }

    private func hotkeyKeycap(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(ElevenLabsBrand.Colors.ink)
            .frame(width: 24, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.paperRecessed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
    }

    // MARK: - Other preferences card

    private var otherPreferencesCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("OTHER")

            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
                togglePreferenceRow(
                    title: "Launch at login",
                    subtitle: "Sticky starts automatically when your Mac boots up.",
                    binding: $isLaunchAtLoginEnabled,
                    onChange: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "dashboardMockLaunchAtLogin")
                    }
                )
            }
            .padding(ElevenLabsBrand.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .fill(ElevenLabsBrand.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                    .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
            )
        }
    }

    private func togglePreferenceRow(
        title: String,
        subtitle: String,
        binding: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: ElevenLabsBrand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(ElevenLabsBrand.Colors.tasteAccent)
                .onChange(of: binding.wrappedValue) { newValue in
                    onChange(newValue)
                }
        }
    }
}
