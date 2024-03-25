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

class FederationInvitationTableViewController: UITableViewController, FederationInvitationCellDelegate {

    private let federationInvitationCellIdentifier = "FederationInvitationCell"
    private var pendingInvitations: [FederationInvitation] = []

    var backgroundView: PlaceholderView = PlaceholderView(for: .grouped)
    var modifyingViewIndicator = UIActivityIndicatorView()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Pending invitations", comment: "")
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

        let barButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        barButtonItem.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [barButtonItem]

        self.tableView.register(UINib(nibName: federationInvitationCellIdentifier, bundle: nil), forCellReuseIdentifier: federationInvitationCellIdentifier)
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

        NCAPIController.sharedInstance().getFederationInvitations(for: activeAccount.accountId) { [weak self] invitations in
            guard let self else { return }

            if let invitations {
                // TODO: For now the invitation endpoint also returns accepted invitations, we only want to have pending
                self.pendingInvitations = invitations.filter { $0.invitationState != .accepted }
                NCDatabaseManager.sharedInstance().setPendingFederationInvitationForAccountId(activeAccount.accountId, with: self.pendingInvitations.count)

                if self.pendingInvitations.isEmpty {
                    self.dismiss(animated: true)
                    return
                }
            } else {
                self.pendingInvitations = []
            }

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
        return pendingInvitations.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = self.tableView.dequeueReusableCell(withIdentifier: federationInvitationCellIdentifier, for: indexPath) as? FederationInvitationCell
        else { return UITableViewCell() }

        let pendingInvitation = self.pendingInvitations[indexPath.row]
        cell.setupForInvitation(invitation: pendingInvitation)
        cell.delegate = self

        return cell
    }

    func federationInvitationCellAccept(_ cell: FederationInvitationCell, invitation: FederationInvitation) {
        self.showActivityIndicator()
        cell.setDisabledState()

        NCAPIController.sharedInstance().acceptFederationInvitation(for: invitation.accountId, with: invitation.invitationId) { [weak self] success in
            if !success {
                NotificationPresenter.shared().present(text: NSLocalizedString("Failed to accept invitation", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }

            self?.getData()
        }
    }

    func federationInvitationCellReject(_ cell: FederationInvitationCell, invitation: FederationInvitation) {
        self.showActivityIndicator()
        cell.setDisabledState()

        NCAPIController.sharedInstance().rejectFederationInvitation(for: invitation.accountId, with: invitation.invitationId) { [weak self] success in
            if !success {
                NotificationPresenter.shared().present(text: NSLocalizedString("Failed to reject invitation", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }

            self?.getData()
        }
    }
}
