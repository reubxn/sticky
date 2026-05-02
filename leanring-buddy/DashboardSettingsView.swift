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
    /// Selected Claude model — same UserDefaults key as
    /// `CompanionManager.selectedModel`. Reads on appear, writes on
    /// change.
    @State private var selectedClaudeModel: String = UserDefaults.standard
        .string(forKey: "selectedClaudeModel") ?? "claude-haiku-4-5-20251001"

    /// Sticky cursor toggle — same key as
    /// `CompanionManager.isClickyCursorEnabled`.
    @State private var isClickyCursorEnabled: Bool = UserDefaults.standard
        .object(forKey: "isClickyCursorEnabled") as? Bool ?? true

    /// Mocked: launch at login. Real launch-at-login already
    /// registers via SMAppService at startup; this toggle is just
    /// a UI placeholder for the dashboard surface.
    @State private var isLaunchAtLoginEnabled: Bool = UserDefaults.standard
        .bool(forKey: "dashboardMockLaunchAtLogin")

    /// Mocked: analytics opt-out toggle. Doesn't actually unhook
    /// PostHog in the MVP — surface only.
    @State private var isAnalyticsOptedOut: Bool = UserDefaults.standard
        .bool(forKey: "dashboardMockAnalyticsOptedOut")

    private static let availableClaudeModels: [(modelId: String, displayName: String)] = [
        ("claude-haiku-4-5-20251001", "Haiku 4.5 — fastest"),
        ("claude-sonnet-4-6", "Sonnet 4.6 — balanced"),
        ("claude-opus-4-7", "Opus 4.7 — sharpest")
    ]

    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "SETTINGS",
                title: "Sticky preferences.",
                subtitle: "Tune the model, the cursor, and the demo toggles. Changes persist."
            )

            modelPickerCard

            cursorAndHotkeyCard

            otherPreferencesCard
        }
    }

    // MARK: - Model picker card

    private var modelPickerCard: some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            ElevenLabsEyebrow("MODEL")

            VStack(spacing: 6) {
                ForEach(Self.availableClaudeModels, id: \.modelId) { model in
                    modelPickerRow(modelId: model.modelId, displayName: model.displayName)
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

    private func modelPickerRow(modelId: String, displayName: String) -> some View {
        let isSelected = (modelId == selectedClaudeModel)
        return Button(action: {
            selectedClaudeModel = modelId
            UserDefaults.standard.set(modelId, forKey: "selectedClaudeModel")
        }) {
            HStack(spacing: ElevenLabsBrand.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(
                        isSelected
                            ? ElevenLabsBrand.Colors.ink
                            : ElevenLabsBrand.Colors.inkTertiary
                    )
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                Spacer()
            }
            .padding(.vertical, 6)
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

                Divider().background(ElevenLabsBrand.Colors.hairline)

                togglePreferenceRow(
                    title: "Opt out of analytics",
                    subtitle: "We collect anonymous usage stats to improve Sticky. Toggle this to opt out.",
                    binding: $isAnalyticsOptedOut,
                    onChange: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "dashboardMockAnalyticsOptedOut")
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
                .onChange(of: binding.wrappedValue) { newValue in
                    onChange(newValue)
                }
        }
    }
}
