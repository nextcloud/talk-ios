//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class BotsTableViewController: UITableViewController, BotCellDelegate {

    var room: NCRoom
    var bots: [Bot]
    var backgroundView: PlaceholderView = PlaceholderView(for: .grouped)
    var modifyingViewIndicator = UIActivityIndicatorView()

    init(room: NCRoom, bots: [Bot]) {
        self.room = room
        self.bots = bots
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Bots", comment: "")

        self.tableView.register(UINib(nibName: BotCell.identifier, bundle: nil), forCellReuseIdentifier: BotCell.identifier)
        self.tableView.backgroundView = backgroundView
        self.tableView.sectionHeaderTopPadding = 0

        self.backgroundView.placeholderTextView.text = NSLocalizedString("No bots available for this conversation", comment: "")
        self.backgroundView.setImage(UIImage(named: "custom.laptopcomputer.badge.person.crop.slash"))
        self.backgroundView.placeholderView.isHidden = !self.bots.isEmpty

        if #unavailable(iOS 26.0) {
            self.modifyingViewIndicator.color = NCAppBranding.themeTextColor()
        }
    }

    func showActivityIndicator() {
        self.modifyingViewIndicator.startAnimating()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modifyingViewIndicator)
    }

    func hideActivityIndicator() {
        self.modifyingViewIndicator.stopAnimating()
        self.navigationItem.rightBarButtonItem = nil
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bots.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: BotCell.identifier, for: indexPath) as? BotCell
        else { return UITableViewCell() }

        let bot = self.bots[indexPath.row]
        cell.setupFor(bot: bot)
        cell.delegate = self

        return cell
    }

    // MARK: - Delegate

    func changeBotState(_ cell: BotCell, bot: Bot) {
        guard let account = self.room.account else { return }

        self.showActivityIndicator()
        cell.setDisabledState()

        Task {
            let updatedBot: Bot?

            if bot.state == .disabled {
                updatedBot = try await NCAPIController.sharedInstance().enableBot(withId: bot.id, forRoom: self.room.token, forAccount: account)
            } else {
                updatedBot = try await NCAPIController.sharedInstance().disableBot(withId: bot.id, forRoom: self.room.token, forAccount: account)
            }

            cell.setEnabledState()

            if let updatedBot, let firstBot = self.bots.firstIndex(where: { $0.id == updatedBot.id }) {
                self.bots[firstBot] = updatedBot
                cell.setupFor(bot: updatedBot)
            }

            self.hideActivityIndicator()
        }
    }

}
