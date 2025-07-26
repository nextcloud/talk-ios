//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Notification.Name {
    static let FederationInvitationDidAcceptNotification = Notification.Name(rawValue: "FederationInvitationDidAccept")
}

@objc extension NSNotification {
    public static let FederationInvitationDidAcceptNotification = Notification.Name.FederationInvitationDidAcceptNotification
}

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

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Pending invitations", comment: "")

        let barButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        barButtonItem.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.leftBarButtonItems = [barButtonItem]

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
            } else {
                NotificationCenter.default.post(name: .FederationInvitationDidAcceptNotification, object: self, userInfo: nil)
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
