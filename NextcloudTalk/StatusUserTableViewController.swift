//
//  StatusUserTableViewController.swift
//  NextcloudTalk
//
//  Created by Aleksandra Lazarevic on 21.1.22..
//

import UIKit

enum UserStatusSection: Int {
    case kUserStatusSectionOnlineStatus = 0
    case kUserStatusSectionStatusMessage
    case kUserStatusSectionCount
}

class StatusUserTableViewController: UITableViewController, DetailedOptionsSelectorTableViewControllerDelegate, UserStatusMessageViewControllerDelegate {
    var userStatus: NCUserStatus?
    init(userStatus: NCUserStatus?) {
        super.init(style: .grouped)
        self.userStatus = userStatus
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Status", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        if #available(iOS 13.0, *) {
            let themeColor: UIColor = NCAppBranding.themeColor()
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = themeColor
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }
    }
    // MARK: User Status
    func presentUserStatusOptions() {
        var options = [DetailedOption]()
        let onlineOption = DetailedOption()
        onlineOption.identifier = kUserStatusOnline
        onlineOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusOnline, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        onlineOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusOnline)
        if let userStatus = userStatus {
            onlineOption.selected = userStatus.status == kUserStatusOnline
        }
        let awayOption = DetailedOption()
        awayOption.identifier = kUserStatusAway
        awayOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusAway, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        awayOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusAway)
        if let userStatus = userStatus {
            awayOption.selected = userStatus.status == kUserStatusAway
        }
        let dndOption = DetailedOption()
        dndOption.identifier = kUserStatusAway
        dndOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusDND, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        dndOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusDND)
        if let userStatus = userStatus {
            dndOption.selected = userStatus.status == kUserStatusDND
        }
        let invisibleOption = DetailedOption()
        invisibleOption.identifier = kUserStatusInvisible
        invisibleOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusInvisible, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        invisibleOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusInvisible)
        invisibleOption.subtitle = NSLocalizedString("Appear offline", comment: "")
        if let userStatus = userStatus {
            invisibleOption.selected = userStatus.status == kUserStatusInvisible
        }
        options.append(onlineOption)
        options.append(awayOption)
        options.append(dndOption)
        options.append(invisibleOption)
        let optionSelectorVC = DetailedOptionsSelectorTableViewController(options: options, forSenderIdentifier: nil, andTitle: NSLocalizedString(("Online status"), comment: ""))
        if let optionSelectorVC = optionSelectorVC {
            optionSelectorVC.delegate = self
            let optionSelectorNC = NCNavigationController(rootViewController: optionSelectorVC)
            self.present(optionSelectorNC, animated: true, completion: nil)
        }
    }
    func presentUserStatusMessageOptions() {
        if let userStatus = userStatus {
            let userStatusMessageVC = UserStatusMessageViewController(userStatus: userStatus)
            userStatusMessageVC.delegate = self
            let userStatusMessageNC = NCNavigationController(rootViewController: userStatusMessageVC)
            self.present(userStatusMessageNC, animated: true, completion: nil)
        }
    }
    func setActiveUserStatus(userStatus: String) {
        let activeAcoount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setUserStatus(userStatus, for: activeAcoount) { _ in
            self.getActiveUserStatus()
        }
    }
    func getActiveUserStatus() {
        let activeAccount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getUserStatus(for: activeAccount) { [self] userStatusDict, error in
            if error == nil && userStatusDict != nil {
                userStatus = NCUserStatus(dictionary: userStatusDict!)
                self.tableView.reloadData()
            }
        }
    }
    // MARK: DetailedOptionSelector Delegate
    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController!, didSelectOptionWithIdentifier option: DetailedOption!) {
        self.dismiss(animated: true) {
            if !option.selected {
                self.setActiveUserStatus(userStatus: option.identifier)
            }
        }
    }
    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController!) {
        //
    }
    func didClearStatusMessage() {
        //
    }
    func didSetStatusMessage(icon: String?, message: String?, clearAt: NSDate?) {
        //
    }
}
