//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol PollDraftsViewControllerDelegate: AnyObject {
    func didSelectPollDraft(draft:NCPoll, forEditing: Bool)
}

class PollDraftsViewController: UITableViewController {

    weak var delegate: PollDraftsViewControllerDelegate?

    var room: NCRoom
    var drafts: [NCPoll] = []
    var pollDraftsBackgroundView: PlaceholderView = PlaceholderView(for: .grouped)

    init(room: NCRoom) {
        self.room = room
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Poll drafts", comment: "")

        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [closeButton]

        setupBackgroundView()
        getPollDrafts()
    }

    // MARK: - Backgroud view
    private func setupBackgroundView() {
        pollDraftsBackgroundView.placeholderView.isHidden = true
        pollDraftsBackgroundView.loadingView.startAnimating()
        pollDraftsBackgroundView.placeholderTextView.text = NSLocalizedString("No poll drafts saved yet", comment: "")
        pollDraftsBackgroundView.setImage(UIImage(systemName: "chart.bar"))

        tableView.backgroundView = pollDraftsBackgroundView
    }

    // MARK: - Poll drafts
    private func getPollDrafts() {
        NCAPIController.sharedInstance().getPollDrafts(inRoom: room.token, for: room.account) { drafts, error, _ in
            if error == nil, let drafts {
                var draftsArray: [NCPoll] = []
                let draftDicts: [[String: Any]] = drafts.compactMap { $0 as? [String: Any] }
                for draftDict in draftDicts {
                    if let draft = NCPoll.initWithPollDictionary(draftDict) {
                        draftsArray.append(draft)
                    }
                }
                self.drafts = draftsArray
                self.tableView.reloadData()
            }

            self.pollDraftsBackgroundView.placeholderView.isHidden = drafts?.count ?? 0 > 0
            self.pollDraftsBackgroundView.loadingView.stopAnimating()
        }
    }

    // MARK: - Error dialogs
    func showDeletionError() {
        let alert = UIAlertController(title: NSLocalizedString("Deleting poll draft failed", comment: ""),
                                      message: NSLocalizedString("An error occurred while deleting the poll draft", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    // MARK: - TableView DataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return drafts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "PollDraftCellIdentifier"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
        let draft = drafts[indexPath.row]

        cell.imageView?.image = UIImage(systemName: "chart.bar")
        cell.imageView?.tintColor = UIColor.label
        cell.textLabel?.text = draft.question
        cell.detailTextLabel?.text = NSLocalizedString("Poll draft", comment: "") + " • " + String.localizedStringWithFormat(NSLocalizedString("%d options", comment: "Number of options in a poll"), draft.options.count)

        return cell
    }

    // MARK: - TableView Delegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        dismiss(animated: true) {
            let draft = self.drafts[indexPath.row]
            self.delegate?.didSelectPollDraft(draft: draft, forEditing: false)
        }
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: NSLocalizedString("Delete", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { [unowned self] _ in
                let draft = self.drafts[indexPath.row]
                NCAPIController.sharedInstance().closePoll(withId: draft.pollId, inRoom: room.token, for: room.account) { _, error, _ in
                    if error == nil {
                        self.getPollDrafts()
                    } else {
                        self.showDeletionError()
                    }
                }
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityEditDraftPoll, forAccountId: self.room.accountId) {
                let editAction = UIAction(title: NSLocalizedString("Edit", comment: ""), image: UIImage(systemName: "pencil")) { [unowned self] _ in
                    dismiss(animated: true) {
                        let draft = self.drafts[indexPath.row]
                        self.delegate?.didSelectPollDraft(draft: draft, forEditing: true)
                    }
                }

                return UIMenu(children: [editAction, deleteAction])
            }

            return UIMenu(children: [deleteAction])
        }
    }
}
