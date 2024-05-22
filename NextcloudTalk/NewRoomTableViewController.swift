//
// Copyright (c) 2024 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit

enum NewRoomOption: Int {
    case createNewRoom = 0
    case joinOpenRoom
}

@objcMembers class NewRoomTableViewController: UITableViewController,
                                               UINavigationControllerDelegate {

    var account: TalkAccount

    var indexes: [String] = []
    var contacts: [String: [NCUser]] = [:]
    var serverContacts: [NCUser] = []
    var addressBookContacts: [NCUser] = []

    init(account: TalkAccount) {
        self.account = account
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.getPossibleContacts()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("New conversation", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()

        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - New room options

    func getNewRoomOptions() -> [NewRoomOption] {
        var options = [NewRoomOption]()

        // New group room
        if NCSettingsController.sharedInstance().canCreateGroupAndPublicRooms() {
            options.append(.createNewRoom)
        }

        // List open rooms
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms, forAccountId: self.account.accountId) {
            options.append(.joinOpenRoom)
        }

        return options
    }

    // MARK: - Contacts

    func getPossibleContacts() {
        NCAPIController.sharedInstance().getContactsFor(account, forRoom: "new", groupRoom: false, withSearchParam: "") { indexes, _, contacts, _ in
            self.indexes = indexes as? [String] ?? []
            self.indexes.insert("", at: 0)
            self.serverContacts = contacts as? [NCUser] ?? []
            self.loadCombinedContacts()
        }
    }

    func loadCombinedContacts() {
        self.addressBookContacts = NCContact.contacts(forAccountId: self.account.accountId, contains: nil)

        let combinedContactArray = NCUser.combineUsersArray(self.addressBookContacts, withUsersArray: self.serverContacts)
        self.contacts = NCUser.indexedUsers(fromUsersArray: combinedContactArray)

        self.tableView.reloadData()
    }

    // MARK: - TableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return indexes.count
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return indexes
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return indexes[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return getNewRoomOptions().count
        } else {
            let index = indexes[section]
            return contacts[index]?.count ?? 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if indexPath.section == 0 {
            let options = getNewRoomOptions()
            let option = options[indexPath.row]
            var newRoomOptionCell = UITableViewCell()
            switch option {
            case .createNewRoom:
                newRoomOptionCell = tableView.dequeueReusableCell(withIdentifier: "NewGroupRoomCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "NewGroupRoomCellIdentifier")
                newRoomOptionCell.textLabel?.text = NSLocalizedString("Create a new conversation", comment: "")
                newRoomOptionCell.imageView?.image = UIImage(systemName: "bubble")
            case .joinOpenRoom:
                newRoomOptionCell = tableView.dequeueReusableCell(withIdentifier: "ListOpenRoomsCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "ListOpenRoomsCellIdentifier")
                newRoomOptionCell.textLabel?.text = NSLocalizedString("Join open conversations", comment: "")
                newRoomOptionCell.imageView?.image = UIImage(systemName: "list.bullet")
            }

            newRoomOptionCell.imageView?.tintColor = .secondaryLabel
            newRoomOptionCell.imageView?.contentMode = .scaleAspectFit
            newRoomOptionCell.textLabel?.numberOfLines = 0

            return newRoomOptionCell

        } else {
            let index = indexes[indexPath.section]
            let contactsForIndex = contacts[index]
            guard let contact = contactsForIndex?[indexPath.row] else {
                return UITableViewCell()
            }

            let contactCell = tableView.dequeueReusableCell(withIdentifier: kContactCellIdentifier) as? ContactsTableViewCell ??
            ContactsTableViewCell(style: .default, reuseIdentifier: kContactCellIdentifier)

            contactCell.labelTitle.text = contact.name

            let contactType = contact.source as String
            contactCell.contactImage.setActorAvatar(forId: contact.userId, withType: contactType, withDisplayName: contact.name, withRoomToken: nil)

            return contactCell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            let options = getNewRoomOptions()
            let option = options[indexPath.row]

            if option == .createNewRoom {
                self.presentCreateRoomViewController()
            } else if option == .joinOpenRoom {
                self.presentJoinOpenRoomsViewController()
            }

        } else {
            let index = indexes[indexPath.section]
            let contactsForIndex = contacts[index]
            guard let contact = contactsForIndex?[indexPath.row] else { return }

            self.createConversationWithContact(contact)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Actions

    func presentCreateRoomViewController() {
        let viewController = RoomCreationTableViewController(account: account)
        let navController = NCNavigationController(rootViewController: viewController)
        self.present(navController, animated: true)
    }

    func presentJoinOpenRoomsViewController() {
        let viewController = OpenConversationsTableViewController()
        let navController = NCNavigationController(rootViewController: viewController)
        self.present(navController, animated: true)
    }

    func createConversationWithContact(_ contact: NCUser) {
        NCAPIController.sharedInstance().createRoom(forAccount: account, withInvite: contact.userId, ofType: .oneToOne, andName: nil) { room, error in
            if let token = room?.token, error == nil {
                self.navigationController?.dismiss(animated: true, completion: {
                    NotificationCenter.default.post(name: NSNotification.Name.NCSelectedUserForChat, object: self, userInfo: ["token": token])
                })
            }
        }
    }
}
