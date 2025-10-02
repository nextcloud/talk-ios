//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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

    public var room: NCRoom

    required init?(coder aDecoder: NSCoder) {
        self.poll = NCPoll()
        self.room = NCRoom()
        
        super.init(coder: aDecoder)
        self.setupPollResultsDetailsView()
    }

    init(poll: NCPoll, room: NCRoom) {
        self.poll = poll
        self.room = room

        super.init(style: .insetGrouped)
        self.setupPollResultsDetailsView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Poll results", comment: "")
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
        if let account = room.account {
            cell.avatarImageView.setActorAvatar(forId: detail.actorId, withType: detail.actorType, withDisplayName: detail.actorDisplayName, withRoomToken: self.room.token, using: account)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
