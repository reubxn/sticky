//
//  DashboardLiveChatView.swift
//  leanring-buddy
//
//  Live, interactive chat surface embedded as a sidebar tab inside the
//  Dashboard. Wraps the same `ChatView` + `ChatViewModel` the floating
//  chat window uses, so messages typed here show up in the floating
//  window and vice versa — there's one shared transcript for the app.
//
//  The view model is held by `ChatWindowController.shared.chatViewModel`
//  so opening / closing the floating chat doesn't reset the dashboard's
//  copy and starting a "New chat" from either surface clears both.
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
        ChatView(chatViewModel: sharedChatViewModel)
            .onAppear {
                if let companionManager {
                    sharedChatViewModel.setCompanionManager(companionManager)
                }
                sharedChatViewModel.refreshSelectedModelFromUserDefaults()
            }
    }
}
