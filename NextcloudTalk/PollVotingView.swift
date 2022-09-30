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

    var poll: NCPoll?
    var room: NCRoom?
    var isPollOpen: Bool = false
    var isOwnPoll: Bool = false
    var canModeratePoll: Bool = false
    var userVoted: Bool = false
    var userVotedOptions: [Int] = []
    var editingVote: Bool = false
    var showPollResults: Bool = false
    var showIntermediateResults: Bool = false
    let footerView = PollFooterView(frame: CGRect.zero)
    var pollBackgroundView: PlaceholderView = PlaceholderView(for: .grouped)
    var userSelectedOptions: [Int] = []

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initPollView()
    }

    required override init(style: UITableView.Style) {
        super.init(style: style)
        self.initPollView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Poll", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        pollBackgroundView.placeholderView.isHidden = true
        pollBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = pollBackgroundView

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func initPollView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: "PollResultTableViewCell", bundle: .main), forCellReuseIdentifier: "PollResultCellIdentifier")
    }

    func setupPollView() {
        guard let poll = poll else {return}
        // Set poll settings
        let activeAccountUserId = NCDatabaseManager.sharedInstance().activeAccount().userId
        self.isPollOpen = poll.status == NCPollStatusOpen
        self.isOwnPoll = poll.actorId == activeAccountUserId && poll.actorType == "users"
        self.canModeratePoll = self.isOwnPoll || room?.isUserOwnerOrModerator() ?? false
        self.userVoted = !poll.votedSelf.isEmpty
        self.userVotedOptions = poll.votedSelf as? [Int] ?? []
        self.userSelectedOptions = self.userVotedOptions
        self.showPollResults = (userVoted && !editingVote) || !isPollOpen
        self.showIntermediateResults = showPollResults && isPollOpen && poll.resultMode == NCPollResultModeHidden
        // Set footer buttons
        self.tableView.tableFooterView = pollFooterView()
        // Set vote button state
        self.setVoteButtonState()
        // Reload table view
        self.tableView.reloadData()
    }

    func pollFooterView() -> UIView {
        var footerRect = CGRect.zero
        footerView.primaryButtonContainerView.isHidden = true
        footerView.secondaryButtonContainerView.isHidden = true
        if isPollOpen {
            // Primary button
            if userVoted && !editingVote {
                footerView.primaryButton.setTitle(NSLocalizedString("Change your vote", comment: ""), for: .normal)
                footerView.primaryButton.setButtonStyle(style: .secondary)
                footerView.primaryButton.setButtonAction(target: self, selector: #selector(editVoteButtonPressed))
            } else {
                footerView.primaryButton.setTitle(NSLocalizedString("Submit vote", comment: ""), for: .normal)
                footerView.primaryButton.setButtonStyle(style: .primary)
                footerView.primaryButton.setButtonAction(target: self, selector: #selector(voteButtonPressed))
            }
            footerRect.size.height += PollFooterView.heightForOption
            footerView.primaryButtonContainerView.isHidden = false
            // Secondary button
            if canModeratePoll {
                footerView.secondaryButton.setTitle(NSLocalizedString("End poll", comment: ""), for: .normal)
                footerView.secondaryButton.setButtonStyle(style: .destructive)
                footerView.secondaryButton.setButtonAction(target: self, selector: #selector(endPollButtonPressed))
            }
            if editingVote {
                footerView.secondaryButton.setTitle(NSLocalizedString("Dismiss", comment: ""), for: .normal)
                footerView.secondaryButton.setButtonStyle(style: .tertiary)
                footerView.secondaryButton.setButtonAction(target: self, selector: #selector(dismissButtonPressed))
            }
            if canModeratePoll || editingVote {
                footerRect.size.height += PollFooterView.heightForOption
                footerView.secondaryButtonContainerView.isHidden = false
            }
        }
        footerView.frame = footerRect
        return footerView
    }

    func voteButtonPressed() {
        guard let poll = poll, let room = room else {return}
        footerView.primaryButton.isEnabled = false
        NCAPIController.sharedInstance().voteOnPoll(withId: poll.pollId, inRoom: room.token, withOptions: userSelectedOptions,
        for: NCDatabaseManager.sharedInstance().activeAccount()) { responsePoll, error, _ in
            if let responsePoll = responsePoll, error == nil {
                self.poll = responsePoll
                self.editingVote = false
            }
            self.setupPollView()
        }
    }

    func editVoteButtonPressed() {
        self.editingVote = true
        self.setupPollView()
    }

    func dismissButtonPressed() {
        self.editingVote = false
        self.setupPollView()
    }

    func endPollButtonPressed() {
        self.showClosePollConfirmationDialog()
    }

    func setVoteButtonState() {
        if (userSelectedOptions.isEmpty || userSelectedOptions.sorted() == userVotedOptions.sorted()) &&
            isPollOpen && (!userVoted || editingVote) {
            footerView.primaryButton.setButtonEnabled(enabled: false)
        } else {
            footerView.primaryButton.setButtonEnabled(enabled: true)
        }
    }

    func updatePoll(poll: NCPoll) {
        self.poll = poll
        pollBackgroundView.loadingView.stopAnimating()
        pollBackgroundView.loadingView.isHidden = true
        setupPollView()
    }

    func showClosePollConfirmationDialog() {
        let closePollDialog = UIAlertController(
            title: NSLocalizedString("End poll", comment: ""),
            message: NSLocalizedString("Do you really want to end this poll?", comment: ""),
            preferredStyle: .alert)

        let endAction = UIAlertAction(title: NSLocalizedString("End poll", comment: ""), style: .destructive) { _ in
            self.closePoll()
        }
        closePollDialog.addAction(endAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        closePollDialog.addAction(cancelAction)

        self.present(closePollDialog, animated: true, completion: nil)
    }

    func closePoll() {
        guard let poll = poll, let room = room else {return}
        NCAPIController.sharedInstance().closePoll(withId: poll.pollId, inRoom: room.token, for: NCDatabaseManager.sharedInstance().activeAccount()) { responsePoll, error, _ in
            if let responsePoll = responsePoll, error == nil {
                self.poll = responsePoll
                self.editingVote = false
            }
            self.setupPollView()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return PollSection.kPollSectionCount.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case PollSection.kPollSectionQuestion.rawValue:
            return poll?.question != nil ?  1 : 0
        case PollSection.kPollSectionOptions.rawValue:
            return poll?.options?.count ?? 0
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == PollSection.kPollSectionOptions.rawValue {
            let votes = poll?.numVoters ?? 0
            let votesString = String.localizedStringWithFormat(NSLocalizedString("%d votes", comment: "Votes in a poll"), votes)
            let resultsString = NSLocalizedString("Results", comment: "Results of a poll")
            if showPollResults && !showIntermediateResults {
                return resultsString + " - " + votesString
            } else if canModeratePoll {
                return votesString
            }
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let pollQuestionCellIdentifier = "pollQuestionCellIdentifier"
        let pollOptionCellIdentifier = "pollOptionCellIdentifier"
        var cell = UITableViewCell()

        switch indexPath.section {
        case PollSection.kPollSectionQuestion.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: pollQuestionCellIdentifier)
            cell.textLabel?.text = poll?.question
            cell.textLabel?.numberOfLines = 4
            cell.textLabel?.lineBreakMode = .byWordWrapping
            cell.textLabel?.sizeToFit()
            cell.imageView?.image = UIImage(named: "poll")?.withRenderingMode(.alwaysTemplate)
            cell.imageView?.tintColor = UIColor.label

        case PollSection.kPollSectionOptions.rawValue:
            if !showPollResults || showIntermediateResults {
                cell = UITableViewCell(style: .value1, reuseIdentifier: pollOptionCellIdentifier)
                cell.textLabel?.text = poll?.options[indexPath.row] as? String
                cell.textLabel?.numberOfLines = 4
                cell.textLabel?.lineBreakMode = .byWordWrapping
                cell.textLabel?.sizeToFit()
                var checkboxImageView = UIImageView(image: UIImage(named: "checkbox-unchecked")?.withRenderingMode(.alwaysTemplate))
                checkboxImageView.tintColor = NCAppBranding.placeholderColor()
                let votedSelf = poll?.votedSelf as? [Int] ?? []
                if userSelectedOptions.contains(indexPath.row) || (showIntermediateResults && votedSelf.contains(indexPath.row)) {
                    checkboxImageView = UIImageView(image: UIImage(named: "checkbox-checked")?.withRenderingMode(.alwaysTemplate))
                    checkboxImageView.tintColor = NCAppBranding.elementColor()
                }
                if showIntermediateResults {
                    checkboxImageView.tintColor = checkboxImageView.tintColor.withAlphaComponent(0.3)
                }
                cell.accessoryView = checkboxImageView
            } else {
                let resultCell = tableView.dequeueReusableCell(withIdentifier: "PollResultCellIdentifier", for: indexPath) as? PollResultTableViewCell
                resultCell?.optionLabel.text = poll?.options[indexPath.row] as? String
                let votesDict = poll?.votes as? [String: Int] ?? [:]
                let optionVotes = votesDict["option-" + String(indexPath.row)] ?? 0
                let totalVotes = poll?.numVoters == 0 ? 1: poll?.numVoters ?? 1
                let progress = Float(optionVotes) / Float(totalVotes)
                resultCell?.optionProgressView.progress = progress
                resultCell?.resultLabel.text = String(Int(progress * 100)) + "%"
                let votedSelf = poll?.votedSelf as? [Int] ?? []
                if votedSelf.contains(indexPath.row) {
                    resultCell?.highlightResult()
                }
                cell = resultCell ?? PollResultTableViewCell()
            }
        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section != PollSection.kPollSectionOptions.rawValue || showIntermediateResults {
            return
        }

        guard let poll = poll else {return}

        if showPollResults {
            if poll.details.isEmpty {return}
            let pollResultsDetailsVC = PollResultsDetailsViewController(poll: poll)
            self.navigationController?.pushViewController(pollResultsDetailsVC, animated: true)
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
