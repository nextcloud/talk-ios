//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit
import DebouncedOnChange

struct UserSelectionSwiftUIView: View {

    @Environment(\.dismiss) var dismiss

    @Binding var selectedUserId: String?
    @Binding var selectedUserDisplayName: String?

    @State private var searchQuery = ""
    @State private var searchTask: URLSessionDataTask?
    @State private var isSearching: Bool = false
    @State private var userData: [NCUser] = []

    @FocusState private var textFieldIsFocused: Bool

    var searchInput: some View {
        TextField("Search for a user", text: $searchQuery)
            .autocorrectionDisabled()
            .focused($textFieldIsFocused)
            .onChange(of: searchQuery, debounceTime: 0.5) { _ in
                self.searchUsers()
            }
    }

    var userList: some View {
        List {
            Section {
                searchInput
            }

            ForEach(userData, id: \.self) { user in
                Button(action: {
                    self.selectedUserId = user.userId
                    self.selectedUserDisplayName = user.name
                    self.dismiss()
                },
                label: {
                    HStack {
                        AvatarImageViewWrapper(actorId: Binding.constant(user.userId), actorType: Binding.constant("users"))
                            .frame(width: 28, height: 28)
                            .clipShape(Capsule())

                        Text(user.name)
                            .foregroundColor(.primary)
                    }
                })
            }
        }
        .overlay {
            Group {
                if userData.isEmpty {
                    if isSearching {
                        ProgressView()
                    } else {
                        Text("No user found")
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack {
            userList.scrollContentBackground(.hidden)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitle(Text("Absence"), displayMode: .inline)
        .navigationBarHidden(false)
        .onAppear {
            self.textFieldIsFocused = true
        }
    }

    func searchUsers() {
        self.userData = []
        self.searchTask?.cancel()

        guard !self.searchQuery.isEmpty else { return }

        self.isSearching = true

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        self.searchTask = NCAPIController.sharedInstance().searchUsers(for: activeAccount, withSearchParam: searchQuery) { _, _, userList, _ in
            userData = userList as? [NCUser] ?? []
            self.isSearching = false
        }
    }

}
