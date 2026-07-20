//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct RoomTagsAssignmentView: View {

    let room: NCRoom
    let account: TalkAccount
    let hostingWrapper: HostingControllerWrapper

    @State private var customTags: [NCConversationTag] = []
    @State private var assignedTagIds: Set<String> = []
    @State private var newTagName = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            Section {
                ForEach(customTags, id: \.tagId) { tag in
                    let isAssigned = assignedTagIds.contains(tag.tagId)

                    Button(action: {
                        toggle(tag)
                    }, label: {
                        HStack {
                            Text(tag.name)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isAssigned ? Color(NCAppBranding.elementColor()) : Color(.tertiaryLabel))
                        }
                    })
                }

                // Create a new tag and directly assign it to this conversation
                HStack {
                    TextField(NSLocalizedString("New tag", comment: "Placeholder for the name of a new tag"), text: $newTagName)
                    Button(NSLocalizedString("Create", comment: "Generic 'Create' button label (e.g. new conversation, new tag)")) {
                        createAndAssignTag()
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                Button(action: {
                    hostingWrapper.presentViewController(RoomTagsManagementView.viewController(forAccount: account), animated: true)
                }, label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Manage tags")
                    }
                    .foregroundColor(.primary)
                })
            }
        }
        .navigationBarTitle(Text(NSLocalizedString("Tags", comment: "'Tags' meaning 'Conversation tags'")), displayMode: .inline)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    // Environment dismiss is not wired up to the UIKit modal presentation
                    hostingWrapper.dismissViewController(animated: true)
                }, label: {
                    Text("Close")
                        .foregroundColor(Color(getTintColor()))
                })
            }
        }
        .onAppear {
            loadTags()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NCConversationTagsUpdated)) { output in
            guard output.userInfo?["accountId"] as? String == account.accountId,
                  let tags = output.userInfo?["tags"] as? [NCConversationTag]
            else { return }

            customTags = tags.filter { $0.type == NCConversationTagTypeCustom }
        }
        .alert(errorMessage ?? NSLocalizedString("Could not update tags", comment: ""), isPresented: $showError) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        }
    }

    private func getTintColor() -> UIColor {
        if #available(iOS 26.0, *) {
            return .label
        } else {
            return NCAppBranding.themeTextColor()
        }
    }

    private func loadTags() {
        customTags = NCDatabaseManager.sharedInstance().conversationTags(forAccountId: account.accountId).filter { $0.type == NCConversationTagTypeCustom }
        assignedTagIds = Set(room.tagIdList)

        // Revalidate from the server. The result is delivered through the NCConversationTagsUpdated notification
        NCAPIController.sharedInstance().getConversationTags(forAccount: account)
    }

    private func createAndAssignTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                let tag = try await NCAPIController.sharedInstance().createConversationTag(name, forAccount: account)

                newTagName = ""
                customTags.append(tag)
                toggle(tag)
            } catch {
                if let tagError = error as? NCAPIController.ConversationTagError {
                    errorMessage = tagError.localizedMessage
                } else {
                    errorMessage = nil
                }

                showError = true
            }
        }
    }

    private func toggle(_ tag: NCConversationTag) {
        // Optimistically apply the new state and roll back in case the request fails
        let previousTagIds = assignedTagIds

        if assignedTagIds.contains(tag.tagId) {
            assignedTagIds.remove(tag.tagId)
        } else {
            assignedTagIds.insert(tag.tagId)
        }

        let newTagIds = Array(assignedTagIds)

        Task {
            do {
                _ = try await NCAPIController.sharedInstance().setConversationTags(newTagIds, forRoom: room.token, forAccount: account)

                // Refresh the room, so the tag changes are stored and reflected in the conversation list
                NCRoomsManager.shared.updateRoom(room.token, forAccount: account)
            } catch {
                assignedTagIds = previousTagIds
                errorMessage = nil
                showError = true
            }
        }
    }
}

extension RoomTagsAssignmentView {

    static func viewController(for room: NCRoom, withAccount account: TalkAccount) -> UIViewController {
        let wrapper = HostingControllerWrapper()
        let hostingController = UIHostingController(rootView: RoomTagsAssignmentView(room: room, account: account, hostingWrapper: wrapper))
        wrapper.controller = hostingController

        let navigationController = NCNavigationController(rootViewController: hostingController)

        // Style the content view controller, so the navigation bar gets the theme color (pre iOS 26)
        NCAppBranding.styleViewController(hostingController)

        return navigationController
    }
}
