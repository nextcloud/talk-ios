//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol AddParticipantsTableViewControllerDelegate: NSObjectProtocol {
    @objc optional func addParticipantsTableViewController(_ viewController: AddParticipantsTableViewController, wantsToAdd participants: [NCUser])
    @objc optional func addParticipantsTableViewControllerDidFinish(_ viewController: AddParticipantsTableViewController)
}

class AddParticipantsTableViewController: UITableViewController, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating {

    weak var delegate: AddParticipantsTableViewControllerDelegate?

    private let room: NCRoom?

    private var participants: [String: [NCUser]] = [:]
    private var indexes: [String] = []
    private var selectedParticipants: [NCUser] = []

    private var resultTableViewController: ResultMultiSelectionTableViewController!
    private var searchController: UISearchController!
    private var participantsBackgroundView: PlaceholderView!
    private var searchTimer: Timer?
    private var searchParticipantsTask: URLSessionDataTask?
    private let addingParticipantsIndicator = UIActivityIndicatorView()

    init(for room: NCRoom?) {
        self.room = room

        super.init(nibName: "AddParticipantsTableViewController", bundle: nil)

        if #available(iOS 26.0, *) {
            addingParticipantsIndicator.color = .label
        } else {
            addingParticipantsIndicator.color = NCAppBranding.themeTextColor()
        }
    }

    convenience init(participants: [NCUser]) {
        self.init(for: nil)

        self.selectedParticipants = participants
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        self.tableView.sectionIndexBackgroundColor = .clear

        resultTableViewController = ResultMultiSelectionTableViewController()
        resultTableViewController.selectedParticipants = NSMutableArray(array: selectedParticipants)
        resultTableViewController.room = room

        searchController = UISearchController(searchResultsController: resultTableViewController)
        searchController.searchResultsUpdater = self
        searchController.searchBar.sizeToFit()

        self.navigationItem.searchController = searchController

        NCAppBranding.styleViewController(self)

        self.tableView.tableFooterView = UIView(frame: .zero)
        // Contacts placeholder view
        participantsBackgroundView = PlaceholderView()
        participantsBackgroundView.setImage(UIImage(named: "contacts-placeholder"))
        participantsBackgroundView.placeholderTextView.text = NSLocalizedString("No participants found", comment: "")
        participantsBackgroundView.placeholderView.isHidden = true
        participantsBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = participantsBackgroundView

        // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
        resultTableViewController.tableView.delegate = self
        searchController.delegate = self
        searchController.searchBar.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false

        updateCounter()

        self.definesPresentationContext = true

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = cancelButton
        self.navigationItem.title = NSLocalizedString("Add participants", comment: "")

        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.navigationItem.hidesSearchBarWhenScrolling = false

        getPossibleParticipants()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationItem.hidesSearchBarWhenScrolling = false
    }

    // MARK: - View controller actions

    @objc func cancelButtonPressed() {
        close()
    }

    func close() {
        delegate?.addParticipantsTableViewControllerDidFinish?(self)
        self.navigationController?.dismiss(animated: true)
    }

    @objc func addButtonPressed() {
        // Adding participants to a room
        if let room, !selectedParticipants.isEmpty {
            // Extending a one2one room
            if room.type == .oneToOne, NCDatabaseManager.sharedInstance().serverHasTalkCapability(.conversationCreationAll) {
                extendOne2OneRoom()

            // Adding participants to a group room
            } else {
                let addParticipantsGroup = DispatchGroup()
                var errorAddingParticipants = false

                showAddingParticipantsView()
                for participant in selectedParticipants {
                    addParticipantsGroup.enter()
                    Task { @MainActor in
                        let success = await self.addParticipant(participant, toRoom: room)
                        if !success {
                            errorAddingParticipants = true
                        }
                        addParticipantsGroup.leave()
                    }
                }

                addParticipantsGroup.notify(queue: .main) { [weak self] in
                    self?.removeAddingParticipantsView()

                    if !errorAddingParticipants {
                        self?.close()
                    }
                }
            }

        // If there is no room, it means the AddParticipantsViewController is being used just to select participants
        } else if let delegate, delegate.responds(to: #selector(AddParticipantsTableViewControllerDelegate.addParticipantsTableViewController(_:wantsToAdd:))) {
            delegate.addParticipantsTableViewController?(self, wantsToAdd: selectedParticipants)
            close()
        }
    }

    @MainActor
    private func addParticipant(_ participant: NCUser, toRoom room: NCRoom) async -> Bool {
        do {
            _ = try await NCAPIController.sharedInstance().addParticipant(participant.userId, ofType: participant.source as String?, toRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
            return true
        } catch {
            let alert = UIAlertController(title: NSLocalizedString("Could not add participant", comment: ""),
                                          message: String(format: NSLocalizedString("An error occurred while adding %@ to the room", comment: ""), participant.name),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            return false
        }
    }

    func extendOne2OneRoom() {
        guard let room, let account = room.account else {
            return
        }

        let roomBuilder = RoomBuilder()
        roomBuilder.roomType(.group)
        roomBuilder.objecType(NCRoomObjectTypeExtendedConversation)
        roomBuilder.objectId(room.token)

        // Create the other participant of the 1:1 room from room object
        let user = NCUser()
        user.userId = room.name
        user.name = room.displayName
        user.source = kParticipantTypeUser as NSString

        // Add the other participant of the 1:1 room at the beginning of the selected participants array
        let participants = [user] + selectedParticipants
        roomBuilder.participants(participants)

        // Create the room name [Actor who extends the 1:1 room, other participant of the 1:1 room, selected participants...]
        var namesArray: [String] = participants.map { $0.name }
        namesArray.insert(account.userDisplayName, at: 0)
        var roomName = namesArray.joined(separator: ", ")
        // Ensure the roomName does not exceed 255 characters limit.
        if roomName.count > 255 {
            roomName = String(roomName.prefix(254)) + "…"
        }
        roomBuilder.roomName(roomName)

        showAddingParticipantsView()
        NCAPIController.sharedInstance().createRoom(forAccount: account, withParameters: roomBuilder.roomParameters) { [weak self] createdRoom, error in
            guard let self else { return }

            self.removeAddingParticipantsView()
            if error != nil {
                let alert = UIAlertController(title: NSLocalizedString("Could not start group conversation", comment: ""),
                                              message: NSLocalizedString("An error occurred while starting a new group conversation", comment: ""),
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            } else if let createdRoom {
                self.navigationController?.dismiss(animated: true) {
                    NotificationCenter.default.post(name: NSNotification.Name.NCSelectedUserForChat, object: self, userInfo: ["token": createdRoom.token])
                }
            }
        }
    }

    func updateCounter() {
        var addButton: UIBarButtonItem?
        if room == nil {
            addButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(addButtonPressed))
        } else if !selectedParticipants.isEmpty {
            addButton = UIBarButtonItem(title: String(format: NSLocalizedString("Add (%lu)", comment: ""), selectedParticipants.count),
                                        style: .plain, target: self, action: #selector(addButtonPressed))
        }

        self.navigationController?.navigationBar.topItem?.rightBarButtonItem = addButton
    }

    func showAddingParticipantsView() {
        addingParticipantsIndicator.startAnimating()
        let addingParticipantButton = UIBarButtonItem(customView: addingParticipantsIndicator)
        self.navigationItem.rightBarButtonItems = [addingParticipantButton]
        self.tableView.allowsSelection = false
        resultTableViewController.tableView.allowsSelection = false
    }

    func removeAddingParticipantsView() {
        addingParticipantsIndicator.stopAnimating()
        updateCounter()
        self.tableView.allowsSelection = true
        resultTableViewController.tableView.allowsSelection = true
    }

    // MARK: - Participants actions

    func getPossibleParticipants() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getContacts(forAccount: activeAccount, forRoom: room?.token, forGroupRoom: true, withSearchParam: nil) { [weak self] contactList, error in
            guard let self else { return }

            if error == nil, let contactList = contactList as? [NCUser] {
                let storedContacts = NCContact.contacts(forAccountId: activeAccount.accountId, contains: nil)
                let combinedContactList = NCUser.combineUsersArray(storedContacts, withUsersArray: contactList)
                if let participants = NCUser.indexedUsers(fromUsersArray: combinedContactList) {
                    self.participants = participants
                    self.indexes = participants.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    self.participantsBackgroundView.loadingView.stopAnimating()
                    self.participantsBackgroundView.loadingView.isHidden = true
                    self.participantsBackgroundView.placeholderView.isHidden = !participants.isEmpty
                    self.tableView.reloadData()
                }
            } else if let error {
                NCLog.log("Error while trying to get participants: \(error)")
            }
        }
    }

    func searchForParticipants(with searchString: String) {
        searchParticipantsTask?.cancel()
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        searchParticipantsTask = NCAPIController.sharedInstance().getContacts(forAccount: activeAccount, forRoom: room?.token, forGroupRoom: true, withSearchParam: searchString) { [weak self] contactList, error in
            guard let self else { return }

            if error == nil, let contactList = contactList as? [NCUser] {
                let storedContacts = NCContact.contacts(forAccountId: activeAccount.accountId, contains: searchString)
                let combinedContactList = NCUser.combineUsersArray(storedContacts, withUsersArray: contactList)
                if let participants = NCUser.indexedUsers(fromUsersArray: combinedContactList) {
                    let sortedIndexes = participants.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    self.resultTableViewController.setSearchResultContacts(NSMutableDictionary(dictionary: participants), withIndexes: sortedIndexes)
                }
            } else if let error, error.underlyingError.code != NSURLErrorCancelled {
                NCLog.log("Error while searching for participants: \(error)")
            }
        }
    }

    func isParticipantAlreadySelected(_ participant: NCUser) -> Bool {
        return selectedParticipants.contains {
            $0.userId == participant.userId && $0.source == participant.source
        }
    }

    func removeSelectedParticipant(_ participant: NCUser) {
        if let index = selectedParticipants.firstIndex(where: {
            $0.userId == participant.userId && $0.source == participant.source
        }) {
            selectedParticipants.remove(at: index)
        }
    }

    // MARK: - Search controller

    func updateSearchResults(for searchController: UISearchController) {
        searchTimer?.invalidate()
        searchTimer = nil
        resultTableViewController.showSearchingUI()
        DispatchQueue.main.async { [weak self] in
            self?.searchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.searchForParticipants()
            }
        }
    }

    func searchForParticipants() {
        guard let searchString = searchController.searchBar.text, !searchString.isEmpty else {
            return
        }

        searchForParticipants(with: searchString)
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        self.tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return indexes.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let index = indexes[section]
        return participants[index]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kContactsTableCellHeight
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return indexes[section]
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return indexes
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let index = indexes[indexPath.section]
        let participantsForIndex = participants[index] ?? []
        let participant = participantsForIndex[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: kContactCellIdentifier, for: indexPath) as? ContactsTableViewCell ??
        ContactsTableViewCell(style: .default, reuseIdentifier: kContactCellIdentifier)

        cell.labelTitle.text = participant.name

        let account = room?.account ?? NCDatabaseManager.sharedInstance().activeAccount()

        cell.avatarView.setActorAvatar(forId: participant.userId, withType: participant.source as String?, withDisplayName: participant.name, withRoomToken: room?.token, using: account)

        var selectionImage = UIImage(systemName: "circle")
        var selectionImageColor = UIColor.tertiaryLabel
        if isParticipantAlreadySelected(participant) {
            selectionImage = UIImage(systemName: "checkmark.circle.fill")
            selectionImageColor = NCAppBranding.elementColor()
        }
        let selectionImageView = UIImageView(image: selectionImage)
        selectionImageView.tintColor = selectionImageColor
        cell.accessoryView = selectionImageView

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let participantsForIndex: [NCUser]

        if searchController.isActive,
           let resultContacts = resultTableViewController.contacts as? [String: [NCUser]], !resultContacts.isEmpty,
           let resultIndexes = resultTableViewController.indexes as? [String] {
            let index = resultIndexes[indexPath.section]
            participantsForIndex = resultContacts[index] ?? []
        } else {
            let index = indexes[indexPath.section]
            participantsForIndex = participants[index] ?? []
        }

        let participant = participantsForIndex[indexPath.row]
        if !isParticipantAlreadySelected(participant) {
            selectedParticipants.append(participant)
        } else {
            removeSelectedParticipant(participant)
        }

        resultTableViewController.selectedParticipants = NSMutableArray(array: selectedParticipants)

        tableView.beginUpdates()
        tableView.reloadRows(at: [indexPath], with: .none)
        tableView.endUpdates()

        updateCounter()
    }

}
