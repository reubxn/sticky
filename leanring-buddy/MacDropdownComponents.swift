//
//  MacDropdownComponents.swift
//  leanring-buddy
//
//  Reusable SwiftUI primitives that match macOS Control Center / Wi-Fi
//  dropdown styling: translucent system material, rounded corners,
//  hairline border, soft shadow, sectioned content with circular-icon
//  rows and native hover highlights. Use these for any in-app dropdown
//  surface (model picker, taste-mode picker, etc.) so they all share
//  the same Apple-native feel.
//

import AppKit
import SwiftUI

// MARK: - Visual Effect Wrapper

/// `NSVisualEffectView` wrapped for SwiftUI. SwiftUI's built-in materials
/// (`.ultraThinMaterial` etc.) only blur content within the same window —
/// they don't blur what's behind a borderless panel. Using
/// `NSVisualEffectView` with `.behindWindow` blending is the only way to
/// get the desktop-blur look that Apple's own dropdowns have.
struct DropdownVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .menu,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        // `.active` keeps the blur lit even when the host panel isn't the
        // key window — important for non-activating menu-bar panels.
        visualEffectView.state = .active
        visualEffectView.isEmphasized = true
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Container

/// Wraps content in the standard macOS-dropdown chrome: translucent
/// `.menu` material, 12pt continuous corners, a hairline separator
/// border, and a soft drop shadow. Width defaults to 380pt to match
/// Apple's Wi-Fi / Focus / Sound dropdowns in Control Center.
struct MacDropdownContainer<Content: View>: View {
    var width: CGFloat
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        width: CGFloat = 380,
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(width: width)
        .background(DropdownVisualEffectView())
        .overlay(
            // Hairline border — Apple's dropdowns use a very subtle
            // separator-color stroke to define the surface edge against
            // bright backgrounds. Drawn as an inner stroke so it never
            // bleeds outside the rounded corners.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Section

/// One logical group inside a dropdown. Renders an optional sentence-case
/// header (matching modern macOS section-header style — not the older
/// uppercase tracked style), then its rows, then an optional bottom
/// divider. Stack multiple `DropdownSection`s vertically for menus like
/// Wi-Fi (Personal Hotspot / Other Networks / Settings).
struct DropdownSection<Content: View>: View {
    var title: String?
    var showsBottomDivider: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ title: String? = nil,
        showsBottomDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsBottomDivider = showsBottomDivider
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 4)

            if showsBottomDivider {
                Divider()
                    .padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - Row

/// A single tappable row in a dropdown. Mirrors the Wi-Fi dropdown
/// layout: a circular tinted icon well on the left, title (and optional
/// subtitle) in the middle, and an arbitrary trailing view (toggle,
/// chevron, status badge, checkmark, etc.) on the right. Hovering
/// fills the row with a subtle accent-colored background — same
/// behavior as Apple's own menu rows.
///
/// Pass `action: nil` to make the row inert (purely informational).
/// Otherwise the entire row width is clickable.
struct DropdownRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var iconBackground: Color
    var iconForeground: Color
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        iconBackground: Color = .accentColor,
        iconForeground: Color = .white,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconBackground = iconBackground
        self.iconForeground = iconForeground
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 10) {
                if let systemImage {
                    iconWell(systemName: systemImage)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                trailing()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                // Hover highlight only when the row is interactive.
                // Uses `Color.primary.opacity` so it inverts correctly
                // between light and dark mode (white wash in dark, black
                // wash in light) without us having to branch on scheme.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowHoverFill)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { hovering in isHovering = hovering }
    }

    private var rowHoverFill: Color {
        guard isHovering, action != nil else { return .clear }
        return Color.primary.opacity(0.08)
    }

    /// 28pt circular icon well in the row's tint color. Matches the
    /// circular Wi-Fi network icons / Focus mode icons in Control Center.
    private func iconWell(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(iconBackground)
                .frame(width: 28, height: 28)

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(iconForeground)
        }
    }
}

// MARK: - SwiftUI popover modifier

extension View {
    /// Presents Mac-style dropdown content as a SwiftUI popover anchored
    /// to this view. Wraps the content in `MacDropdownContainer` so the
    /// caller only has to provide sections + rows.
    ///
    /// Use this for in-window dropdowns triggered by buttons (model
    /// picker, mode picker, etc.). For the menu-bar dropdown itself,
    /// continue using `MenuBarPanelManager`'s custom `NSPanel` since a
    /// SwiftUI popover anchors to a window — and the menu-bar icon
    /// isn't part of any window.
    func macDropdown<Content: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 380,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            MacDropdownContainer(width: width) {
                content()
            }
        }
    }
}
