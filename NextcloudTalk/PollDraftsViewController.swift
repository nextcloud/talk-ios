//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol PollDraftsViewControllerDelegate: AnyObject {
    func didSelectPollDraft(question: String, options: [String], resultMode: NCPollResultMode, maxVotes: Int)
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

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Poll drafts", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

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
            self.delegate?.didSelectPollDraft(question: draft.question, options: draft.options.compactMap { $0 as? String }, resultMode: draft.resultMode, maxVotes: draft.maxVotes)
        }
    }
}
