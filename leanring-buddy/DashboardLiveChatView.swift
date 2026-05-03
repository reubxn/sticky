//
//  DashboardLiveChatView.swift
//  leanring-buddy
//
//  Live, interactive chat surface embedded as a sidebar tab inside the
//  Dashboard. Two-pane layout: a chat-history rail on the left listing
//  every archived session (text + voice, newest first), and the live
//  ChatView on the right. Tapping a row in the rail loads that session
//  into the live transcript so the user can read or continue it.
//
//  Wraps the same `ChatView` + `ChatViewModel` the floating chat window
//  uses, so messages typed here show up in the floating window and vice
//  versa — there's one shared transcript for the app. The view model is
//  held by `ChatWindowController.shared.chatViewModel` so opening /
//  closing the floating chat doesn't reset the dashboard's copy and
//  starting a "New chat" from either surface clears both.
//

import SwiftUI

struct DashboardLiveChatView: View {
    /// Optional CompanionManager. Threaded in from
    /// `DashboardWindowController`. When present, the chat view model
    /// uses the active persona and taste profile; when nil (previews),
    /// the chat falls back to a generic Sticky prompt.
    let companionManager: CompanionManager?

    /// The same ChatViewModel the floating chat window uses. Shared so
    /// both surfaces show the same transcript.
    @ObservedObject private var sharedChatViewModel: ChatViewModel = ChatWindowController.shared.chatViewModel

    var body: some View {
        HStack(spacing: 0) {
            // The sidebar requires a CompanionManager so it can render the
            // persona dropdown above the chats list. In production
            // `companionManager` is always non-nil; previews skip the
            // sidebar entirely so the chat still renders standalone.
            if let companionManager {
                ChatHistorySidebar(
                    chatViewModel: sharedChatViewModel,
                    companionManager: companionManager
                )
                .frame(width: 240)

                Divider().background(ElevenLabsBrand.Colors.hairline)
            }

            ChatView(
                chatViewModel: sharedChatViewModel,
                showsHeader: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let companionManager {
                sharedChatViewModel.setCompanionManager(companionManager)
            }
            sharedChatViewModel.refreshSelectedModelFromUserDefaults()
        }
    }
}
