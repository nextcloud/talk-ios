//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
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

@objcMembers class ReactionsSummaryView: UITableViewController {

    var reactions: [String: [[String: AnyObject]]] = [:]
    var sortedReactions: [String] = []
    var reactionsBackgroundView: PlaceholderView = PlaceholderView(for: .grouped)

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

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Reactions", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        reactionsBackgroundView.placeholderView.isHidden = true
        reactionsBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = reactionsBackgroundView

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
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
        let actorDisplayName = actor?["actorDisplayName"] as? String
        cell.titleLabel.text = actorDisplayName

        // Actor avatar
        let actorId = actor?["actorId"] as? String
        let actorType = actor?["actorType"] as? String
        if actorId != nil && actorType == "users" {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            if let request = NCAPIController.sharedInstance().createAvatarRequest(forUser: actorId, with: self.traitCollection.userInterfaceStyle, andSize: 96, using: activeAccount) {
                cell.avatarImageView.setImageWith(request, placeholderImage: nil, success: nil, failure: nil)
                cell.avatarImageView.contentMode = .scaleToFill
            }
        } else {
            let color = UIColor(red: 0.73, green: 0.73, blue: 0.73, alpha: 1.0) /*#b9b9b9*/
            cell.avatarImageView.setImageWith("?", color: color, circular: true)
            cell.avatarImageView.contentMode = .scaleToFill
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
