//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit
import SDWebImage

class RoomSearchTableViewController: UITableViewController {

    private enum RoomSearchSection: Int {
        case filtered = 0
        case users
        case listable
        case messages
    }

    var rooms: [NCRoom] = [] { didSet { reloadAndCheckSearchingIndicator() } }
    var users: [NCUser] = [] { didSet { reloadAndCheckSearchingIndicator() } }
    var listableRooms: [NCRoom] = [] { didSet { reloadAndCheckSearchingIndicator() } }
    var messages: [NKSearchEntry] = [] { didSet { reloadAndCheckSearchingIndicator() } }
    var searchingMessages: Bool = false { didSet { reloadAndCheckSearchingIndicator() } }

    private var roomSearchBackgroundView: PlaceholderView = PlaceholderView(for: .insetGrouped)
    private var suppressReload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.register(UINib(nibName: RoomTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: RoomTableViewCell.identifier)
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = UITableView.automaticDimension
        self.tableView.tableFooterView = UIView(frame: .zero)
        // Align header's title to ContactsTableViewCell's label
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 0)
        self.tableView.separatorInsetReference = .fromAutomaticInsets
        // Contacts placeholder view
        roomSearchBackgroundView.setImage(UIImage(named: "conversations-placeholder"))
        roomSearchBackgroundView.placeholderTextView.text = NSLocalizedString("No results found", comment: "")
        roomSearchBackgroundView.placeholderView.isHidden = true
        roomSearchBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = roomSearchBackgroundView
    }

    // MARK: - User Interface

    private func reloadAndCheckSearchingIndicator() {
        guard !suppressReload else { return }

        self.tableView.reloadData()

        if searchingMessages {
            if !searchSections().isEmpty {
                roomSearchBackgroundView.loadingView.stopAnimating()
                roomSearchBackgroundView.loadingView.isHidden = true
                showSearchingFooterView()
            } else {
                roomSearchBackgroundView.loadingView.startAnimating()
                roomSearchBackgroundView.loadingView.isHidden = false
                hideSearchingFooterView()
            }
            roomSearchBackgroundView.placeholderView.isHidden = true
        } else {
            roomSearchBackgroundView.loadingView.stopAnimating()
            roomSearchBackgroundView.loadingView.isHidden = true
            roomSearchBackgroundView.placeholderView.isHidden = !searchSections().isEmpty
        }
    }

    func showSearchingFooterView() {
        let loadingMoreView = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        loadingMoreView.color = .darkGray
        loadingMoreView.startAnimating()
        self.tableView.tableFooterView = loadingMoreView
    }

    func hideSearchingFooterView() {
        self.tableView.tableFooterView = nil
    }

    func clearSearchedResults() {
        suppressReload = true
        rooms = []
        users = []
        listableRooms = []
        messages = []
        suppressReload = false

        reloadAndCheckSearchingIndicator()
    }

    // MARK: - Utils

    private func searchSections() -> [RoomSearchSection] {
        var sections: [RoomSearchSection] = []
        if !rooms.isEmpty {
            sections.append(.filtered)
        }
        if !users.isEmpty {
            sections.append(.users)
        }
        if !listableRooms.isEmpty {
            sections.append(.listable)
        }
        if !messages.isEmpty {
            sections.append(.messages)
        }
        return sections
    }

    func room(for indexPath: IndexPath) -> NCRoom? {
        let searchSection = searchSections()[indexPath.section]
        if searchSection == .filtered && indexPath.row < rooms.count {
            return rooms[indexPath.row]
        } else if searchSection == .listable && indexPath.row < listableRooms.count {
            return listableRooms[indexPath.row]
        }

        return nil
    }

    func message(for indexPath: IndexPath) -> NKSearchEntry? {
        let searchSection = searchSections()[indexPath.section]
        if searchSection == .messages && indexPath.row < messages.count {
            return messages[indexPath.row]
        }

        return nil
    }

    func user(for indexPath: IndexPath) -> NCUser? {
        let searchSection = searchSections()[indexPath.section]
        if searchSection == .users && indexPath.row < users.count {
            return users[indexPath.row]
        }

        return nil
    }

    private func tableView(_ tableView: UITableView, cellForMessageAt indexPath: IndexPath) -> UITableViewCell {
        let messageEntry = messages[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: RoomTableViewCell.identifier) as? RoomTableViewCell ?? RoomTableViewCell(style: .default, reuseIdentifier: RoomTableViewCell.identifier)

        cell.titleLabel.text = messageEntry.title
        cell.subtitleLabel.text = messageEntry.subline

        // Thumbnail image
        let thumbnailURL = URL(string: messageEntry.thumbnailURL)
        let actorId = messageEntry.attributes?["actorId"] as? String
        let actorType = messageEntry.attributes?["actorType"] as? String
        if let thumbnailURL, !thumbnailURL.absoluteString.isEmpty {
            cell.avatarView.avatarImageView.sd_setImage(with: thumbnailURL, placeholderImage: nil, options: [.retryFailed, .refreshCached])
            cell.avatarView.avatarImageView.contentMode = .scaleToFill
        } else {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            cell.avatarView.setActorAvatar(forId: actorId, withType: actorType, withDisplayName: "", withRoomToken: nil, using: activeAccount)
        }

        // Clear possible content not removed by cell reuse
        cell.dateLabel.text = ""
        cell.setUnread(messages: 0, mentioned: false, groupMentioned: false)

        // Add message date (if it is included in attributes)
        var timestamp = 0
        if let timestampValue = messageEntry.attributes?["timestamp"] {
            if let number = timestampValue as? NSNumber {
                timestamp = number.intValue
            } else if let string = timestampValue as? String {
                timestamp = Int(string) ?? 0
            }
        }
        if timestamp > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            cell.dateLabel.text = NCUtils.readableTimeOrDate(fromDate: date)
        }

        return cell
    }

    private func tableView(_ tableView: UITableView, cellForUserAt indexPath: IndexPath) -> UITableViewCell {
        let user = users[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: RoomTableViewCell.identifier) as? RoomTableViewCell ?? RoomTableViewCell(style: .default, reuseIdentifier: RoomTableViewCell.identifier)

        // Clear possible content not removed by cell reuse
        cell.dateLabel.text = ""
        cell.setUnread(messages: 0, mentioned: false, groupMentioned: false)

        cell.titleLabel.text = user.name
        cell.titleOnly = true
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        cell.avatarView.setActorAvatar(forId: user.userId, withType: user.source as String?, withDisplayName: user.name, withRoomToken: nil, using: activeAccount)

        return cell
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return searchSections().count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch searchSections()[section] {
        case .filtered:
            return rooms.count
        case .users:
            return users.count
        case .listable:
            return listableRooms.count
        case .messages:
            return messages.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch searchSections()[section] {
        case .filtered:
            return NSLocalizedString("Conversations", comment: "")
        case .users:
            return NSLocalizedString("Users", comment: "")
        case .listable:
            return NSLocalizedString("Open conversations", comment: "TRANSLATORS 'Open conversations' as a type of conversation. 'Open conversations' are conversations that can be found by other users")
        case .messages:
            return NSLocalizedString("Messages", comment: "")
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let searchSection = searchSections()[indexPath.section]
        // Messages
        if searchSection == .messages {
            return self.tableView(tableView, cellForMessageAt: indexPath)
        }
        // Contacts
        if searchSection == .users {
            return self.tableView(tableView, cellForUserAt: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: RoomTableViewCell.identifier) as? RoomTableViewCell ?? RoomTableViewCell(style: .default, reuseIdentifier: RoomTableViewCell.identifier)

        guard let room = room(for: indexPath) else { return cell }

        // Set room name
        cell.titleLabel.text = room.displayName

        // Set last activity
        if room.lastMessageId != nil || room.lastMessageProxiedJSONString != nil {
            cell.titleOnly = false
            cell.subtitleLabel.attributedText = room.lastMessageString
        } else {
            cell.titleOnly = true
            cell.subtitleLabel.text = ""
        }
        let date = Date(timeIntervalSince1970: TimeInterval(room.lastActivity))
        cell.dateLabel.text = NCUtils.readableTimeOrDate(fromDate: date)

        // Open conversations
        if searchSection == .listable {
            cell.titleOnly = false
            cell.subtitleLabel.text = room.roomDescription
            cell.dateLabel.text = ""
        }

        // Set unread messages
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDirectMentionFlag) {
            let mentioned = room.unreadMentionDirect || room.type == .oneToOne || room.type == .formerOneToOne
            let groupMentioned = room.unreadMention && !room.unreadMentionDirect
            cell.setUnread(messages: room.unreadMessages, mentioned: mentioned, groupMentioned: groupMentioned)
        } else {
            let mentioned = room.unreadMention || room.type == .oneToOne || room.type == .formerOneToOne
            cell.setUnread(messages: room.unreadMessages, mentioned: mentioned, groupMentioned: false)
        }

        if room.unreadMessages > 0 {
            // When there are unread messages, we need to show the subtitle at the moment
            cell.titleOnly = false
        }

        cell.avatarView.setAvatar(for: room)

        // Set favorite or call image
        if room.hasCall {
            cell.avatarView.favoriteImageView.tintColor = .systemRed
            cell.avatarView.favoriteImageView.image = UIImage(systemName: "video.fill")
        } else if room.isFavorite {
            cell.avatarView.favoriteImageView.tintColor = .systemYellow
            cell.avatarView.favoriteImageView.image = UIImage(systemName: "star.fill")
        }

        return cell
    }
}
