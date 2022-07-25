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

@objcMembers class PollVotingView: UITableViewController {

    enum PollSection: Int {
        case kPollSectionQuestion = 0
        case kPollSectionOptions
        case kPollSectionCount
    }

    var poll: NCPoll = NCPoll()
    var room: String = ""
    var pollBackgroundView: PlaceholderView = PlaceholderView(for: .grouped)
    var userSelectedOptions: [Int] = []
    var voteButton: UIButton = UIButton()

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupPollView()
    }

    required override init(style: UITableView.Style) {
        super.init(style: style)
        self.setupPollView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Poll", comment: "")

        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            appearance.backgroundColor = NCAppBranding.themeColor()
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }

        pollBackgroundView.placeholderView.isHidden = true
        pollBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = pollBackgroundView

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func setupPollView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: kShareTableCellNibName, bundle: .main), forCellReuseIdentifier: kShareCellIdentifier)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 54, bottom: 0, right: 0)
    }

    func pollFooterView() -> UIView {
        if poll.question != nil {
            let buttonsContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
            voteButton = UIButton(frame: CGRect(x: 0, y: 0, width: 50, height: 40))
            voteButton.setTitle(NSLocalizedString("Vote", comment: ""), for: .normal)
            voteButton.addTarget(self, action: #selector(voteButtonPressed), for: .touchUpInside)
            voteButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            voteButton.backgroundColor = NCAppBranding.themeColor()
            voteButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
            voteButton.setTitleColor(NCAppBranding.themeTextColor().withAlphaComponent(0.5), for: .disabled)
            voteButton.layer.cornerRadius = 20.0
            voteButton.layer.masksToBounds = true
            voteButton.sizeToFit()
            let voteButtonFrame = voteButton.frame
            buttonsContainerView.addSubview(voteButton)
            // Add constraints
            voteButton.translatesAutoresizingMaskIntoConstraints = false
            let horizontalConstraint = NSLayoutConstraint(item: voteButton,
                                                          attribute: NSLayoutConstraint.Attribute.centerX,
                                                          relatedBy: NSLayoutConstraint.Relation.equal,
                                                          toItem: buttonsContainerView,
                                                          attribute: NSLayoutConstraint.Attribute.centerX,
                                                          multiplier: 1,
                                                          constant: 0)
            let verticalConstraint = NSLayoutConstraint(item: voteButton,
                                                        attribute: NSLayoutConstraint.Attribute.centerY,
                                                        relatedBy: NSLayoutConstraint.Relation.equal,
                                                        toItem: buttonsContainerView,
                                                        attribute: NSLayoutConstraint.Attribute.centerY,
                                                        multiplier: 1,
                                                        constant: 0)
            let widthConstraint = NSLayoutConstraint(item: voteButton,
                                                     attribute: NSLayoutConstraint.Attribute.width,
                                                     relatedBy: NSLayoutConstraint.Relation.equal,
                                                     toItem: nil,
                                                     attribute: NSLayoutConstraint.Attribute.notAnAttribute,
                                                     multiplier: 1,
                                                     constant: voteButtonFrame.width + 40)
            let heightConstraint = NSLayoutConstraint(item: voteButton,
                                                      attribute: NSLayoutConstraint.Attribute.height,
                                                      relatedBy: NSLayoutConstraint.Relation.equal,
                                                      toItem: nil,
                                                      attribute: NSLayoutConstraint.Attribute.notAnAttribute,
                                                      multiplier: 1,
                                                      constant: 40)
            buttonsContainerView.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])
            return buttonsContainerView
        }
        return UIView()
    }

    func voteButtonPressed() {
        NCAPIController.sharedInstance().voteOnPoll(withId: poll.pollId, inRoom: room, withOptions: userSelectedOptions,
        for: NCDatabaseManager.sharedInstance().activeAccount()) { responsePoll, error, _ in
            if let responsePoll = responsePoll, error == nil {
                self.poll = responsePoll
            }
        }
    }

    func setVoteButtonState() {
        if userSelectedOptions.isEmpty {
            voteButton.backgroundColor = NCAppBranding.themeColor().withAlphaComponent(0.5)
            voteButton.isEnabled = false
        } else {
            voteButton.backgroundColor = NCAppBranding.themeColor()
            voteButton.isEnabled = true
        }
    }

    func updatePoll(poll: NCPoll) {
        self.poll = poll
        pollBackgroundView.loadingView.stopAnimating()
        pollBackgroundView.loadingView.isHidden = true
        self.tableView.tableFooterView = pollFooterView()
        self.setVoteButtonState()
        self.tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return PollSection.kPollSectionCount.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case PollSection.kPollSectionQuestion.rawValue:
            return poll.question != nil ?  1 : 0
        case PollSection.kPollSectionOptions.rawValue:
            return poll.options?.count ?? 0
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let pollQuestionCellIdentifier = "pollQuestionCellIdentifier"
        let pollOptionCellIdentifier = "pollOptionCellIdentifier"
        var cell = UITableViewCell()

        switch indexPath.section {
        case PollSection.kPollSectionQuestion.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: pollQuestionCellIdentifier)
            cell.textLabel?.text = poll.question
            cell.textLabel?.numberOfLines = 4
            cell.textLabel?.lineBreakMode = .byWordWrapping
            cell.textLabel?.sizeToFit()
            cell.imageView?.image = UIImage(named: "poll")?.withRenderingMode(.alwaysTemplate)
            cell.imageView?.tintColor = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)
        case PollSection.kPollSectionOptions.rawValue:
            cell = UITableViewCell(style: .value1, reuseIdentifier: pollOptionCellIdentifier)
            cell.textLabel?.text = poll.options[indexPath.row] as? String
            cell.textLabel?.numberOfLines = 4
            cell.textLabel?.lineBreakMode = .byWordWrapping
            cell.textLabel?.sizeToFit()
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            if userSelectedOptions.contains(indexPath.row) {
                cell.accessoryView = UIImageView(image: UIImage(named: "checkbox-checked"))
            } else {
                cell.accessoryView = UIImageView(image: UIImage(named: "checkbox-unchecked"))
            }
        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section != PollSection.kPollSectionOptions.rawValue {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        if let index = userSelectedOptions.firstIndex(of: indexPath.row), poll.maxVotes != 1 {
            userSelectedOptions.remove(at: index)
        } else {
            if poll.maxVotes == 1 {
                userSelectedOptions.removeAll()
            } else if poll.maxVotes > 1 && poll.maxVotes == userSelectedOptions.count {
                return
            }
            userSelectedOptions.append(indexPath.row)
        }
        setVoteButtonState()
        tableView.reloadSections(IndexSet(integer: PollSection.kPollSectionOptions.rawValue), with: .automatic)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
