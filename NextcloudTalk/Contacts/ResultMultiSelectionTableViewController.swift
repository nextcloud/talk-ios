//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class ResultMultiSelectionTableViewController: UITableViewController {

    private(set) var contacts: [String: [NCUser]] = [:]
    private(set) var indexes: [String] = []
    var selectedParticipants: [NCUser] = []
    var room: NCRoom?

    private let contactsBackgroundView = PlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)
        // Align header's title to ContactsTableViewCell's label
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        self.tableView.tableFooterView = UIView(frame: .zero)

        contactsBackgroundView.setImage(UIImage(named: "contacts-placeholder"))
        contactsBackgroundView.placeholderTextView.text = NSLocalizedString("No results found", comment: "")
        showSearchingUI()
        self.tableView.backgroundView = contactsBackgroundView
    }

    func showSearchingUI() {
        setContacts([:], withIndexes: [])
        contactsBackgroundView.placeholderView.isHidden = true
        contactsBackgroundView.loadingView.startAnimating()
        contactsBackgroundView.loadingView.isHidden = false
    }

    private func hideSearchingUI() {
        contactsBackgroundView.loadingView.stopAnimating()
        contactsBackgroundView.loadingView.isHidden = true
    }

    private func setContacts(_ contacts: [String: [NCUser]], withIndexes indexes: [String]) {
        self.contacts = contacts
        self.indexes = indexes
        self.tableView.reloadData()
    }

    func setSearchResultContacts(_ contacts: [String: [NCUser]], withIndexes indexes: [String]) {
        hideSearchingUI()
        contactsBackgroundView.placeholderView.isHidden = !contacts.isEmpty
        setContacts(contacts, withIndexes: indexes)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return indexes.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts[indexes[section]]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kContactsTableCellHeight
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return indexes[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let contact = contacts[indexes[indexPath.section]]?[indexPath.row],
              let cell = tableView.dequeueReusableCell(withIdentifier: kContactCellIdentifier, for: indexPath) as? ContactsTableViewCell
        else {
            return UITableViewCell()
        }

        cell.labelTitle.text = contact.name

        if contact.source == AttendeeType.email.rawValue {
            // Only when adding new (email) participants we show the mail avatar
            cell.avatarView.setMailAvatar()
        } else {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            cell.avatarView.setActorAvatar(forId: contact.userId, withType: contact.source, withDisplayName: contact.name, withRoomToken: room?.token, using: activeAccount)
        }

        let isSelected = selectedParticipants.contains { $0.userId == contact.userId && $0.source == contact.source }
        let selectionImageView = UIImageView(image: UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle"))
        selectionImageView.tintColor = isSelected ? NCAppBranding.elementColor() : .tertiaryLabel
        cell.accessoryView = selectionImageView

        return cell
    }
}
