//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class ThreadsTableViewController: UITableViewController {

    private let threadCellIdentifier = "ThreadCellIdentifier"
    private var threads: [NCThread] = []

    var backgroundView: PlaceholderView = PlaceholderView(for: .grouped)

    init(threads: [NCThread]?) {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Threads", comment: "")

        let barButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        barButtonItem.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.leftBarButtonItems = [barButtonItem]

        self.tableView.register(UINib(nibName: RoomTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: threadCellIdentifier)
        self.tableView.backgroundView = backgroundView

        self.backgroundView.placeholderView.isHidden = true
        self.backgroundView.loadingView.startAnimating()
        self.backgroundView.placeholderTextView.text = NSLocalizedString("No followed threads", comment: "")
        self.backgroundView.setImage(UIImage(systemName: "bubble.left.and.bubble.right"))
    }

    override func viewWillAppear(_ animated: Bool) {
        self.getData()
    }

    func getData() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getSubscribedThreads(for: activeAccount.accountId) { [weak self] threads, _ in
            guard let self else { return }

            if let threads {
                self.threads = threads
            } else {
                self.threads = []
            }

            self.backgroundView.loadingView.stopAnimating()
            self.backgroundView.placeholderView.isHidden = !self.threads.isEmpty
            self.tableView.reloadData()
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return threads.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: threadCellIdentifier, for: indexPath) as? RoomTableViewCell
        else { return UITableViewCell() }

        let thread = self.threads[indexPath.row]
        cell.avatarView.avatarImageView.setThreadAvatar(forThread: thread)
        cell.titleLabel.text = thread.title

        cell.roomToken = thread.roomToken

        let message = thread.lastMessage() ?? thread.firstMessage()
        cell.subtitleLabel.text = message?.messagePreview()?.string

        if let timestamp = message?.timestamp {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            cell.dateLabel.text = NCUtils.readableTimeOrDate(fromDate: date)
        } else {
            cell.dateLabel.text = nil
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let thread = self.threads[indexPath.row]
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        guard let room = NCDatabaseManager.sharedInstance().room(withToken: thread.roomToken, forAccountId: thread.accountId),
              let chatViewController = ChatViewController(forThread: thread, inRoom: room, withAccount: activeAccount)
        else { return }

        self.navigationController?.pushViewController(chatViewController, animated: true)
    }
}
