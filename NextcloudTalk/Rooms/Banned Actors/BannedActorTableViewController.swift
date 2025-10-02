//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class BannedActorTableViewController: UITableViewController, BannedActorCellDelegate {

    private let bannedActorCellIdentifier = "BannedActorCell"
    private var bannedActors: [BannedActor] = []

    var room: NCRoom
    var backgroundView: PlaceholderView = PlaceholderView(for: .grouped)
    var modifyingViewIndicator = UIActivityIndicatorView()

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

        self.navigationItem.title = NSLocalizedString("Banned users and guests", comment: "")

        self.tableView.register(UINib(nibName: bannedActorCellIdentifier, bundle: nil), forCellReuseIdentifier: bannedActorCellIdentifier)
        self.tableView.backgroundView = backgroundView

        self.backgroundView.placeholderView.isHidden = true
        self.backgroundView.placeholderTextView.text = NSLocalizedString("No banned users or guests", comment: "")
        self.backgroundView.setImage(UIImage(systemName: "person.badge.minus"))
        self.backgroundView.loadingView.startAnimating()

        self.modifyingViewIndicator.color = NCAppBranding.themeTextColor()
    }

    override func viewWillAppear(_ animated: Bool) {
        self.getData()
    }

    func getData() {
        NCAPIController.sharedInstance().listBans(for: room.accountId, in: room.token) { [weak self] bannedActors in
            guard let self else { return }

            self.bannedActors = bannedActors ?? []

            self.backgroundView.loadingView.stopAnimating()
            self.backgroundView.loadingView.isHidden = true
            self.backgroundView.placeholderView.isHidden = !self.bannedActors.isEmpty

            self.tableView.reloadData()
            self.hideActivityIndicator()
        }
    }

    func showActivityIndicator() {
        self.modifyingViewIndicator.startAnimating()
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: modifyingViewIndicator)
    }

    func hideActivityIndicator() {
        self.modifyingViewIndicator.stopAnimating()
        self.navigationItem.leftBarButtonItem = nil
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bannedActors.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: bannedActorCellIdentifier, for: indexPath) as? BannedActorCell
        else { return UITableViewCell() }

        let bannedActor = self.bannedActors[indexPath.row]
        cell.setupFor(bannedActor: bannedActor)
        cell.delegate = self

        return cell
    }

    func bannedActorCellUnbanActor(_ cell: BannedActorCell, bannedActor: BannedActor) {
        self.showActivityIndicator()
        cell.setDisabledState()

        NCAPIController.sharedInstance().unbanActor(for: room.accountId, in: self.room.token, with: bannedActor.banId) { [weak self] success in
            if !success {
                NotificationPresenter.shared().present(text: NSLocalizedString("Failed to unban selected entry", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }

            self?.getData()
        }
    }
}
