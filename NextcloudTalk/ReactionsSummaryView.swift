//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class ReactionsSummaryView: UITableViewController {

    var reactions: [String: [[String: AnyObject]]] = [:]
    var sortedReactions: [String] = []
    var reactionsBackgroundView: PlaceholderView = PlaceholderView(for: .grouped)

    public var room: NCRoom?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupReactionsSummaryView()
    }

    required override init(style: UITableView.Style) {
        super.init(style: style)
        self.setupReactionsSummaryView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Reactions", comment: "")

        reactionsBackgroundView.placeholderView.isHidden = true
        reactionsBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = reactionsBackgroundView

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func setupReactionsSummaryView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: kShareTableCellNibName, bundle: .main), forCellReuseIdentifier: kShareCellIdentifier)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 54, bottom: 0, right: 0)
    }

    func updateReactions(reactions: [String: [[String: AnyObject]]]) {
        self.reactions = reactions
        // Sort reactions by number of reactions
        for (k, _) in Array(reactions).sorted(by: {$0.value.count > $1.value.count}) {
            self.sortedReactions.append(k)
        }
        reactionsBackgroundView.loadingView.stopAnimating()
        reactionsBackgroundView.loadingView.isHidden = true
        self.tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sortedReactions.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let reaction = self.sortedReactions[section]
        if let actors = self.reactions[reaction] {
            return actors.count
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sortedReactions[section]
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kShareTableCellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kShareCellIdentifier) as? ShareTableViewCell ??
        ShareTableViewCell(style: .default, reuseIdentifier: kShareCellIdentifier)

        let reaction = self.sortedReactions[indexPath.section]
        let actor = self.reactions[reaction]?[indexPath.row]

        // Actor name
        let actorDisplayName = actor?["actorDisplayName"] as? String ?? ""

        cell.titleLabel.text = actorDisplayName.isEmpty ? NSLocalizedString("Guest", comment: "") : actorDisplayName

        // Actor avatar
        let actorId = actor?["actorId"] as? String ?? ""
        let actorType = actor?["actorType"] as? String ?? ""

        if let room, let account = room.account {
            cell.avatarImageView.setActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: room.token, using: account)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
