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

@objcMembers class PollResultsDetailsViewController: UITableViewController {

    struct PollResultDetail {
        let actorDisplayName: String
        let actorId: String
        let actorType: String
        let optionId: Int

        init(dictionary: [String: Any]) {
            self.actorDisplayName = dictionary["actorDisplayName"] as? String ?? ""
            self.actorId = dictionary["actorId"] as? String ?? ""
            self.actorType = dictionary["actorType"] as? String ?? ""
            self.optionId = dictionary["optionId"] as? Int ?? 0
        }
    }

    var poll: NCPoll
    var resultsDetails: [Int: [PollResultDetail]] = [:]
    var sortedOptions: [Int] = []

    required init?(coder aDecoder: NSCoder) {
        self.poll = NCPoll()
        super.init(coder: aDecoder)
        self.setupPollResultsDetailsView()
    }

    init(poll: NCPoll) {
        self.poll = poll

        super.init(style: .insetGrouped)
        self.setupPollResultsDetailsView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Poll results", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func setupPollResultsDetailsView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: kShareTableCellNibName, bundle: .main), forCellReuseIdentifier: kShareCellIdentifier)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 54, bottom: 0, right: 0)

        // Create resultsDetails dictionary
        for detail in poll.details {
            if let resultDetail = detail as? [String: Any] {
                let pollResultDetail = PollResultDetail(dictionary: resultDetail)
                if var value = resultsDetails[pollResultDetail.optionId] {
                    value.append(pollResultDetail)
                    resultsDetails[pollResultDetail.optionId] = value
                } else {
                    resultsDetails[pollResultDetail.optionId] = [pollResultDetail]
                }
            }
        }
        sortedOptions = Array(resultsDetails.keys).sorted()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sortedOptions.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let option = sortedOptions[section]
        if let optionDetails = resultsDetails[option] {
            return optionDetails.count
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let option = sortedOptions[section]
        return poll.options[option] as? String
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kShareTableCellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kShareCellIdentifier) as? ShareTableViewCell ??
        ShareTableViewCell(style: .default, reuseIdentifier: kShareCellIdentifier)

        let option = sortedOptions[indexPath.section]
        let optionDetails = resultsDetails[option]
        guard let detail = optionDetails?[indexPath.row] else {return UITableViewCell()}

        // Actor name
        cell.titleLabel.text = detail.actorDisplayName

        // Actor avatar
        if detail.actorType == "users" {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            if let request = NCAPIController.sharedInstance().createAvatarRequest(forUser: detail.actorId, with: self.traitCollection.userInterfaceStyle, andSize: 96, using: activeAccount) {
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
