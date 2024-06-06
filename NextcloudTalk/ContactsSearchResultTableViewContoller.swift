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

@objcMembers class ContactsSearchResultTableViewController: UITableViewController {

    var indexes: [String] = []
    var contacts: [String: [NCUser]] = [:]

    let tableBackgroundView = PlaceholderView()

    override init(style: UITableView.Style) {
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)

        tableBackgroundView.setImage(UIImage(named: "contacts-placeholder"))
        tableBackgroundView.placeholderTextView.text = NSLocalizedString("No results found", comment: "")
        self.showSearchingUI()
        self.tableView.backgroundView = tableBackgroundView

    }

    // MARK: - UI

    func showSearchingUI() {
        tableBackgroundView.placeholderView.isHidden = true
        tableBackgroundView.loadingView.startAnimating()
        tableBackgroundView.loadingView.isHidden = false
    }

    func hideSearchingUI() {
        tableBackgroundView.loadingView.stopAnimating()
        tableBackgroundView.loadingView.isHidden = true
    }

    func setContacts(_ contacts:[String: [NCUser]], indexes:[String]) {
        self.contacts = contacts
        self.indexes = indexes
        self.tableView.reloadData()
    }

    func setSearchResultContacts(_ contacts:[String: [NCUser]], indexes:[String]) {
        self.hideSearchingUI()
        self.tableBackgroundView.placeholderView.isHidden = !contacts.isEmpty
        self.setContacts(contacts, indexes: indexes)
    }

    // MARK: - TableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return indexes.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return indexes[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let index = indexes[section]
        return contacts[index]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

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
