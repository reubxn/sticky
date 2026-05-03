//
//  DashboardSectionHeader.swift
//  leanring-buddy
//
//  Shared section header shown at the top of every dashboard tab —
//  large editorial title + optional subtitle + optional trailing
//  control slot. Keeps the visual rhythm consistent across Tastes,
//  Team, Profile, Chat, Settings without repeating the same
//  six-line VStack in each view.
//

import SwiftUI

struct DashboardSectionHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    let trailing: () -> Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: ElevenLabsBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                ElevenLabsEyebrow(eyebrow)

                Text(title)
                    .font(ElevenLabsBrand.Typography.cardTitle(size: 26))
                    .tracking(-0.4)
                    .foregroundColor(ElevenLabsBrand.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ElevenLabsBrand.Typography.body)
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing()
        }
    }
}

// Convenience overload for headers without a trailing control.
extension DashboardSectionHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// Shared scroll-container that the section views wrap their content
/// in. Provides consistent padding + max-width clamp so content
/// stays readable in a wide window.
struct DashboardContentScrollContainer<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.lg) {
                content()
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, ElevenLabsBrand.Spacing.xl)
            .padding(.vertical, ElevenLabsBrand.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
