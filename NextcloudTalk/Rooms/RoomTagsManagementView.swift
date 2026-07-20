//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

extension NCAPIController.ConversationTagError {

    var localizedMessage: String {
        switch self {
        case .invalidName:
            return NSLocalizedString("This tag name is invalid or already in use", comment: "")
        case .tagLimitReached:
            return NSLocalizedString("You have reached the maximum number of tags", comment: "")
        case .immutableTag:
            return NSLocalizedString("This tag cannot be changed", comment: "")
        }
    }
}

struct RoomTagsManagementView: View {

    let account: TalkAccount
    let hostingWrapper: HostingControllerWrapper

    @Environment(\.editMode) private var editMode

    @State private var tags: [NCConversationTag] = []
    @State private var newTagName = ""
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    @State private var tagToRename: NCConversationTag?
    @State private var renamedTagName = ""
    @State private var showRenameAlert = false

    @State private var tagToDelete: NCConversationTag?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                ForEach(tags, id: \.tagId) { tag in
                    if tag.type == NCConversationTagTypeCustom {
                        Text(tag.name)
                            .swipeActions {
                                Button(role: .destructive, action: {
                                    tagToDelete = tag
                                    showDeleteConfirmation = true
                                }, label: {
                                    Image(systemName: "trash")
                                })

                                Button(action: {
                                    tagToRename = tag
                                    renamedTagName = tag.name
                                    showRenameAlert = true
                                }, label: {
                                    Image(systemName: "pencil")
                                })
                            }
                    } else {
                        // Built-in favorites tag can be reordered, but not renamed or deleted
                        HStack {
                            Text(NSLocalizedString("Favorites", comment: "'Favorites' meaning 'Favorite conversations'"))
                            Spacer()
                            Image(systemName: "star.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onMove(perform: move)

                // Shown as the last row of the tags section while editing
                if editMode?.wrappedValue.isEditing == true {
                    HStack {
                        TextField(NSLocalizedString("New tag", comment: "Placeholder for the name of a new tag"), text: $newTagName)
                        Button(NSLocalizedString("Create", comment: "Generic 'Create' button label (e.g. new conversation, new tag)")) {
                            createTag()
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } footer: {
                if !tags.isEmpty {
                    Text("Swipe a tag to rename or delete it. Use edit to reorder the tags.")
                }
            }
        }
        .navigationBarTitle(Text(NSLocalizedString("Manage tags", comment: "")), displayMode: .inline)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .tint(Color(getTintColor()))
            }
        }
        .onAppear {
            loadTags()
        }
        .alert(NSLocalizedString("Rename tag", comment: ""), isPresented: $showRenameAlert) {
            TextField(NSLocalizedString("Tag name", comment: ""), text: $renamedTagName)
            Button(NSLocalizedString("Save", comment: "")) {
                renameTag()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(NSLocalizedString("Delete tag?", comment: ""), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                deleteTag()
            }
        } message: {
            Text("This tag will be removed from all conversations it is assigned to.")
        }
        .alert(errorMessage ?? NSLocalizedString("An error occurred, please try again", comment: ""), isPresented: $showErrorAlert) {
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
        tags = NCDatabaseManager.sharedInstance().conversationTags(forAccountId: account.accountId).filter { $0.type != NCConversationTagTypeOther }

        refreshTagsFromServer()
    }

    private func refreshTagsFromServer() {
        // Also updates the stored tags and notifies the conversation list
        NCAPIController.sharedInstance().getConversationTags(forAccount: account) { fetchedTags, _ in
            guard let fetchedTags else { return }

            tags = fetchedTags.filter { $0.type != NCConversationTagTypeOther }
        }
    }

    private func showError(_ error: Error) {
        if let tagError = error as? NCAPIController.ConversationTagError {
            errorMessage = tagError.localizedMessage
        } else {
            errorMessage = nil
        }

        showErrorAlert = true
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                _ = try await NCAPIController.sharedInstance().createConversationTag(name, forAccount: account)
                newTagName = ""
                refreshTagsFromServer()
            } catch {
                showError(error)
            }
        }
    }

    private func renameTag() {
        guard let tagToRename else { return }

        let name = renamedTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != tagToRename.name else { return }

        Task {
            do {
                _ = try await NCAPIController.sharedInstance().renameConversationTag(withId: tagToRename.tagId, to: name, forAccount: account)
                refreshTagsFromServer()
            } catch {
                showError(error)
            }
        }
    }

    private func deleteTag() {
        guard let tagToDelete else { return }

        Task {
            do {
                try await NCAPIController.sharedInstance().deleteConversationTag(withId: tagToDelete.tagId, forAccount: account)
                refreshTagsFromServer()

                // The tag was removed from all conversations, so refresh the rooms to update their tags
                NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
            } catch {
                showError(error)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)

        let orderedIds = tags.map { $0.tagId }

        Task {
            do {
                _ = try await NCAPIController.sharedInstance().reorderConversationTags(withOrderedIds: orderedIds, forAccount: account)
                refreshTagsFromServer()
            } catch {
                showError(error)
                refreshTagsFromServer()
            }
        }
    }
}

extension RoomTagsManagementView {

    static func viewController(forAccount account: TalkAccount) -> UIViewController {
        let wrapper = HostingControllerWrapper()
        let hostingController = UIHostingController(rootView: RoomTagsManagementView(account: account, hostingWrapper: wrapper))
        wrapper.controller = hostingController

        let navigationController = NCNavigationController(rootViewController: hostingController)

        // Style the content view controller, so the navigation bar gets the theme color (pre iOS 26)
        NCAppBranding.styleViewController(hostingController)

        return navigationController
    }
}
