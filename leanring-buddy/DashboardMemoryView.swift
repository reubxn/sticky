//
//  DashboardMemoryView.swift
//  leanring-buddy
//
//  "Memory" tab of the Dashboard — embeds the same TasteLibraryView
//  that previously lived in its own floating window. Shows every
//  TastePrinciple Sticky has learned, grouped by domain, with the
//  Personal/Team scope toggle at the top.
//
//  A thin wrapper so the library view doesn't need to know whether
//  it's hosted in a floating window or inside the dashboard.
//

import SwiftUI

struct DashboardMemoryView: View {
    /// Threaded in from `DashboardWindowController`. The library needs
    /// a CompanionManager to read the active scope and persona. When
    /// nil (previews / dashboard opened before the menu bar wired
    /// things up), shows a small placeholder explaining how to access
    /// the library.
    let companionManager: CompanionManager?

    var body: some View {
        if let companionManager {
            TasteLibraryView(companionManager: companionManager)
        } else {
            placeholderForUnavailableManager
        }
    }

    /// Tiny fallback shown when the dashboard was created before the
    /// shared CompanionManager was injected. Should be unreachable in
    /// the running app — the menu bar always wires the manager in
    /// before opening the dashboard — but kept as a defensive fallback
    /// rather than crashing with a force-unwrap.
    private var placeholderForUnavailableManager: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            Text("Memory unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text("Open Sticky from the menu bar first.")
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ElevenLabsBrand.Colors.paper)
    }
}
