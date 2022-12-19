//
// Copyright (c) 2022 Aleksandra Lazarevic <aleksandra@nextcloud.com>
//
// Author Aleksandra Lazarevic <aleksandra@nextcloud.com>
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

import UIKit

enum UserStatusSection: Int {
    case kUserStatusSectionOnlineStatus = 0
    case kUserStatusSectionStatusMessage
    case kUserStatusSectionCount
}

class UserStatusTableViewController: UITableViewController, DetailedOptionsSelectorTableViewControllerDelegate, UserStatusMessageViewControllerDelegate {

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
        dndOption.identifier = kUserStatusDND
        dndOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusDND, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        dndOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusDND)
        dndOption.subtitle = NSLocalizedString("Mute all notifications", comment: "")
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

        let optionSelectorVC = DetailedOptionsSelectorTableViewController(options: options, forSenderIdentifier: nil)
        if let optionSelectorVC = optionSelectorVC {
            optionSelectorVC.title = NSLocalizedString("Online status", comment: "")
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

    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController?, didSelectOptionWithIdentifier option: DetailedOption?) {
        self.dismiss(animated: true) {
            if let option = option {
                if !option.selected {
                    self.setActiveUserStatus(userStatus: option.identifier)
                }
            }
        }
    }

    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController?) {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: UserStatusMessageViewController Delegate

    func didClearStatusMessage() {
        if let userStatus = userStatus {
            userStatus.icon = ""
            userStatus.message = ""
            userStatus.clearAt = 0
            self.tableView.reloadData()
        }
    }
    func didSetStatusMessage(icon: String?, message: String?, clearAt: NSDate?) {
        if let userStatus = userStatus {
            if let icon = icon {
                userStatus.icon = icon
            }
            if let message = message {
                userStatus.message = message
            }
            if let clearAt = clearAt {
                userStatus.clearAt = Int(clearAt.timeIntervalSince1970)
            }
            self.tableView.reloadData()
        }
    }

    // MARK: Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return UserStatusSection.kUserStatusSectionCount.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case UserStatusSection.kUserStatusSectionOnlineStatus.rawValue:
            return NSLocalizedString("Online status", comment: "")
        case UserStatusSection.kUserStatusSectionStatusMessage.rawValue:
            return NSLocalizedString("Status message", comment: "")
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = UITableViewCell()
        let kOnlineStatusCellIdentifier = "OnlineStatusCellIdentifier"
        let kStatusMessageCellIdentifier = "StatusMessageCellIdentifier"
        switch indexPath.section {
        case UserStatusSection.kUserStatusSectionOnlineStatus.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: kOnlineStatusCellIdentifier)
            if let userStatus = userStatus {
                cell.textLabel?.text = userStatus.readableUserStatus()
                let statusImage = userStatus.userStatusImageName(ofSize: 24)
                if !statusImage.isEmpty {
                    cell.imageView?.image = UIImage(named: statusImage)
                } else {
                    cell.imageView?.image = nil
                }
            } else {
                cell.textLabel?.text = NSLocalizedString("Fetching status …", comment: "")
            }
        case UserStatusSection.kUserStatusSectionStatusMessage.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: kStatusMessageCellIdentifier)
            if let userStatus = userStatus {
                let statusMessage = userStatus.readableUserStatusMessage()
                if !statusMessage.isEmpty {
                    cell.textLabel?.text = statusMessage
                } else {
                    cell.textLabel?.text = NSLocalizedString("What is your status?", comment: "")
                }
            }
        default:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case UserStatusSection.kUserStatusSectionOnlineStatus.rawValue:
            self.presentUserStatusOptions()
        case UserStatusSection.kUserStatusSectionStatusMessage.rawValue:
            self.presentUserStatusMessageOptions()
        default:
            break
        }
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
}
