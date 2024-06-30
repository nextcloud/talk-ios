//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Banned users and guests", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        let themeColor: UIColor = NCAppBranding.themeColor()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = themeColor
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.tableView.register(UINib(nibName: bannedActorCellIdentifier, bundle: nil), forCellReuseIdentifier: bannedActorCellIdentifier)
        self.tableView.backgroundView = backgroundView

        self.backgroundView.placeholderView.isHidden = true
        self.backgroundView.loadingView.startAnimating()

        self.modifyingViewIndicator.color = NCAppBranding.themeTextColor()
    }

    override func viewWillAppear(_ animated: Bool) {
        self.getData()
    }

    func getData() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().listBans(for: activeAccount.accountId, in: room.token) { [weak self] bannedActors in
            guard let self else { return }

            self.bannedActors = bannedActors ?? []

            self.backgroundView.loadingView.stopAnimating()
            self.backgroundView.loadingView.isHidden = true

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

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().unbanActor(for: activeAccount.accountId, in: self.room.token, with: bannedActor.banId) { [weak self] success in
            if !success {
                NotificationPresenter.shared().present(text: NSLocalizedString("Failed to unban selected entry", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }

            self?.getData()
        }
    }
}
