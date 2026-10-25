//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ConversationView: View {

    @EnvironmentObject private var connection: WatchConnection

    let conversation: WatchConversation

    @State private var messages: [WatchMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var reactingTo: WatchMessage?

    private let quickReplies = [
        "👍",
        NSLocalizedString("OK", comment: "Quick reply on the Apple Watch"),
        NSLocalizedString("Thanks!", comment: "Quick reply on the Apple Watch"),
        NSLocalizedString("On my way", comment: "Quick reply on the Apple Watch"),
        NSLocalizedString("I'll call you later", comment: "Quick reply on the Apple Watch")
    ]

    var body: some View {
        Group {
            // The list is only created once the messages are there, so it starts at the bottom
            if isLoading, messages.isEmpty, errorMessage == nil {
                ProgressView()
            } else {
                messageList
            }
        }
        .navigationTitle(conversation.displayName)
        .task {
            await load()
            await connection.markAsRead(conversation)
        }
        .sheet(item: $reactingTo) { message in
            ReactionPicker { reaction in
                reactingTo = nil
                react(with: reaction, to: message)
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                ForEach(messages) { message in
                    MessageRow(message: message)
                        .id(message.id)
                        .onTapGesture {
                            if conversation.canReact {
                                reactingTo = message
                            }
                        }
                }

                Section {
                    TextFieldLink(prompt: Text(NSLocalizedString("Reply", comment: ""))) {
                        Label(NSLocalizedString("Reply", comment: ""), systemImage: "mic.fill")
                    } onSubmit: { text in
                        send(text)
                    }
                    .disabled(isSending)

                    ForEach(quickReplies, id: \.self) { reply in
                        Button(reply) {
                            send(reply)
                        }
                        .disabled(isSending)
                    }
                }
            }
            .onAppear {
                // Start with the newest message
                DispatchQueue.main.async {
                    proxy.scrollTo(messages.last?.id, anchor: .top)
                }
            }
        }
    }

    private func load() async {
        isLoading = true

        do {
            messages = try await connection.messages(in: conversation)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func send(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isSending = true

        Task {
            do {
                try await connection.send(trimmedText, to: conversation)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    private func react(with reaction: String, to message: WatchMessage) {
        Task {
            do {
                try await connection.react(with: reaction, to: message, in: conversation)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct MessageRow: View {

    let message: WatchMessage

    var body: some View {
        VStack(alignment: message.isOwnMessage ? .trailing : .leading, spacing: 2) {
            if !message.isOwnMessage {
                Text(message.author)
                    .font(.caption2)
                    .foregroundStyle(Color.talkAccent)
                    .lineLimit(1)
            }

            Text(message.text)
                .font(.footnote)

            HStack(spacing: 4) {
                ForEach(message.reactions, id: \.reaction) { reaction in
                    Text("\(reaction.reaction) \(reaction.count)")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(reaction.reactedBySelf ? Color.talkAccent.opacity(0.5) : Color.gray.opacity(0.3)))
                }

                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isOwnMessage ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ReactionPicker: View {

    let onSelect: (String) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WatchRequest.reactions, id: \.self) { reaction in
                Button(reaction) {
                    onSelect(reaction)
                }
                .font(.title2)
            }
        }
        .padding(.horizontal)
    }
}
