//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import AudioToolbox
import Realm
import NextcloudKit

@objc(RoomsTableViewController)
class RoomsTableViewController: UITableViewController, CCCertificateDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating, UserStatusViewDelegate {

    private enum RoomsFilter: Int {
        case all = 0
        case unread
        case mentioned
        case event
    }

    private enum RoomsSection: Int, CaseIterable {
        case pendingFederationInvitation = 0
        case threads
        case archivedConversations
        case roomList
    }

    @objc public var selectedRoomToken: String? {
        didSet {
            highlightSelectedRoom()
        }
    }

    private var rlmNotificationToken: RLMNotificationToken?
    private var rooms: [NCRoom] = []
    private var allRooms: [NCRoom] = []
    private var threads: [NCThread]?
    private var showingArchivedRooms = false
    private var roomRefreshControl: UIRefreshControl!
    private var searchController: UISearchController!
    private var searchString: String?
    private var resultTableViewController: RoomSearchTableViewController!
    private var unifiedSearchController: NCUnifiedSearchController?
    private var roomsBackgroundView: PlaceholderView!
    private var newConversationButton: UIBarButtonItem?
    private var filterButton: UIBarButtonItem?
    private var settingsButton: UIBarButtonItem!
    private var profileButton: UIButton!
    private var activeUserStatus: NCUserStatus?
    private var refreshRoomsTimer: Timer?
    private var nextRoomWithMentionIndexPath: IndexPath?
    private var lastRoomWithMentionIndexPath: IndexPath?
    private var unreadMentionsBottomButton: UIButton!
    private var contextChatNavigationController: NCNavigationController?
    private var activeFilter: RoomsFilter = .all

    private var contextMenuActionBlock: (() -> Void)?

    // While a context menu is being displayed we defer room list reloads, otherwise reloading the
    // table moves the cells out from under the floating context menu preview, making it overlay
    // unrelated cells. Any refresh that arrives meanwhile is coalesced and applied once the menu ends.
    private var isContextMenuActive = false
    private var pendingRoomListRefresh = false

    override func viewDidLoad() {
        super.viewDidLoad()

        rlmNotificationToken = NCRoom.allObjects().addNotificationBlock { [weak self] _, _, _ in
            self?.refreshRoomList()
        }

        self.tableView.register(UINib(nibName: RoomTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: RoomTableViewCell.identifier)
        self.tableView.register(InfoLabelTableViewCell.self, forCellReuseIdentifier: InfoLabelTableViewCell.identifier)

        self.tableView.separatorStyle = .none

        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = UITableView.automaticDimension
        self.tableView.tableFooterView = UIView(frame: .zero)

        resultTableViewController = RoomSearchTableViewController(style: .insetGrouped)
        searchController = UISearchController(searchResultsController: resultTableViewController)
        searchController.searchResultsUpdater = self
        searchController.searchBar.sizeToFit()

        setupNavigationBar()

        // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
        resultTableViewController.tableView.delegate = self
        searchController.delegate = self
        searchController.searchBar.delegate = self

        self.definesPresentationContext = true

        // Rooms placeholder view
        roomsBackgroundView = PlaceholderView()
        roomsBackgroundView.placeholderView.isHidden = true
        roomsBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = roomsBackgroundView

        // Unread mentions bottom indicator
        unreadMentionsBottomButton = UIButton(frame: CGRect(x: 0, y: 0, width: 126, height: 28))
        unreadMentionsBottomButton.backgroundColor = NCAppBranding.themeColor()
        unreadMentionsBottomButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        unreadMentionsBottomButton.titleLabel?.font = .systemFont(ofSize: 14)
        unreadMentionsBottomButton.layer.cornerRadius = 14
        unreadMentionsBottomButton.clipsToBounds = true
        unreadMentionsBottomButton.isHidden = false
        unreadMentionsBottomButton.translatesAutoresizingMaskIntoConstraints = false
        unreadMentionsBottomButton.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 12.0, bottom: 0.0, right: 12.0)
        unreadMentionsBottomButton.titleLabel?.minimumScaleFactor = 0.9
        unreadMentionsBottomButton.titleLabel?.numberOfLines = 1
        unreadMentionsBottomButton.titleLabel?.adjustsFontSizeToFitWidth = true

        let unreadMentionsString = NSLocalizedString("Unread mentions", comment: "")
        let buttonText = "↓ \(unreadMentionsString)"
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
        let textSize = NSString(string: buttonText).boundingRect(with: CGSize(width: 300, height: 28), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        let buttonWidth = textSize.size.width + 20

        unreadMentionsBottomButton.addTarget(self, action: #selector(unreadMentionsBottomButtonPressed(_:)), for: .touchUpInside)
        unreadMentionsBottomButton.setTitle(buttonText, for: .normal)

        self.view.addSubview(unreadMentionsBottomButton)

        // Set selection color for selected cells
        self.tableView.tintColor = .clear

        // The title is used when long-pressing the back button in a conversation
        self.navigationItem.backButtonTitle = NSLocalizedString("Conversations", comment: "")

        let views: [String: Any] = ["unreadMentionsButton": unreadMentionsBottomButton as Any]
        let metrics: [String: Any] = ["buttonWidth": buttonWidth]
        let margins = self.view.layoutMarginsGuide

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(>=0)-[unreadMentionsButton(28)]-30-|", options: [], metrics: nil, views: views))
        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[unreadMentionsButton(buttonWidth)]-(>=0)-|", options: [], metrics: metrics, views: views))
        NSLayoutConstraint.activate([unreadMentionsBottomButton.centerXAnchor.constraint(equalTo: margins.centerXAnchor)])
        NSLayoutConstraint.activate([unreadMentionsBottomButton.bottomAnchor.constraint(equalTo: self.tableView.safeAreaLayoutGuide.bottomAnchor, constant: -20)])

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appStateHasChanged(_:)), name: .NCAppStateHasChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(connectionStateHasChanged(_:)), name: .NCConnectionStateHasChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(roomsDidUpdate(_:)), name: .NCRoomsManagerDidUpdateRooms, object: nil)
        notificationCenter.addObserver(self, selector: #selector(notificationWillBePresented(_:)), name: .NCNotificationControllerWillPresent, object: nil)
        notificationCenter.addObserver(self, selector: #selector(serverCapabilitiesUpdated(_:)), name: .NCServerCapabilitiesUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(userProfileImageUpdated(_:)), name: .NCUserProfileImageUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(roomCreated(_:)), name: .NCRoomCreated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(activeAccountDidChange(_:)), name: .NCSettingsControllerDidChangeActiveAccount, object: nil)
        notificationCenter.addObserver(self, selector: #selector(pendingInvitationsDidUpdate(_:)), name: NSNotification.Name(NCDatabaseManagerPendingFederationInvitationsDidChange), object: nil)
        notificationCenter.addObserver(self, selector: #selector(inviationDidAccept(_:)), name: .FederationInvitationDidAcceptNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(userThreadsUpdated(_:)), name: .NCUserThreadsUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(userHasThreadsUpdated(_:)), name: .NCUserHasThreadsFlagUpdated, object: nil)
    }

    private func configureFilterButtonInToolbar() {
        if #available(iOS 26, *) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                let account = NCDatabaseManager.sharedInstance().activeAccount()

                var menuChildren: [UIMenuElement] = []
                menuChildren.append(getFiltersSection(reversed: true))
                if NCSettingsController.sharedInstance().isRoomsSortingSupported(forAccountId: account.accountId) {
                    menuChildren.append(getGroupModeSection(reversed: true))
                    menuChildren.append(getSortOrderSection(reversed: true))
                }

                let menu = UIMenu(title: "", children: menuChildren)

                let filterBarButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), menu: menu)

                if activeFilter != .all {
                    filterBarButton.style = .prominent
                    filterBarButton.tintColor = NCAppBranding.elementColor()
                }

                self.setToolbarItems([
                    self.navigationItem.searchBarPlacementBarButtonItem,
                    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                    filterBarButton
                ], animated: true)

                self.navigationController?.setToolbarHidden(false, animated: true)
            }
        }
    }

    private func setupNavigationBar() {
        setNavigationLogoButton()
        configureRightBarButtonItems()
        createRefreshControl()

        self.navigationItem.searchController = searchController

        if #available(iOS 26.0, *) {
            self.tableView.backgroundColor = .clear

            // Set a solid background in collapsed mode, as otherwise we have a weird color transition
            // when navigating back in light mode
            if self.splitViewController?.isCollapsed == true {
                self.view.backgroundColor = .systemBackground
            } else {
                self.view.backgroundColor = .clear
            }
        } else {
            NCAppBranding.styleViewController(self)
        }
    }

    private func setNavigationLogoButton() {
        let logoImageView = UIImageView(image: NCAppBranding.navigationLogoImage())
        if !customNavigationLogo.boolValue {
            logoImageView.tintColor = .label
        }
        self.navigationItem.titleView = logoImageView
        self.navigationItem.titleView?.accessibilityLabel = talkAppName
    }

    private func configureRightBarButtonItems() {
        var rightItems: [UIBarButtonItem] = []

        // New conversation button
        if NCSettingsController.sharedInstance().canCreateGroupAndPublicRooms() ||
            NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms) {

            let newConversationButton = UIBarButtonItem(image: UIImage(systemName: "plus.circle.fill"), style: .plain, target: self, action: #selector(presentNewRoomViewController))
            newConversationButton.accessibilityLabel = NSLocalizedString("Create or join a conversation", comment: "")
            self.newConversationButton = newConversationButton
            rightItems.append(newConversationButton)
        }

        // Filter and sort button (only when not already in the iOS 26 toolbar menu)
        if !hasFilterAndSortMenuInToolbar() {
            let filterButton = UIBarButtonItem(image: nil, menu: getFilterAndSortMenu())
            filterButton.image = UIImage(systemName: (activeFilter != .all) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            filterButton.accessibilityLabel = NSLocalizedString("Filter and sort conversations", comment: "")
            self.filterButton = filterButton
            rightItems.append(filterButton)
        } else {
            configureFilterButtonInToolbar()
        }

        // iOS 26 style
        if #available(iOS 26.0, *) {
            newConversationButton?.tintColor = NCAppBranding.elementColor()

            if UIDevice.current.userInterfaceIdiom != .phone {
                // On non-iPhones we want to hide the shared background (glass effect)
                for item in rightItems {
                    item.hidesSharedBackground = true
                }
            } else {
                // On iPhones we want to have a prominent glass button with non-filled icon
                newConversationButton?.image = UIImage(systemName: "plus")
                newConversationButton?.style = .prominent
            }
        }

        self.navigationItem.rightBarButtonItems = rightItems
    }

    private func hasFilterAndSortMenuInToolbar() -> Bool {
        if #available(iOS 26, *) {
            return UIDevice.current.userInterfaceIdiom == .phone
        }
        return false
    }

    @objc private func presentNewRoomViewController() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let newRoomVC = NewRoomTableViewController(account: activeAccount)
        let navigationController = NCNavigationController(rootViewController: newRoomVC)
        self.present(navigationController, animated: true)
    }

    deinit {
        rlmNotificationToken?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        adaptInterface(forAppState: NCConnectionController.shared.appState)
        adaptInterface(forConnectionState: NCConnectionController.shared.connectionState)

        if NCSettingsController.sharedInstance().isContactSyncEnabled() && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityPhonebookSearch) {
            NCContactsManager.sharedInstance().searchInServer(forAddressBookContacts: false)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        refreshRoomList()

        self.clearsSelectionOnViewWillAppear = self.splitViewController?.isCollapsed ?? false

        if self.splitViewController?.isCollapsed == true {
            self.selectedRoomToken = nil
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stopRefreshRoomsTimer()

        // Reset deferred-refresh state in case the context menu was dismissed by navigating away
        // without a willEndContextMenuInteraction callback, so refreshes aren't skipped indefinitely.
        isContextMenuActive = false
        pendingRoomListRefresh = false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setProfileButton()
            setupNavigationBar()
        }
    }

    // MARK: - Notifications

    @objc private func appStateHasChanged(_ notification: Notification) {
        let appStateRaw = (notification.userInfo?["appState"] as? NSNumber)?.intValue ?? 0
        let appState = AppState(rawValue: appStateRaw) ?? .unknown
        adaptInterface(forAppState: appState)
    }

    @objc private func connectionStateHasChanged(_ notification: Notification) {
        let connectionStateRaw = (notification.userInfo?["connectionState"] as? NSNumber)?.intValue ?? 0
        let connectionState = ConnectionState(rawValue: connectionStateRaw) ?? .unknown
        adaptInterface(forConnectionState: connectionState)
    }

    @objc private func roomsDidUpdate(_ notification: Notification) {
        if let error = notification.userInfo?["error"] as? OcsError {
            NSLog("Error while trying to get rooms: %@", error.description)
            if error.underlyingError.code == NSURLErrorServerCertificateUntrusted {
                NSLog("Untrusted certificate")
                DispatchQueue.main.async {
                    CCCertificate.sharedManager().presentViewControllerCertificate(withTitle: error.underlyingError.localizedDescription, viewController: self, delegate: self)
                }
            }
        }

        roomRefreshControl?.endRefreshing()
    }

    @objc private func pendingInvitationsDidUpdate(_ notification: Notification) {
        refreshRoomList()
    }

    @objc private func inviationDidAccept(_ notification: Notification) {
        // We accepted an invitation, so we refresh the rooms from the API to show it directly
        refreshRooms()
    }

    @objc private func userThreadsUpdated(_ notification: Notification) {
        let accountId = notification.userInfo?["accountId"] as? String
        let threads = notification.userInfo?["threads"] as? [NCThread]

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if activeAccount.accountId == accountId {
            self.threads = threads
            refreshRoomList()
        }
    }

    @objc private func userHasThreadsUpdated(_ notification: Notification) {
        let accountId = notification.userInfo?["accountId"] as? String
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if activeAccount.accountId == accountId {
            refreshRoomList()
        }
    }

    @objc private func notificationWillBePresented(_ notification: Notification) {
        NCRoomsManager.shared.updateRoomsAndChats(updatingUserStatus: false, onlyLastModified: false, withCompletionBlock: nil)
        setUnreadMessageForInactiveAccountsIndicator()
    }

    @objc private func serverCapabilitiesUpdated(_ notification: Notification) {
        setupNavigationBar()
    }

    @objc private func userProfileImageUpdated(_ notification: Notification) {
        setProfileButton()
    }

    @objc private func appWillEnterForeground(_ notification: Notification) {
        if NCConnectionController.shared.appState == .ready {
            NCRoomsManager.shared.updateRoomsAndChats(updatingUserStatus: true, onlyLastModified: false, withCompletionBlock: nil)
            startRefreshRoomsTimer()

            DispatchQueue.main.async {
                // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
                self.setProfileButton()
                self.setUnreadMessageForInactiveAccountsIndicator()
            }
        }
    }

    @objc private func appWillResignActive(_ notification: Notification) {
        stopRefreshRoomsTimer()
    }

    @objc private func roomCreated(_ notification: Notification) {
        DispatchQueue.main.async {
            self.refreshRooms()
            let roomToken = notification.userInfo?["token"] as? String
            self.selectedRoomToken = roomToken
        }
    }

    @objc private func activeAccountDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.activeFilter = .all
            self.refreshRoomList()

            // Setup the navigation bar here, otherwise it would only be updated
            // when the capabilities were updated, which fails when the server is not reachable.
            self.setupNavigationBar()
        }
    }

    // MARK: - Refresh Timer

    private func startRefreshRoomsTimer() {
        stopRefreshRoomsTimer()
        refreshRoomsTimer = Timer.scheduledTimer(timeInterval: 30.0, target: self, selector: #selector(refreshRooms), userInfo: nil, repeats: true)
    }

    private func stopRefreshRoomsTimer() {
        refreshRoomsTimer?.invalidate()
        refreshRoomsTimer = nil
    }

    @objc private func refreshRooms() {
        NCRoomsManager.shared.updateRoomsAndChats(updatingUserStatus: true, onlyLastModified: false, withCompletionBlock: nil)

        if NCConnectionController.shared.connectionState == .connected {
            NCRoomsManager.shared.resendOfflineMessagesWithCompletionBlock(nil)
        }

        updateUserStatus()

        DispatchQueue.main.async {
            // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
            self.setUnreadMessageForInactiveAccountsIndicator()
        }
    }

    // MARK: - Refresh Control

    private func createRefreshControl() {
        roomRefreshControl = UIRefreshControl()

        if #available(iOS 26.0, *) {
            roomRefreshControl.tintColor = .label
        } else {
            roomRefreshControl.tintColor = NCAppBranding.themeTextColor()
        }

        roomRefreshControl.addTarget(self, action: #selector(refreshControlTarget), for: .valueChanged)
        self.tableView.refreshControl = roomRefreshControl
    }

    private func deleteRefreshControl() {
        roomRefreshControl?.endRefreshing()
        self.refreshControl = nil
    }

    @objc private func refreshControlTarget() {
        NCRoomsManager.shared.updateRoomsAndChats(updatingUserStatus: true, onlyLastModified: false, withCompletionBlock: nil)

        updateUserStatus()

        // Actuate `Peek` feedback (weak boom)
        AudioServicesPlaySystemSound(1519)
    }

    // MARK: - User Status SwiftUI View Delegate

    func userStatusViewDidDisappear() {
        updateUserStatus()
    }

    // MARK: - Title menu

    private func getActiveAccountMenuOptions() -> UIMenu {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)

        let userStatusDeferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }

            if serverCapabilities == nil || !(serverCapabilities?.userStatus ?? false) {
                completion([])
                return
            }

            NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { userStatus in
                guard let userStatus else {
                    completion([])
                    return
                }

                let userStatusImage = userStatus.getSFUserStatusIcon()
                let vc = UserStatusSwiftUIViewFactory.create(userStatus: userStatus, delegate: self)

                let onlineOption = UIAction(title: userStatus.readableUserStatusOrMessage(), image: userStatusImage, identifier: nil) { _ in
                    self.present(vc, animated: true)
                }

                self.activeUserStatus = userStatus
                self.updateProfileButtonImage()

                completion([onlineOption])
            }
        }

        return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [userStatusDeferred])
    }

    private func getInactiveAccountMenuOptions() -> UIDeferredMenuElement {
        // We use a deferred action here to always have an up-to-date list of inactive accounts and their notifications
        let inactiveAccountMenuDeferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }

            var inactiveAccounts: [UIMenuElement] = []

            for account in NCDatabaseManager.sharedInstance().inactiveAccounts() {
                let accountName = account.userDisplayName
                var accountImage = NCAPIController.sharedInstance().userProfileImage(forAccount: account, withStyle: self.traitCollection.userInterfaceStyle)

                if var image = accountImage {
                    image = NCUtils.roundedImage(fromImage: image)

                    // Draw a red circle to the image in case we have unread notifications for that account
                    if account.unreadNotification {
                        UIGraphicsBeginImageContextWithOptions(CGSize(width: 82, height: 82), false, 3)
                        let context = UIGraphicsGetCurrentContext()
                        image.draw(in: CGRect(x: 0, y: 4, width: 78, height: 78))
                        context?.saveGState()

                        context?.setFillColor(UIColor.systemRed.cgColor)
                        context?.fillEllipse(in: CGRect(x: 52, y: 0, width: 30, height: 30))

                        image = UIGraphicsGetImageFromCurrentImageContext() ?? image

                        UIGraphicsEndImageContext()
                    }

                    accountImage = image
                }

                let switchAccountAction = UIAction(title: accountName, image: accountImage, identifier: nil) { _ in
                    NCSettingsController.sharedInstance().setActiveAccountWithAccountId(account.accountId)
                }

                if account.unreadBadgeNumber > 0 {
                    switchAccountAction.subtitle = String.localizedStringWithFormat(NSLocalizedString("%ld notifications", comment: ""), account.unreadBadgeNumber)
                } else {
                    switchAccountAction.subtitle = account.server.replacingOccurrences(of: "https://", with: "")
                }

                inactiveAccounts.append(switchAccountAction)
            }

            if !inactiveAccounts.isEmpty {
                let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                var accountImage = NCAPIController.sharedInstance().userProfileImage(forAccount: activeAccount, withStyle: self.traitCollection.userInterfaceStyle)
                if let image = accountImage {
                    accountImage = NCUtils.roundedImage(fromImage: image)
                }
                let activeAccountAction = UIAction(title: activeAccount.userDisplayName, image: accountImage, identifier: nil) { _ in }
                activeAccountAction.subtitle = activeAccount.server.replacingOccurrences(of: "https://", with: "")
                activeAccountAction.state = .on
                inactiveAccounts.insert(activeAccountAction, at: 0)
            }

            let inactiveAccountsMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: inactiveAccounts)
            if #available(iOS 17.4, *) {
                let displayPreferences = UIMenuDisplayPreferences()
                displayPreferences.maximumNumberOfTitleLines = 1

                inactiveAccountsMenu.displayPreferences = displayPreferences
            }

            completion([inactiveAccountsMenu])
        }

        return inactiveAccountMenuDeferred
    }

    private func updateAccountPickerMenu() {
        var accountPickerMenu: [UIMenuElement] = []

        // When no elements are returned by the deferred menu, the entries / inline-menu will be hidden
        accountPickerMenu.append(getActiveAccountMenuOptions())
        accountPickerMenu.append(getInactiveAccountMenuOptions())

        var optionItems: [UIMenuElement] = []

        if multiAccountEnabled.boolValue {
            let addAccountOption = UIAction(title: NSLocalizedString("Add account", comment: ""), image: UIImage(systemName: "person.crop.circle.badge.plus")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal), identifier: nil) { _ in
                NCUserInterfaceController.sharedInstance().presentLoginViewController()
            }

            optionItems.append(addAccountOption)
        }

        let openSettingsOption = UIAction(title: NSLocalizedString("Settings", comment: ""), image: UIImage(systemName: "gear")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal), identifier: nil) { _ in
            NCDatabaseManager.sharedInstance().removeUnreadNotificationForInactiveAccounts()
            self.setUnreadMessageForInactiveAccountsIndicator()
            AppStoreReviewController.recordAction(AppStoreReviewController.visitAppSettings)
            NCUserInterfaceController.sharedInstance().presentSettingsViewController()
        }

        optionItems.append(openSettingsOption)

        let optionMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: optionItems)

        accountPickerMenu.append(optionMenu)

        profileButton.menu = UIMenu(title: "", children: accountPickerMenu)
        profileButton.showsMenuAsPrimaryAction = true
    }

    // MARK: - Search controller

    func updateSearchResults(for searchController: UISearchController) {
        let searchString = self.searchController.searchBar.text
        // Do not search for the same term twice (e.g. when the searchbar retrieves back the focus)
        if self.searchString == searchString { return }
        self.searchString = searchString
        // Cancel previous call to search listable rooms and messages
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(searchListableRoomsAndMessages), object: nil)

        // Search for listable rooms and messages
        if let searchString, !searchString.isEmpty {
            // Set searchingMessages flag if we are going to search for messages
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityUnifiedSearch) {
                setLoadMoreButtonHidden(true)
                resultTableViewController.searchingMessages = true
            }
            // Throttle listable rooms and messages search
            self.perform(#selector(searchListableRoomsAndMessages), with: nil, afterDelay: 1)
        } else {
            // Clear search results
            setLoadMoreButtonHidden(true)
            resultTableViewController.searchingMessages = false
            resultTableViewController.clearSearchedResults()
        }

        // Filter rooms
        filterRooms()
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        self.searchController.searchBar.text = ""
        filterRooms()
    }

    private func filterRooms() {
        let filteredRooms = filterRooms(with: activeFilter)

        let searchString = searchController.searchBar.text ?? ""
        if searchString.isEmpty {
            rooms = filteredRooms
            calculateLastRoomWithMention()
            self.tableView.reloadData()
            highlightSelectedRoom()
        } else {
            resultTableViewController.rooms = filterRooms(filteredRooms, with: searchString)
            calculateLastRoomWithMention()
        }

        updatePlaceholderView()
    }

    @objc private func searchListableRoomsAndMessages() {
        let searchString = searchController.searchBar.text
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        // Search for contacts
        resultTableViewController.users = []
        NCAPIController.sharedInstance().getContacts(forAccount: account, forRoom: nil, forGroupRoom: false, withSearchParam: searchString) { [weak self] contactList, error in
            guard let self else { return }
            if error == nil {
                var users = self.usersWithoutOneToOneConversations(contactList ?? [])
                if NCSettingsController.sharedInstance().isContactSyncEnabled() && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityPhonebookSearch) {
                    let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                    let addressBookContacts = NCContact.contacts(forAccountId: activeAccount.accountId, contains: nil)
                    users = NCUser.combineUsersArray(addressBookContacts, withUsersArray: users)
                }
                self.resultTableViewController.users = users
            }
        }
        // Search for listable rooms
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms) {
            resultTableViewController.listableRooms = []
            NCAPIController.sharedInstance().getListableRooms(forAccount: account, withSerachTerm: searchString) { [weak self] rooms, error in
                if error == nil {
                    self?.resultTableViewController.listableRooms = rooms ?? []
                }
            }
        }
        // Search for messages
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityUnifiedSearch) {
            unifiedSearchController = NCUnifiedSearchController(account: account, searchTerm: searchString ?? "")
            resultTableViewController.messages = []
            searchForMessagesWithCurrentSearchTerm()
        }
    }

    private func usersWithoutOneToOneConversations(_ users: [NCUser]) -> [NCUser] {
        let oneToOnePredicate = NSPredicate(format: "type == %ld", NCRoomType.oneToOne.rawValue)
        let oneToOneRooms = (rooms as NSArray).filtered(using: oneToOnePredicate)
        let names = (oneToOneRooms as NSArray).value(forKey: "name") as? [Any] ?? []
        let namePredicate = NSPredicate(format: "NOT (userId IN %@)", argumentArray: [names])

        return (users as NSArray).filtered(using: namePredicate) as? [NCUser] ?? []
    }

    private func searchForMessagesWithCurrentSearchTerm() {
        unifiedSearchController?.searchMessages { [weak self] entries in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resultTableViewController.searchingMessages = false
                self.resultTableViewController.messages = entries ?? []
                self.setLoadMoreButtonHidden(!(self.unifiedSearchController?.showMore ?? false))
            }
        }
    }

    private func filterRooms(with filter: RoomsFilter) -> [NCRoom] {
        let predicate: NSPredicate
        switch filter {
        case .unread:
            predicate = NSPredicate(format: "isVisible == YES AND unreadMessages > 0 AND isArchived == %@", NSNumber(value: showingArchivedRooms))
        case .mentioned:
            predicate = NSPredicate(format: "isVisible == YES AND hasUnreadMention == YES AND isArchived == %@", NSNumber(value: showingArchivedRooms))
        case .event:
            predicate = NSPredicate(format: "objectType == 'event' AND isArchived == %@", NSNumber(value: showingArchivedRooms))
        default:
            predicate = NSPredicate(format: "isVisible == YES AND isArchived == %@", NSNumber(value: showingArchivedRooms))
        }

        return (allRooms as NSArray).filtered(using: predicate) as? [NCRoom] ?? []
    }

    private func filterRooms(_ rooms: [NCRoom], with searchString: String) -> [NCRoom] {
        return (rooms as NSArray).filtered(using: NSPredicate(format: "displayName CONTAINS[c] %@", searchString)) as? [NCRoom] ?? []
    }

    private func setLoadMoreButtonHidden(_ hidden: Bool) {
        if !hidden {
            let loadMoreButton = UIButton(frame: CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 44))
            loadMoreButton.titleLabel?.font = .systemFont(ofSize: 15)
            loadMoreButton.setTitleColor(.systemBlue, for: .normal)
            loadMoreButton.setTitle(NSLocalizedString("Load more results", comment: ""), for: .normal)
            loadMoreButton.addTarget(self, action: #selector(loadMoreMessagesWithCurrentSearchTerm), for: .touchUpInside)
            resultTableViewController.tableView.tableFooterView = loadMoreButton
        } else {
            resultTableViewController.tableView.tableFooterView = nil
        }
    }

    @objc private func loadMoreMessagesWithCurrentSearchTerm() {
        if let unifiedSearchController, unifiedSearchController.searchTerm == searchController.searchBar.text {
            resultTableViewController.showSearchingFooterView()
            searchForMessagesWithCurrentSearchTerm()
        }
    }

    // MARK: - Rooms filter

    private func availableFilters() -> [RoomsFilter] {
        return [.all, .unread, .mentioned, .event]
    }

    private func filterName(_ filter: RoomsFilter) -> String {
        switch filter {
        case .all:
            return NSLocalizedString("No filter", comment: "'No filter' meaning 'No filter will be applied in conversations list'")
        case .unread:
            return NSLocalizedString("Unread", comment: "'Unread' meaning 'Unread conversations'")
        case .mentioned:
            return NSLocalizedString("Mentioned", comment: "'Mentioned' meaning 'Mentioned conversations'")
        case .event:
            return NSLocalizedString("Meetings", comment: "'Meetings' meaning 'Conversations that were created from a calendar event'")
        }
    }

    private func filterImage(_ filter: RoomsFilter) -> UIImage? {
        switch filter {
        case .all:
            return UIImage(named: "custom.line.3.horizontal.decrease.slash")
        case .unread:
            return UIImage(named: "custom.bubble.badge")
        case .mentioned:
            return UIImage(systemName: "at")
        case .event:
            return UIImage(systemName: "calendar")
        }
    }

    private func filterPlaceholderImage(_ filter: RoomsFilter) -> UIImage? {
        if filter == .all {
            return UIImage(named: "conversations-placeholder")
        }

        return filterImage(filter)
    }

    private func filterPlaceholderText(_ filter: RoomsFilter) -> String? {
        switch filter {
        case .all:
            return NSLocalizedString("You are not part of any conversation. Press + to start a new one.", comment: "")
        case .unread:
            return NSLocalizedString("You have no unread messages.", comment: "")
        case .mentioned:
            return NSLocalizedString("You have no unread mentions.", comment: "")
        case .event:
            return NSLocalizedString("You have no meetings scheduled.", comment: "")
        }
    }

    // MARK: - Sort menu

    private func getSortOrderSection(reversed: Bool) -> UIMenu {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        let currentSort = NCRoomSortOrder(rawValue: serverCapabilities?.roomsSortOrder ?? 0) ?? .activity

        let byActivity = UIAction(title: NSLocalizedString("By activity", comment: "Sort conversations by recent activity"), image: UIImage(systemName: "clock"), identifier: nil) { [weak self] _ in
            self?.applySortOrder(.activity)
        }
        byActivity.state = (currentSort == .activity) ? .on : .off

        let alphabetically = UIAction(title: NSLocalizedString("Alphabetically", comment: "Sort conversations alphabetically"), image: UIImage(systemName: "character.square"), identifier: nil) { [weak self] _ in
            self?.applySortOrder(.alphabetical)
        }
        alphabetically.state = (currentSort == .alphabetical) ? .on : .off

        let children: [UIMenuElement] = reversed ? [alphabetically, byActivity] : [byActivity, alphabetically]

        return UIMenu(title: NSLocalizedString("Sort conversations", comment: "Title for conversations sorting options"), image: nil, identifier: nil, options: .displayInline, children: children)
    }

    private func getGroupModeSection(reversed: Bool) -> UIMenu {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        let currentGroup = NCRoomGroupMode(rawValue: serverCapabilities?.roomsGroupMode ?? 0) ?? .none

        let noGrouping = UIAction(title: NSLocalizedString("No grouping", comment: "Do not group conversations by type"), image: UIImage(systemName: "list.bullet"), identifier: nil) { [weak self] _ in
            self?.applyGroupMode(.none)
        }
        noGrouping.state = (currentGroup == .none) ? .on : .off

        let privateFirst = UIAction(title: NSLocalizedString("Private first", comment: "Show private conversations before group ones"), image: UIImage(systemName: "person"), identifier: nil) { [weak self] _ in
            self?.applyGroupMode(.privateFirst)
        }
        privateFirst.state = (currentGroup == .privateFirst) ? .on : .off

        let groupFirst = UIAction(title: NSLocalizedString("Group first", comment: "Show group conversations before private ones"), image: UIImage(systemName: "person.2"), identifier: nil) { [weak self] _ in
            self?.applyGroupMode(.groupFirst)
        }
        groupFirst.state = (currentGroup == .groupFirst) ? .on : .off

        let children: [UIMenuElement] = reversed ? [groupFirst, privateFirst, noGrouping] : [noGrouping, privateFirst, groupFirst]

        return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: children)
    }

    private func getFiltersSection(reversed: Bool) -> UIMenu {
        var filterActions: [UIAction] = []

        for filterValue in availableFilters() {
            let action = UIAction(title: filterName(filterValue), image: filterImage(filterValue), identifier: nil) { [weak self] _ in
                guard let self else { return }

                self.activeFilter = filterValue
                self.filterRooms()
                self.configureRightBarButtonItems()
                self.updateMentionsIndicator()
            }

            action.state = (filterValue == activeFilter) ? .on : .off
            filterActions.append(action)
        }

        let children: [UIMenuElement] = reversed ? filterActions.reversed() : filterActions

        return UIMenu(title: NSLocalizedString("Filters", comment: "Title for available conversations filters"), image: nil, identifier: nil, options: .displayInline, children: children)
    }

    private func getFilterAndSortMenu() -> UIMenu {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        var children: [UIMenuElement] = []

        if NCSettingsController.sharedInstance().isRoomsSortingSupported(forAccountId: account.accountId) {
            children.append(getSortOrderSection(reversed: false))
            children.append(getGroupModeSection(reversed: false))
        }

        children.append(getFiltersSection(reversed: false))

        return UIMenu(title: "", children: children)
    }

    private func applySortOrder(_ sortOrder: NCRoomSortOrder) {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        Task {
            let success = await NCAPIController.sharedInstance().setRoomSortOrder(sortOrder, forAccount: account)
            if success {
                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(account.accountId) { _ in
                    DispatchQueue.main.async {
                        self.refreshRoomList()
                        self.configureRightBarButtonItems()
                    }
                }
            }
        }
    }

    private func applyGroupMode(_ groupMode: NCRoomGroupMode) {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        Task {
            let success = await NCAPIController.sharedInstance().setRoomGroupMode(groupMode, forAccount: account)
            if success {
                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(account.accountId) { _ in
                    DispatchQueue.main.async {
                        self.refreshRoomList()
                        self.configureRightBarButtonItems()
                    }
                }
            }
        }
    }

    // MARK: - User Interface

    @objc func refreshRoomList() {
        // Don't reload while a context menu is open, as that would detach the preview from its cell.
        // The refresh is applied once the context menu interaction ends.
        if isContextMenuActive {
            pendingRoomListRefresh = true
            return
        }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let accountRooms = NCDatabaseManager.sharedInstance().roomsForAccountId(account.accountId, withRealm: nil)
        allRooms = accountRooms
        rooms = accountRooms

        // Filter rooms
        filterRooms()

        // Update placeholder view
        updatePlaceholderView()

        // Reload room list
        self.tableView.reloadData()

        // Update unread mentions indicator
        updateMentionsIndicator()

        highlightSelectedRoom()
    }

    private func updatePlaceholderView() {
        roomsBackgroundView.loadingView.stopAnimating()
        roomsBackgroundView.loadingView.isHidden = true

        roomsBackgroundView.setImage(filterPlaceholderImage(activeFilter))
        roomsBackgroundView.placeholderTextView.text = filterPlaceholderText(activeFilter)
        roomsBackgroundView.placeholderView.isHidden = !rooms.isEmpty
    }

    private func adaptInterface(forAppState appState: AppState) {
        switch appState {
        case .noServerProvided, .missingUserProfile, .missingServerCapabilities, .missingSignalingConfiguration:
            // Clear active user status and threads when changing users
            activeUserStatus = nil
            threads = nil
            setProfileButton()
        case .ready:
            setProfileButton()
            let isAppActive = UIApplication.shared.applicationState == .active
            NCRoomsManager.shared.updateRooms(updatingUserStatus: isAppActive, onlyLastModified: false)
            updateUserStatus()
            getUserThreads()
            startRefreshRoomsTimer()
            setupNavigationBar()
        default:
            break
        }
    }

    private func adaptInterface(forConnectionState connectionState: ConnectionState) {
        switch connectionState {
        case .connected:
            setOnlineAppearance()
        case .disconnected:
            setOfflineAppearance()
        default:
            break
        }
    }

    private func setOfflineAppearance() {
        newConversationButton?.isEnabled = false
    }

    private func setOnlineAppearance() {
        newConversationButton?.isEnabled = true
    }

    // MARK: - UIScrollViewDelegate Methods

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == self.tableView {
            updateMentionsIndicator()
        }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == self.tableView {
            updateMentionsIndicator()
        }
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView == self.tableView {
            updateMentionsIndicator()
        }
    }

    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView == self.tableView {
            updateMentionsIndicator()
        }
    }

    // MARK: - Mentions

    private func updateMentionsIndicator() {
        let visibleRows = self.tableView.indexPathsForVisibleRows ?? []
        let lastVisibleRowIndexPath = visibleRows.last
        unreadMentionsBottomButton.isHidden = true

        // Calculate index of first room with a mention outside visible cells
        nextRoomWithMentionIndexPath = nil

        guard let lastRoomWithMentionIndexPath else {
            return
        }

        var i = lastVisibleRowIndexPath?.row ?? 0
        while i <= lastRoomWithMentionIndexPath.row && i < rooms.count {
            let room = rooms[i]
            if room.hasUnreadMention {
                nextRoomWithMentionIndexPath = IndexPath(row: i, section: RoomsSection.roomList.rawValue)
                break
            }
            i += 1
        }

        // Update unread mentions indicator visibility
        unreadMentionsBottomButton.isHidden = visibleRows.contains(lastRoomWithMentionIndexPath) || (lastVisibleRowIndexPath?.row ?? 0) > lastRoomWithMentionIndexPath.row

        // Make sure the style is adjusted to current accounts theme
        unreadMentionsBottomButton.backgroundColor = NCAppBranding.themeColor()
        unreadMentionsBottomButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
    }

    @objc private func unreadMentionsBottomButtonPressed(_ sender: Any) {
        if let nextRoomWithMentionIndexPath {
            self.tableView.scrollToRow(at: nextRoomWithMentionIndexPath, at: .middle, animated: true)
        }
    }

    private func calculateLastRoomWithMention() {
        lastRoomWithMentionIndexPath = nil
        for i in 0..<rooms.count {
            let room = rooms[i]
            if room.hasUnreadMention {
                lastRoomWithMentionIndexPath = IndexPath(row: i, section: RoomsSection.roomList.rawValue)
            }
        }
    }

    // MARK: - User profile

    private func setProfileButton() {
        profileButton = UIButton(type: .custom)
        profileButton.frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        profileButton.accessibilityLabel = NSLocalizedString("User profile and settings", comment: "")

        settingsButton = UIBarButtonItem(customView: profileButton)

        if #available(iOS 26.0, *) {
            if UIDevice.current.userInterfaceIdiom != .phone {
                // On non-iPhones we want to hide the shared background (glass effect)
                settingsButton.hidesSharedBackground = true
            }
        }

        self.navigationItem.leftBarButtonItem = settingsButton

        updateProfileButtonImage()
        updateAccountPickerMenu()
        setUnreadMessageForInactiveAccountsIndicator()
    }

    private func updateProfileButtonImage() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if var profileImage = NCAPIController.sharedInstance().userProfileImage(forAccount: activeAccount, withStyle: self.traitCollection.userInterfaceStyle) {
            // Crop the profile image into a circle
            profileImage = profileImage.cropToCircle(withSize: CGSize(width: 30, height: 30)) ?? profileImage
            // Increase the profile image size to leave space for the status
            profileImage = profileImage.withCircularBackground(backgroundColor: .separator, diameter: 32.0, padding: 1.0) ?? profileImage
            profileImage = profileImage.withCircularBackground(backgroundColor: .clear, diameter: 38.0, padding: 3.0) ?? profileImage

            // Online status icon
            var statusImage: UIImage?
            if activeUserStatus?.hasVisibleStatusIcon() == true {
                if #available(iOS 26.0, *) {
                    // TODO: Also cut out the avatar as we do in AvatarView?
                    statusImage = activeUserStatus?.getSFUserStatusIcon()?.withCircularBackground(backgroundColor: .clear, diameter: 14.0, padding: 1.0)
                } else {
                    statusImage = activeUserStatus?.getSFUserStatusIcon()?.withCircularBackground(backgroundColor: self.navigationController?.navigationBar.barTintColor ?? .clear, diameter: 14.0, padding: 1.0)
                }
            }

            // Status message icon
            if let icon = activeUserStatus?.icon, !icon.isEmpty {
                let iconLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
                iconLabel.text = icon
                iconLabel.adjustsFontSizeToFitWidth = true
                statusImage = UIImage.image(from: iconLabel)
            }

            // Set status image
            if let statusImage {
                profileImage = profileImage.overlay(with: statusImage, at: CGRect(x: 24, y: 24, width: 14, height: 14)) ?? profileImage
            }

            profileButton.setImage(profileImage, for: .normal)
            // Used to distinguish between a "completely loaded" button (with a profile image) and the default gear one
            profileButton.accessibilityIdentifier = "LoadedProfileButton"
        } else {
            profileButton.setImage(UIImage(systemName: "gear"), for: .normal)
            profileButton.contentMode = .center
        }
    }

    private func updateUserStatus() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { [weak self] userStatus in
            if let userStatus {
                self?.activeUserStatus = userStatus
                self?.updateProfileButtonImage()
            }
        }
    }

    private func setUnreadMessageForInactiveAccountsIndicator() {
        let inactiveUnreadCount = NCDatabaseManager.sharedInstance().numberOfInactiveAccountsWithUnreadNotifications()
        if inactiveUnreadCount > 0 {
            if #available(iOS 26.0, *) {
                settingsButton.badge = .count(inactiveUnreadCount)
            } else {
                settingsButton.legacyBadgeValue = "\(inactiveUnreadCount)"
            }
        }
    }

    // MARK: - Threads

    private func getUserThreads() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let currentTimestamp = Int(Date().timeIntervalSince1970)

        // Check if user has threads on app fresh launch or if last check was over 2 hours ago
        if (currentTimestamp - activeAccount.threadsLastCheckTimestamp) > (2 * 60 * 60) {
            NCAPIController.sharedInstance().getSubscribedThreads(for: activeAccount.accountId, withLimit: 100, andOffset: 0) { _, error in
                if let error {
                    NSLog("Error getting user threads: %@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - CCCertificateDelegate

    func trustedCerticateAccepted() {
        NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
    }

    // MARK: - Room actions

    private func actionForNotificationLevel(_ level: NCRoomNotificationLevel, forRoom room: NCRoom) -> UIAction {
        let notificationAction = UIAction(title: NCRoom.stringFor(notificationLevel: level), image: nil, identifier: nil) { _ in
            if level == room.notificationLevel {
                return
            }
            Task { @MainActor in
                let success = await NCAPIController.sharedInstance().setNotificationLevel(level: level, forRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                if success {
                    NotificationPresenter.shared().present(text: NSLocalizedString("Updated notification settings", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                } else {
                    NSLog("Error setting notification level")
                }

                NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
            }
        }

        if room.notificationLevel == level {
            notificationAction.state = .on
        }

        return notificationAction
    }

    private func shareLink(fromRoom room: NCRoom) {
        if let indexPath = indexPath(for: room) {
            NCUserInterfaceController.sharedInstance().presentShareLinkDialog(for: room, inViewContoller: self, for: indexPath)
        }
    }

    private func archiveRoom(_ room: NCRoom) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().archiveRoom(room.token, forAccount: activeAccount) { success in
            if !success {
                NSLog("Error archiving room")
            }

            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func unarchiveRoom(_ room: NCRoom) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().unarchiveRoom(room.token, forAccount: activeAccount) { success in
            if !success {
                NSLog("Error unarchiving room")
            }

            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func markRoomAsRead(_ room: NCRoom) {
        NCAPIController.sharedInstance().setChatReadMarker(room.lastMessage?.messageId ?? 0, inRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount()) { error in
            if let error {
                NSLog("Error marking room as read: %@", error.description)
            }
            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func markRoomAsUnread(_ room: NCRoom) {
        NCAPIController.sharedInstance().markChatAsUnread(inRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount()) { error in
            if let error {
                NSLog("Error marking chat as unread: %@", error.description)
            }
            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func addRoomToFavorites(_ room: NCRoom) {
        NCAPIController.sharedInstance().addRoomToFavorites(room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount()) { error in
            if let error {
                NSLog("Error adding room to favorites: %@", error.description)
            }
            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func removeRoomFromFavorites(_ room: NCRoom) {
        NCAPIController.sharedInstance().removeRoomFromFavorites(room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount()) { error in
            if let error {
                NSLog("Error removing room from favorites: %@", error.description)
            }
            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
        }
    }

    private func presentRoomInfo(forRoom room: NCRoom) {
        let roomInfoVC = RoomInfoUIViewFactory.create(room: room, showDestructiveActions: true, scrollToParticipantsSectionOnAppear: false)
        let navigationController = NCNavigationController(rootViewController: roomInfoVC)

        let cancelAction = UIAction { _ in
            roomInfoVC.dismiss(animated: true)
        }

        let cancelButton = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelAction)
        navigationController.navigationBar.topItem?.leftBarButtonItem = cancelButton

        self.present(navigationController, animated: true)
    }

    private func leaveRoom(_ room: NCRoom) {
        let confirmDialog = UIAlertController(title: NSLocalizedString("Leave conversation", comment: ""),
                                              message: NSLocalizedString("Once a conversation is left, to rejoin a closed conversation, an invite is needed. An open conversation can be rejoined at any time.", comment: ""),
                                              preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: NSLocalizedString("Leave", comment: ""), style: .destructive) { _ in
            NCUserInterfaceController.sharedInstance().presentConversationsList()

            if let indexPath = self.indexPath(for: room) {
                self.rooms.remove(at: indexPath.row)
                self.tableView.deleteRows(at: [indexPath], with: .fade)
            }

            Task { @MainActor in
                do {
                    _ = try await NCAPIController.sharedInstance().removeSelf(fromRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                } catch let ocsError as OcsError {
                    if ocsError.responseStatusCode == 400 {
                        self.showLeaveRoomLastModeratorError(forRoom: room)
                    } else {
                        NSLog("Error leaving room: %@", ocsError.description)
                    }
                } catch {
                    NSLog("Error leaving room: %@", error.localizedDescription)
                }

                NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
            }
        }
        confirmDialog.addAction(confirmAction)
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        confirmDialog.addAction(cancelAction)
        self.present(confirmDialog, animated: true)
    }

    private func deleteRoom(_ room: NCRoom) {
        NCRoomsManager.shared.deleteRoom(withConfirmation: room, withStartedBlock: {
            if let indexPath = self.indexPath(for: room) {
                self.rooms.remove(at: indexPath.row)
                self.tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }, withFinishedBlock: nil)
    }

    private func presentChatForRoom(at indexPath: IndexPath) {
        guard let room = room(for: indexPath) else { return }
        let currentChatViewController = NCRoomsManager.shared.chatViewController

        // When a room is selected, that is currently displayed, leave that room and optionally show the placeholder view again
        if let currentChatViewController, room.token == currentChatViewController.room.token {
            currentChatViewController.leaveChat()
            NCUserInterfaceController.sharedInstance().mainViewController.showPlaceholderView()

            return
        }

        NCRoomsManager.shared.startChat(inRoom: room)
    }

    // MARK: - Utils

    private func room(for indexPath: IndexPath) -> NCRoom? {
        if searchController.isActive && !resultTableViewController.view.isHidden {
            return resultTableViewController.room(for: indexPath)
        } else if indexPath.row < rooms.count {
            return rooms[indexPath.row]
        }

        return nil
    }

    private func indexPath(for room: NCRoom) -> IndexPath? {
        if let idx = rooms.firstIndex(where: { $0.internalId == room.internalId }) {
            return IndexPath(row: idx, section: RoomsSection.roomList.rawValue)
        }

        return nil
    }

    private func archivedRooms() -> [NCRoom] {
        return (allRooms as NSArray).filtered(using: NSPredicate(format: "isArchived == YES")) as? [NCRoom] ?? []
    }

    private func areArchivedRoomsWithUnreadMentions() -> Bool {
        return !(allRooms as NSArray).filtered(using: NSPredicate(format: "hasUnreadMention == YES AND isArchived == YES")).isEmpty
    }

    private func showLeaveRoomLastModeratorError(forRoom room: NCRoom) {
        let leaveRoomFailedDialog = UIAlertController(title: NSLocalizedString("Could not leave conversation", comment: ""),
                                                      message: String(format: NSLocalizedString("You need to promote a new moderator before you can leave %@.", comment: ""), room.displayName),
                                                      preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        leaveRoomFailedDialog.addAction(okAction)

        self.present(leaveRoomFailedDialog, animated: true)
    }

    // MARK: - Search results

    private func presentSelectedMessageInChat(_ message: NKSearchEntry) {
        let roomToken = message.attributes?["conversation"] as? String
        let messageIdString = message.attributes?["messageId"] as? String
        let threadIdString = message.attributes?["threadId"] as? String
        if let roomToken, let messageIdString {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            let messageId = (messageIdString as NSString).integerValue
            let room = NCDatabaseManager.sharedInstance().room(withToken: roomToken, forAccountId: activeAccount.accountId)
            let threadId = (threadIdString as NSString?)?.integerValue ?? 0
            let thread = NCThread(threadId: threadId, inRoom: roomToken, forAccountId: activeAccount.accountId)
            if let room {
                presentContextChat(inRoom: room, inThread: thread, forMessageId: messageId)
            } else {
                NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: roomToken) { [weak self] roomDict, error in
                    if error == nil {
                        if let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {
                            self?.presentContextChat(inRoom: room, inThread: thread, forMessageId: messageId)
                        }
                    } else {
                        let errorMessage = NSLocalizedString("Unable to get conversation of the message", comment: "")
                        NotificationPresenter.shared().present(text: errorMessage, dismissAfterDelay: 5.0, includedStyle: .dark)
                    }
                }
            }
        }
    }

    private func presentContextChat(inRoom room: NCRoom, inThread thread: NCThread?, forMessageId messageId: Int) {
        guard let account = room.account else {
            return
        }

        guard let contextChatViewController = ContextChatViewController(forRoom: room, withAccount: account, withMessage: [], withHighlightId: 0) else {
            return
        }
        contextChatViewController.thread = thread
        contextChatViewController.showContext(ofMessageId: messageId, withLimit: 50, withCloseButton: true)

        let contextChatNavigationController = NCNavigationController(rootViewController: contextChatViewController)
        self.contextChatNavigationController = contextChatNavigationController
        self.present(contextChatNavigationController, animated: true)
    }

    private func createRoom(forSelectedUser user: NCUser) {
        NCAPIController.sharedInstance().createRoom(forAccount: NCDatabaseManager.sharedInstance().activeAccount(), withInvite: user.userId, ofType: .oneToOne, andName: nil) { [weak self] room, error in
            if error == nil, let token = room?.token {
                self?.navigationController?.dismiss(animated: true) {
                    NotificationCenter.default.post(name: .NCSelectedUserForChat, object: self, userInfo: ["token": token])
                }
            }

            self?.searchController.isActive = false
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return RoomsSection.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == RoomsSection.pendingFederationInvitation.rawValue {
            let account = NCDatabaseManager.sharedInstance().activeAccount()
            return account.pendingFederationInvitations > 0 ? 1 : 0
        }

        if section == RoomsSection.archivedConversations.rawValue {
            return (!archivedRooms().isEmpty || showingArchivedRooms) ? 1 : 0
        }

        if section == RoomsSection.threads.rawValue {
            let account = NCDatabaseManager.sharedInstance().activeAccount()
            return (account.hasThreads || (threads?.count ?? 0) > 0) ? 1 : 0
        }

        return rooms.count
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if tableView == self.tableView &&
            (indexPath.section == RoomsSection.pendingFederationInvitation.rawValue ||
             indexPath.section == RoomsSection.archivedConversations.rawValue ||
             indexPath.section == RoomsSection.threads.rawValue) {
            // No swipe action for pending invitations or archived conversations
            return nil
        }

        guard let room = room(for: indexPath) else {
            return nil
        }

        // Do not show swipe actions for open conversations or messages
        if tableView == resultTableViewController.tableView && room.listable != .participantsOnly {
            return nil
        }

        var deleteAction = UIContextualAction(style: .destructive, title: nil) { _, _, completionHandler in
            self.deleteRoom(room)
            completionHandler(false)
        }
        deleteAction.image = UIImage(systemName: "trash")

        if room.canLeaveConversation {
            deleteAction = UIContextualAction(style: .destructive, title: nil) { _, _, completionHandler in
                self.leaveRoom(room)
                completionHandler(false)
            }
            deleteAction.image = UIImage(systemName: "arrow.right.square")
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if tableView == self.tableView &&
            (indexPath.section == RoomsSection.pendingFederationInvitation.rawValue ||
             indexPath.section == RoomsSection.archivedConversations.rawValue ||
             indexPath.section == RoomsSection.threads.rawValue) {
            // No swipe action for pending invitations or archived conversations
            return nil
        }

        guard let room = room(for: indexPath) else {
            return nil
        }

        // Do not show swipe actions for open conversations or messages
        if tableView == resultTableViewController.tableView && room.listable != .participantsOnly {
            return nil
        }

        // Add/Remove room to/from favorites
        let favoriteAction = UIContextualAction(style: .normal, title: nil) { _, _, completionHandler in
            if room.isFavorite {
                self.removeRoomFromFavorites(room)
            } else {
                self.addRoomToFavorites(room)
            }
            completionHandler(true)
        }
        let favImageName = room.isFavorite ? "star" : "star.fill"
        favoriteAction.image = UIImage(systemName: favImageName)
        favoriteAction.backgroundColor = UIColor(red: 0.97, green: 0.80, blue: 0.27, alpha: 1.0) // Favorite yellow

        // Mark room as read/unread
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadMarker) &&
            (!room.isFederated || NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadLast)) {

            let markReadAction = UIContextualAction(style: .normal, title: nil) { _, _, completionHandler in
                if room.unreadMessages > 0 {
                    self.markRoomAsRead(room)
                } else {
                    self.markRoomAsUnread(room)
                }
                completionHandler(true)
            }

            markReadAction.image = (room.unreadMessages > 0) ? UIImage(systemName: "checkmark.bubble") : UIImage(named: "custom.bubble.badge")
            markReadAction.backgroundColor = .systemBlue

            return UISwipeActionsConfiguration(actions: [markReadAction, favoriteAction])
        }

        return UISwipeActionsConfiguration(actions: [favoriteAction])
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == RoomsSection.pendingFederationInvitation.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: InfoLabelTableViewCell.identifier) as? InfoLabelTableViewCell ?? InfoLabelTableViewCell(style: .default, reuseIdentifier: InfoLabelTableViewCell.identifier)

            // Pending federation invitations
            let account = NCDatabaseManager.sharedInstance().activeAccount()

            let pendingInvitationsString = String.localizedStringWithFormat(NSLocalizedString("You have %ld pending invitations", comment: ""), account.pendingFederationInvitations)
            let resultFont = UIFont.preferredFont(forTextStyle: .headline)

            let pendingInvitationsAttachment = NSTextAttachment()
            pendingInvitationsAttachment.image = UIImage(named: "pending-federation-invitations")
            pendingInvitationsAttachment.bounds = CGRect(x: 0, y: CGFloat(roundf(Float(resultFont.capHeight) - 20)) / 2, width: 20, height: 20)

            let resultString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: pendingInvitationsAttachment))
            resultString.append(NSAttributedString(string: "  "))
            resultString.append(NSAttributedString(string: pendingInvitationsString))

            let range = NSRange(location: 0, length: resultString.length)
            resultString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .headline), range: range)

            cell.label.attributedText = resultString

            return cell
        }

        if indexPath.section == RoomsSection.archivedConversations.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: InfoLabelTableViewCell.identifier) as? InfoLabelTableViewCell ?? InfoLabelTableViewCell(style: .default, reuseIdentifier: InfoLabelTableViewCell.identifier)

            let actionString = showingArchivedRooms ? NSLocalizedString("Back to conversations", comment: "") : NSLocalizedString("Archived conversations", comment: "")
            let iconName = showingArchivedRooms ? "arrow.left" : "archivebox"
            let resultFont = UIFont.preferredFont(forTextStyle: .headline)

            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: iconName)?.withRenderingMode(.alwaysTemplate)
            attachment.bounds = CGRect(x: 0, y: CGFloat(roundf(Float(resultFont.capHeight) - 20)) / 2, width: 24, height: 20)

            let resultString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            resultString.append(NSAttributedString(string: "  "))
            resultString.append(NSAttributedString(string: actionString))

            let range = NSRange(location: 0, length: resultString.length)
            resultString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .headline), range: range)

            if !showingArchivedRooms && areArchivedRoomsWithUnreadMentions() {
                let mentionAttachment = NSTextAttachment()
                mentionAttachment.image = UIImage(systemName: "circle.fill")?.withTintColor(NCAppBranding.elementColor(), renderingMode: .alwaysTemplate)
                mentionAttachment.bounds = CGRect(x: 0, y: CGFloat(roundf(Float(resultFont.capHeight) - 20)) / 2, width: 20, height: 20)

                resultString.append(NSAttributedString(string: "  "))
                resultString.append(NSAttributedString(attachment: mentionAttachment))
            }

            cell.label.attributedText = resultString

            return cell
        }

        if indexPath.section == RoomsSection.threads.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: InfoLabelTableViewCell.identifier) as? InfoLabelTableViewCell ?? InfoLabelTableViewCell(style: .default, reuseIdentifier: InfoLabelTableViewCell.identifier)

            let resultFont = UIFont.preferredFont(forTextStyle: .headline)
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: "bubble.left.and.bubble.right")?.withRenderingMode(.alwaysTemplate)
            attachment.bounds = CGRect(x: 0, y: CGFloat(roundf(Float(resultFont.capHeight) - 20)) / 2, width: 24, height: 20)

            let resultString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            resultString.append(NSAttributedString(string: "  "))
            resultString.append(NSAttributedString(string: NSLocalizedString("Threads", comment: "")))

            let range = NSRange(location: 0, length: resultString.length)
            resultString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .headline), range: range)

            cell.label.attributedText = resultString
            cell.separatorInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: .greatestFiniteMagnitude)

            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: RoomTableViewCell.identifier) as? RoomTableViewCell ?? RoomTableViewCell(style: .default, reuseIdentifier: RoomTableViewCell.identifier)

        cell.backgroundColor = .clear

        let room = rooms[indexPath.row]

        // Set room name
        cell.titleLabel.text = room.displayName

        // Set last activity
        if room.lastMessageId != nil || room.lastMessageProxiedJSONString != nil {
            cell.titleOnly = false
            cell.subtitleLabel.attributedText = room.lastMessageString
        } else {
            cell.titleOnly = true
            cell.subtitleLabel.text = ""
        }
        let date = Date(timeIntervalSince1970: TimeInterval(room.lastActivity))
        cell.dateLabel.text = NCUtils.readableTimeOrDate(fromDate: date)

        // Event conversation handling
        if room.isFutureEvent {
            cell.titleOnly = false
            cell.subtitleLabel.text = room.eventStartString
            cell.dateLabel.text = ""
        }

        // Set unread messages
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDirectMentionFlag) {
            let mentioned = room.unreadMentionDirect || room.type == .oneToOne || room.type == .formerOneToOne
            let groupMentioned = room.unreadMention && !room.unreadMentionDirect
            cell.setUnread(messages: room.unreadMessages, mentioned: mentioned, groupMentioned: groupMentioned)
        } else {
            let mentioned = room.unreadMention || room.type == .oneToOne || room.type == .formerOneToOne
            cell.setUnread(messages: room.unreadMessages, mentioned: mentioned, groupMentioned: false)
        }

        if room.unreadMessages > 0 {
            // When there are unread messages, we need to show the subtitle at the moment
            cell.titleOnly = false
        }

        cell.avatarView.setAvatar(for: room)

        // Set favorite or call image
        if room.hasCall {
            cell.avatarView.favoriteImageView.tintColor = .systemRed
            cell.avatarView.favoriteImageView.image = UIImage(systemName: "video.fill")
        } else if room.isFavorite {
            cell.avatarView.favoriteImageView.tintColor = .systemYellow
            cell.avatarView.favoriteImageView.image = UIImage(systemName: "star.fill")
        }

        cell.roomToken = room.token

        return cell
    }

    override func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as? RoomTableViewCell
        cell?.isSelected = true
    }

    override func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as? RoomTableViewCell
        cell?.isSelected = false
    }

    override func tableView(_ tableView: UITableView, willDisplay rcell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if tableView != self.tableView ||
            indexPath.section == RoomsSection.pendingFederationInvitation.rawValue ||
            indexPath.section == RoomsSection.archivedConversations.rawValue ||
            indexPath.section == RoomsSection.threads.rawValue {
            return
        }

        guard let cell = rcell as? RoomTableViewCell else { return }
        let room = rooms[indexPath.row]

        cell.avatarView.setStatus(for: room, allowCustomStatusIcon: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let isAppInForeground = UIApplication.shared.applicationState == .active

        if !isAppInForeground {
            // In case we are not in the active state, we don't want to invoke any navigation event as this might
            // lead to crashes, when the wrong NavBar is referenced
            return
        }

        if self.navigationController?.transitionCoordinator != nil {
            // In case we are currently in a transition (e.g. swipe back from a conversation),
            // we don't want to present any new view controller, as that leads to crashes on iOS >= 26
            removeRoomSelection()
            return
        }

        if tableView == self.tableView && indexPath.section == RoomsSection.pendingFederationInvitation.rawValue {
            let federationInvitationVC = FederationInvitationTableViewController()
            let navigationController = NCNavigationController(rootViewController: federationInvitationVC)
            self.present(navigationController, animated: true)

            return
        }

        if tableView == self.tableView && indexPath.section == RoomsSection.archivedConversations.rawValue {
            showingArchivedRooms = !showingArchivedRooms
            UIView.transition(with: self.tableView, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.filterRooms()
                self.updateMentionsIndicator()
            }, completion: nil)
            return
        }

        if tableView == self.tableView && indexPath.section == RoomsSection.threads.rawValue {
            UIView.transition(with: self.tableView, duration: 0.2, options: .transitionCrossDissolve, animations: {
                let threadsVC = ThreadsTableViewController(threads: self.threads)
                let navigationController = NCNavigationController(rootViewController: threadsVC)
                self.present(navigationController, animated: true)
            }, completion: nil)
            return
        }

        if tableView == resultTableViewController.tableView {
            // Messages
            if let message = resultTableViewController.message(for: indexPath) {
                presentSelectedMessageInChat(message)
                return
            }

            // Users
            if let user = resultTableViewController.user(for: indexPath) {
                createRoom(forSelectedUser: user)
                return
            }
        }

        // Present room chat
        removeRoomSelection()
        presentChatForRoom(at: indexPath)
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if tableView != self.tableView ||
            indexPath.section == RoomsSection.pendingFederationInvitation.rawValue ||
            indexPath.section == RoomsSection.archivedConversations.rawValue ||
            indexPath.section == RoomsSection.threads.rawValue {
            return nil
        }

        guard let room = room(for: indexPath) else { return nil }
        var actions: [UIMenuElement] = []

        let favImageName = room.isFavorite ? "star.slash" : "star"
        let favImage = UIImage(systemName: favImageName)?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        let favActionName = room.isFavorite ? NSLocalizedString("Remove from favorites", comment: "") : NSLocalizedString("Add to favorites", comment: "")
        let favAction = UIAction(title: favActionName, image: favImage, identifier: nil) { [weak self] _ in
            self?.contextMenuActionBlock = {
                if room.isFavorite {
                    self?.removeRoomFromFavorites(room)
                } else {
                    self?.addRoomToFavorites(room)
                }
            }
        }

        actions.append(favAction)

        // Mark room as read/unread
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadMarker) &&
            (!room.isFederated || NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadLast)) {
            if room.unreadMessages > 0 {
                // Mark room as read
                let markReadAction = UIAction(title: NSLocalizedString("Mark as read", comment: ""), image: UIImage(systemName: "checkmark.bubble"), identifier: nil) { [weak self] _ in
                    self?.contextMenuActionBlock = {
                        self?.markRoomAsRead(room)
                    }
                }

                actions.append(markReadAction)
            } else if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatUnread) {
                // Mark room as unread
                let markUnreadAction = UIAction(title: NSLocalizedString("Mark as unread", comment: ""), image: UIImage(named: "custom.bubble.badge"), identifier: nil) { [weak self] _ in
                    self?.contextMenuActionBlock = {
                        self?.markRoomAsUnread(room)
                    }
                }

                actions.append(markUnreadAction)
            }
        }

        // Notification levels
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityNotificationLevels) &&
            room.type != .changelog && room.type != .noteToSelf {

            var notificationActions: [UIMenuElement] = []

            // Chat notification settings
            notificationActions.append(actionForNotificationLevel(.always, forRoom: room))
            notificationActions.append(actionForNotificationLevel(.mention, forRoom: room))
            notificationActions.append(actionForNotificationLevel(.never, forRoom: room))

            // Call notification
            if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityNotificationCalls, for: room) && room.supportsCalling {
                let callNotificationAction = UIAction(title: NSLocalizedString("Notify about calls", comment: ""), image: nil, identifier: nil) { action in
                    let newState = !(action.state == .on)

                    Task { @MainActor in
                        let success = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: newState, forRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                        if success {
                            NotificationPresenter.shared().present(text: NSLocalizedString("Updated notification settings", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                        } else {
                            NSLog("Error setting call notification")
                        }

                        NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
                    }
                }

                if room.notificationCalls {
                    callNotificationAction.state = .on
                }

                let callNotificationMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [callNotificationAction])
                notificationActions.append(callNotificationMenu)
            }

            // Important conversation
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityImportantConversations) {
                let importantConversationAction = UIAction(title: NSLocalizedString("Important conversation", comment: ""), image: nil, identifier: nil) { action in
                    let newState = !(action.state == .on)

                    Task { @MainActor in
                        do {
                            _ = try await NCAPIController.sharedInstance().setImportantState(enabled: newState, forRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                            NotificationPresenter.shared().present(text: NSLocalizedString("Updated notification settings", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                        } catch {
                            NSLog("Error setting call notification: %@", error.localizedDescription)
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
                        }
                    }
                }

                importantConversationAction.subtitle = NSLocalizedString("'Do not disturb' user status is ignored for important conversations", comment: "")

                if room.isImportant {
                    importantConversationAction.state = .on
                }

                let importantConversationMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [importantConversationAction])
                notificationActions.append(importantConversationMenu)
            }

            // Sensitive conversation
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySensitiveConversations) {
                let sensitiveConversationAction = UIAction(title: NSLocalizedString("Sensitive conversation", comment: ""), image: nil, identifier: nil) { action in
                    let newState = !(action.state == .on)

                    Task { @MainActor in
                        do {
                            _ = try await NCAPIController.sharedInstance().setSensitiveState(enabled: newState, forRoom: room.token, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                            NotificationPresenter.shared().present(text: NSLocalizedString("Updated notification settings", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                        } catch {
                            NSLog("Error setting call notification: %@", error.localizedDescription)
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NCRoomsManager.shared.updateRooms(updatingUserStatus: true, onlyLastModified: false)
                        }
                    }
                }

                sensitiveConversationAction.subtitle = NSLocalizedString("Message preview will be disabled in conversation list and notifications", comment: "")

                if room.isSensitive {
                    sensitiveConversationAction.state = .on
                }

                let sensitiveConversationMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [sensitiveConversationAction])
                notificationActions.append(sensitiveConversationMenu)
            }

            let notificationMenu = UIMenu(title: NSLocalizedString("Notifications", comment: ""), image: UIImage(systemName: "bell"), identifier: nil, options: [], children: notificationActions)

            actions.append(notificationMenu)
        }

        // Share link
        if room.type != .changelog && room.type != .noteToSelf {
            let shareLinkAction = UIAction(title: NSLocalizedString("Share link", comment: ""), image: UIImage(systemName: "square.and.arrow.up"), identifier: nil) { [weak self] _ in
                self?.shareLink(fromRoom: room)
            }

            actions.append(shareLinkAction)
        }

        // Archive conversation
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityArchivedConversationsV2) {
            if room.isArchived {
                let unarchiveAction = UIAction(title: NSLocalizedString("Unarchive conversation", comment: ""), image: UIImage(systemName: "arrow.up.bin"), identifier: nil) { [weak self] _ in
                    self?.unarchiveRoom(room)
                }

                actions.append(unarchiveAction)
            } else {
                let archiveAction = UIAction(title: NSLocalizedString("Archive conversation", comment: ""), image: UIImage(systemName: "archivebox"), identifier: nil) { [weak self] _ in
                    self?.archiveRoom(room)
                }

                actions.append(archiveAction)
            }
        }

        // Room info
        let roomInfoAction = UIAction(title: NSLocalizedString("Conversation settings", comment: ""), image: UIImage(systemName: "gearshape"), identifier: nil) { [weak self] _ in
            self?.presentRoomInfo(forRoom: room)
        }

        actions.append(roomInfoAction)

        var destructiveActions: [UIMenuElement] = []

        if room.canLeaveConversation {
            let leaveAction = UIAction(title: NSLocalizedString("Leave conversation", comment: ""), image: UIImage(systemName: "arrow.right.square"), identifier: nil) { [weak self] _ in
                self?.leaveRoom(room)
            }

            leaveAction.attributes = .destructive
            destructiveActions.append(leaveAction)
        }

        if room.canDeleteConversation {
            let deleteAction = UIAction(title: NSLocalizedString("Delete conversation", comment: ""), image: UIImage(systemName: "trash"), identifier: nil) { [weak self] _ in
                self?.deleteRoom(room)
            }

            deleteAction.attributes = .destructive
            destructiveActions.append(deleteAction)
        }

        if !destructiveActions.isEmpty {
            let deleteMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: destructiveActions)

            actions.append(deleteMenu)
        }

        let menu = UIMenu(title: "", children: actions)

        let configuration = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: { () -> UIViewController? in
            return nil
        }, actionProvider: { _ -> UIMenu? in
            return menu
        })

        return configuration
    }

    override func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if tableView != self.tableView {
            return nil
        }

        guard let indexPath = configuration.identifier as? IndexPath else { return nil }

        // Use a snapshot and a new cell (from dataSource) here to not interfere with room refresh
        guard let cell = self.tableView.dataSource?.tableView(self.tableView, cellForRowAt: indexPath) else { return nil }
        guard let previewView = cell.contentView.snapshotView(afterScreenUpdates: false) else { return nil }
        previewView.backgroundColor = .systemBackground

        // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
        let cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2
        let cellCenter = CGPoint(x: cellCenterX, y: cell.center.y)

        // Create a preview target which allows us to have a transparent background
        let previewTarget = UIPreviewTarget(container: self.view, center: cellCenter)
        let previewParameter = UIPreviewParameters()

        // Remove the background and the drop shadow from our custom preview view
        previewParameter.backgroundColor = .systemBackground
        previewParameter.shadowPath = UIBezierPath()

        return UITargetedPreview(view: previewView, parameters: previewParameter, target: previewTarget)
    }

    override func tableView(_ tableView: UITableView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        if tableView != self.tableView {
            return
        }

        isContextMenuActive = true
    }

    override func tableView(_ tableView: UITableView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        if tableView != self.tableView {
            return
        }

        animator?.addCompletion {
            self.isContextMenuActive = false

            // Wait until the context menu is completely hidden before we execute any method
            if let contextMenuActionBlock = self.contextMenuActionBlock {
                contextMenuActionBlock()
                self.contextMenuActionBlock = nil
            }

            // Apply any room list refresh that was deferred while the context menu was visible
            if self.pendingRoomListRefresh {
                self.pendingRoomListRefresh = false
                self.refreshRoomList()
            }
        }
    }

    @objc func removeRoomSelection() {
        self.selectedRoomToken = nil
    }

    @objc func highlightSelectedRoom() {
        if let selectedRoomToken {
            if let idx = rooms.firstIndex(where: { $0.token == selectedRoomToken }) {
                let indexPath = IndexPath(row: idx, section: RoomsSection.roomList.rawValue)
                self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
        } else {
            if let selectedRow = self.tableView.indexPathForSelectedRow {
                self.tableView.deselectRow(at: selectedRow, animated: true)

                // It might happen that this is called while we are switching accounts, so wait for the reload to be finished.
                // Example: Active account has 1 pending invitation, switch to an account with no pending invitation -> crash.
                DispatchQueue.main.async {
                    // Needed to make sure the highlight is really removed
                    self.tableView.reloadRows(at: [selectedRow], with: .none)
                }
            }
        }
    }
}
