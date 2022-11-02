//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
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

import UIKit
import Contacts
import Photos
import UserNotifications

class DiagnosticsTableViewController: UITableViewController {

    enum DiagnosticsSections: Int {
        case kDiagnosticsSectionApp = 0
        case kDiagnosticsSectionAccount
        case kDiagnosticsSectionServer
        case kDiagnosticsSectionTalk
        case kDiagnosticsSectionSignaling
        case kDiagnosticsSectionCount
    }

    enum AppSections: Int {
        case kAppSectionName = 0
        case kAppSectionVersion
        case kAppSectionAllowNotifications
        case kAppSectionAllowMicrophoneAccess
        case kAppSectionAllowCameraAccess
        case kAppSectionAllowContactsAccess
        case kAppSectionAllowLocationAccess
        case kAppSectionAllowPhotoLibraryAccess
        case kAppSectionOpenSettings
        case kAppSectionCount
    }

    enum AccountSections: Int {
        case kAccountSectionServer = 0
        case kAccountSectionUser
        case kAccountPushSubscribed
        case kAccountSectionCount
    }

    enum ServerSections: Int {
        case kServerSectionName = 0
        case kServerSectionVersion
        case kServerSectionUserStatusSupported
        case kServerSectionNotificationsAppEnabled
        case kServerSectionReachable
        case kServerSectionCount
    }

    enum TalkSections: Int {
        case kTalkSectionVersion = 0
        case kTalkSectionCanCreate
        case kTalkSectionCallEnabled
        case kTalkSectionAttachmentsAllowed
        case kTalkSectionCount
    }

    enum AllSignalingSections: Int {
        case kSignalingSectionMode = 0
        case kSignalingSectionVersion
        case kSignalingSectionStunServers
        case kSignalingSectionTurnServers
        case kSignalingSectionCount
    }

    var signalingSections: [Int] = []

    var account: TalkAccount
    var serverCapabilities: ServerCapabilities
    var signalingConfiguration: NSDictionary?
    var externalSignalingController: NCExternalSignalingController?
    var signalingVersion: Int

    var serverReachable: Bool?
    var serverReachableIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))

    var notificationSettings: UNNotificationSettings?
    var notificationSettingsIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))

    let allowedString = NSLocalizedString("Allowed", comment: "'{Microphone, Camera, ...} access is allowed'")
    let deniedString = NSLocalizedString("Denied", comment: "'{Microphone, Camera, ...} access is denied'")
    let notRequestedString = NSLocalizedString("Not requested", comment: "'{Microphone, Camera, ...} access was not requested'")
    let deniedFunctionalityString = NSLocalizedString("This will impact the functionality of this app. Please review your settings.", comment: "")

    let cellIdentifierOpenAppSettings = "cellIdentifierOpenAppSettings"
    let cellIdentifierSubtitle = "cellIdentifierSubtitle"
    let cellIdentifierSubtitleAccessory = "cellIdentifierSubtitleAccessory"

    init(withAccount account: TalkAccount) {
        self.account = account

        self.serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        self.signalingConfiguration = NCSettingsController.sharedInstance().signalingConfigutations[account.accountId] as? NSDictionary
        self.externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: account.accountId)
        self.signalingVersion = NCAPIController.sharedInstance().signalingAPIVersion(for: account)

        // Build signaling sections based on external signaling server
        signalingSections.append(AllSignalingSections.kSignalingSectionMode.rawValue)

        if externalSignalingController?.isEnabled() ?? false {
            signalingSections.append(AllSignalingSections.kSignalingSectionVersion.rawValue)
        }

        signalingSections.append(AllSignalingSections.kSignalingSectionStunServers.rawValue)
        signalingSections.append(AllSignalingSections.kSignalingSectionTurnServers.rawValue)

        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Diagnostics", comment: "")
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

        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifierOpenAppSettings)
        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifierSubtitle)
        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifierSubtitleAccessory)

        runChecks()
    }

    // MARK: Async. checks

    func runChecks() {
        DispatchQueue.main.async {
            self.checkServerReachability()
            self.checkNotificationAuthorizationStatus()
        }
    }

    func checkServerReachability() {
        serverReachable = nil
        serverReachableIndicator.startAnimating()
        self.reloadRow(ServerSections.kServerSectionReachable.rawValue, in: DiagnosticsSections.kDiagnosticsSectionServer.rawValue)

        NCAPIController.sharedInstance().getServerCapabilities(for: account) { _, error in
            DispatchQueue.main.async {
                self.serverReachable = error == nil
                self.serverReachableIndicator.stopAnimating()
                self.reloadRow(ServerSections.kServerSectionReachable.rawValue, in: DiagnosticsSections.kDiagnosticsSectionServer.rawValue)
            }
        }
    }

    func checkNotificationAuthorizationStatus() {
        notificationSettings = nil
        notificationSettingsIndicator.startAnimating()
        self.reloadRow(AppSections.kAppSectionAllowNotifications.rawValue, in: DiagnosticsSections.kDiagnosticsSectionApp.rawValue)

        let current = UNUserNotificationCenter.current()

        current.getNotificationSettings(completionHandler: { settings in
            DispatchQueue.main.async {
                self.notificationSettings = settings
                self.notificationSettingsIndicator.stopAnimating()
                self.reloadRow(AppSections.kAppSectionAllowNotifications.rawValue, in: DiagnosticsSections.kDiagnosticsSectionApp.rawValue)
            }
        })
    }

    // MARK: Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return DiagnosticsSections.kDiagnosticsSectionCount.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case DiagnosticsSections.kDiagnosticsSectionApp.rawValue:
            return AppSections.kAppSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionAccount.rawValue:
            return AccountSections.kAccountSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionServer.rawValue:
            return ServerSections.kServerSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionTalk.rawValue:
            return TalkSections.kTalkSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return signalingSections.count

        default:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case DiagnosticsSections.kDiagnosticsSectionApp.rawValue:
            return NSLocalizedString("App", comment: "")

        case DiagnosticsSections.kDiagnosticsSectionAccount.rawValue:
            return NSLocalizedString("Account", comment: "")

        case DiagnosticsSections.kDiagnosticsSectionServer.rawValue:
            return NSLocalizedString("Server", comment: "")

        case DiagnosticsSections.kDiagnosticsSectionTalk.rawValue:
            return NSLocalizedString("Talk", comment: "")

        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return NSLocalizedString("Signaling", comment: "")

        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case DiagnosticsSections.kDiagnosticsSectionApp.rawValue:
            return appCell(for: indexPath)

        case DiagnosticsSections.kDiagnosticsSectionAccount.rawValue:
            return accountCell(for: indexPath)

        case DiagnosticsSections.kDiagnosticsSectionServer.rawValue:
            return serverCell(for: indexPath)

        case DiagnosticsSections.kDiagnosticsSectionTalk.rawValue:
            return talkCell(for: indexPath)

        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return signalingCell(for: indexPath)

        default:
            break
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == DiagnosticsSections.kDiagnosticsSectionApp.rawValue,
           indexPath.row == AppSections.kAppSectionOpenSettings.rawValue {

            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)

        } else if indexPath.section == DiagnosticsSections.kDiagnosticsSectionTalk.rawValue,
                  indexPath.row == TalkSections.kTalkSectionVersion.rawValue {

            presentCapabilitiesDetails()
        }

        self.tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return (tableView.cellForRow(at: indexPath)?.detailTextLabel?.text) != nil
    }

    override func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return action == #selector(copy(_:))
    }

    override func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(copy(_:)) {
            let cell = tableView.cellForRow(at: indexPath)
            let pasteboard = UIPasteboard.general
            pasteboard.string = cell?.detailTextLabel?.text
        }
    }

    // MARK: Table view cells

    func appCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case AppSections.kAppSectionAllowNotifications.rawValue:
            return appNotificationsCell(for: indexPath)

        case AppSections.kAppSectionAllowMicrophoneAccess.rawValue:
            return appAVAccessCell(for: .audio, for: indexPath)

        case AppSections.kAppSectionAllowCameraAccess.rawValue:
            return appAVAccessCell(for: .video, for: indexPath)

        case AppSections.kAppSectionAllowContactsAccess.rawValue:
            return appContactsAccessCell(for: indexPath)

        case AppSections.kAppSectionAllowLocationAccess.rawValue:
            return appLocationAccessCell(for: indexPath)

        case AppSections.kAppSectionAllowPhotoLibraryAccess.rawValue:
            return appPhotoLibraryAccessCell(for: indexPath)

        case AppSections.kAppSectionOpenSettings.rawValue:
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierOpenAppSettings, for: indexPath)

            cell.textLabel?.text = NSLocalizedString("Open app settings", comment: "")
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = UIColor.systemBlue

            return cell

        default:
            break
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)

        switch indexPath.row {
        case AppSections.kAppSectionName.rawValue:
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)!
            cell.textLabel?.text = NSLocalizedString("Name", comment: "")
            cell.detailTextLabel?.text = appName

        case AppSections.kAppSectionVersion.rawValue:
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")
            cell.detailTextLabel?.text = NCAppBranding.getAppVersionString()

        default:
            break
        }

        return cell
    }

    func appAVAccessCell(for mediaType: AVMediaType, for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)
        let authStatusAV = AVCaptureDevice.authorizationStatus(for: mediaType)

        if mediaType == .audio {
            cell.textLabel?.text = NSLocalizedString("Microphone access", comment: "")
        } else {
            cell.textLabel?.text = NSLocalizedString("Camera access", comment: "")
        }

        switch authStatusAV {
        case .authorized:
            cell.detailTextLabel?.text = allowedString

        case .denied:
            cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString

        default:
            cell.detailTextLabel?.text = notRequestedString
        }

        return cell
    }

    func appContactsAccessCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)
        cell.textLabel?.text = NSLocalizedString("Contact access", comment: "")

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            cell.detailTextLabel?.text = allowedString

        case .denied:
            cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString

        default:
            cell.detailTextLabel?.text = notRequestedString
        }

        return cell
    }

    func appLocationAccessCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)
        cell.textLabel?.text = NSLocalizedString("Location access", comment: "")

        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                cell.detailTextLabel?.text = allowedString

            case .denied:
                cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString

            default:
                cell.detailTextLabel?.text = notRequestedString

            }
        } else {
            cell.detailTextLabel?.text = NSLocalizedString("Location service is not enabled", comment: "")
        }

        return cell
    }

    func appPhotoLibraryAccessCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)
        cell.textLabel?.text = NSLocalizedString("Photo library access", comment: "")

        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            cell.detailTextLabel?.text = allowedString

        case .denied:
            cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString

        default:
            cell.detailTextLabel?.text = notRequestedString
        }

        return cell
    }

    func appNotificationsCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitleAccessory, for: indexPath)
        cell.textLabel?.text = NSLocalizedString("Notifications", comment: "")
        cell.accessoryType = .none
        cell.accessoryView = nil

        if notificationSettingsIndicator.isAnimating {
            cell.accessoryView = notificationSettingsIndicator

        } else if let settings = notificationSettings {
            switch settings.authorizationStatus {
            case .authorized:
                cell.detailTextLabel?.text = allowedString

            case .denied:
                cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString

            default:
                cell.detailTextLabel?.text = notRequestedString
            }
        }

        return cell
    }

    func accountCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)

        switch indexPath.row {
        case AccountSections.kAccountSectionServer.rawValue:
            cell.textLabel?.text = NSLocalizedString("Server", comment: "")
            cell.detailTextLabel?.text = account.server

        case AccountSections.kAccountSectionUser.rawValue:
            cell.textLabel?.text = NSLocalizedString("User", comment: "")
            cell.detailTextLabel?.text = account.user

        case AccountSections.kAccountPushSubscribed.rawValue:
            cell.textLabel?.text = NSLocalizedString("Push notifications", comment: "")
            if account.lastPushSubscription > 0 {
                let lastSubsctiptionString = NSLocalizedString("Last subscription", comment: "Last subscription to the push notification server")
                let lastTime = NSDate(timeIntervalSince1970: TimeInterval(account.lastPushSubscription))
                cell.detailTextLabel?.text = lastSubsctiptionString + ": " + NCUtils.readableDateTime(from: lastTime as Date)
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("Never subscribed", comment: "Never subscribed to the push notification server")
            }

        default:
            break
        }

        return cell
    }

    func serverCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitleAccessory, for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil

        switch indexPath.row {
        case ServerSections.kServerSectionName.rawValue:
            cell.textLabel?.text = NSLocalizedString("Name", comment: "")
            cell.detailTextLabel?.text = serverCapabilities.name

        case ServerSections.kServerSectionVersion.rawValue:
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")
            cell.detailTextLabel?.text = serverCapabilities.version

        case ServerSections.kServerSectionUserStatusSupported.rawValue:
            cell.textLabel?.text = NSLocalizedString("User status supported?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.userStatus)

        case ServerSections.kServerSectionNotificationsAppEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("Notifications app enabled?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.notificationsAppEnabled)

        case ServerSections.kServerSectionReachable.rawValue:
            cell.textLabel?.text = NSLocalizedString("Reachable?", comment: "")
            cell.detailTextLabel?.text = "-"

            if serverReachableIndicator.isAnimating {
                cell.accessoryView = serverReachableIndicator
            } else if let reachable = serverReachable {
                cell.detailTextLabel?.text = readableBool(for: reachable)
            }

        default:
            break
        }

        return cell
    }

    func talkCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitleAccessory, for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil

        switch indexPath.row {
        case TalkSections.kTalkSectionVersion.rawValue:
            cell.accessoryType = .disclosureIndicator

            if serverCapabilities.talkVersion.isEmpty {
                cell.textLabel?.text = NSLocalizedString("Capabilities", comment: "")
                cell.detailTextLabel?.text = String(serverCapabilities.talkCapabilities.count)
            } else {
                cell.textLabel?.text = NSLocalizedString("Version", comment: "")
                cell.detailTextLabel?.text = serverCapabilities.talkVersion
            }

        case TalkSections.kTalkSectionCanCreate.rawValue:
            cell.textLabel?.text = NSLocalizedString("Can create conversations?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.canCreate)

        case TalkSections.kTalkSectionCallEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("Calls enabled?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.callEnabled)

        case TalkSections.kTalkSectionAttachmentsAllowed.rawValue:
            cell.textLabel?.text = NSLocalizedString("Attachments allowed?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.attachmentsAllowed)

        default:
            break
        }

        return cell
    }

    func signalingCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierSubtitle, for: indexPath)

        let allSectionsIndex = signalingSections[indexPath.row]

        switch allSectionsIndex {
        case AllSignalingSections.kSignalingSectionMode.rawValue:
            let externalSignalingServerUsed = externalSignalingController?.isEnabled() ?? false

            cell.textLabel?.text = NSLocalizedString("Mode", comment: "The signaling mode used")

            if externalSignalingServerUsed {
                cell.detailTextLabel?.text = NSLocalizedString("External", comment: "External signaling used")
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("Internal", comment: "Internal signaling used")
            }

        case AllSignalingSections.kSignalingSectionVersion.rawValue:
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")

            if serverCapabilities.externalSignalingServerVersion.isEmpty {
                cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
            } else {
                cell.detailTextLabel?.text = serverCapabilities.externalSignalingServerVersion
            }

        case AllSignalingSections.kSignalingSectionStunServers.rawValue:
            cell.textLabel?.text = NSLocalizedString("STUN servers", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Unavailable", comment: "")

            let stunServersConfig = signalingConfiguration?.object(forKey: "stunservers") as? [NSDictionary]
            var stunServers: [String] = []

            if let stunServersArray = stunServersConfig {
                for stunServerDict in stunServersArray {
                    if signalingVersion >= APIv3 {
                        guard let stunServerStringDict = stunServerDict["urls"] as? [String] else {
                            continue
                        }

                        stunServers += stunServerStringDict
                    } else {
                        guard let stunServerString = stunServerDict["url"] as? String else {
                            continue
                        }

                        stunServers.append(stunServerString)
                    }
                }

                if !stunServers.isEmpty {
                    cell.detailTextLabel?.text = stunServers.joined(separator: "\n")
                }
            }

        case AllSignalingSections.kSignalingSectionTurnServers.rawValue:
            cell.textLabel?.text = NSLocalizedString("TURN servers", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Unavailable", comment: "")

            let turnServersConfig = signalingConfiguration?.object(forKey: "turnservers") as? [NSDictionary]
            var turnServers: [String] = []

            if let turnServersArray = turnServersConfig {
                for turnServerDict in turnServersArray {
                    if signalingVersion >= APIv3 {
                        guard let turnServerStringDict = turnServerDict["urls"] as? [String] else {
                            continue
                        }

                        turnServers += turnServerStringDict
                    } else {
                        guard let turnServerString = turnServerDict["url"] as? String else {
                            continue
                        }

                        turnServers.append(turnServerString)
                    }
                }

                if !turnServers.isEmpty {
                    cell.detailTextLabel?.text = turnServers.joined(separator: "\n")
                }
            }

        default:
            break
        }

        return cell
    }

    // MARK: Capabilities details

    func presentCapabilitiesDetails() {
        let talkFeatures = serverCapabilities.talkCapabilities.value(forKey: "self") as? [String]

        guard let capabilities = talkFeatures else {
            return
        }

        let capabilitiesVC = SimpleTableViewController(withOptions: capabilities.sorted(),
                                                       withTitle: NSLocalizedString("Capabilities", comment: ""))

        self.navigationController?.pushViewController(capabilitiesVC, animated: true)
    }

    // MARK: Utils

    func readableBool(for value: Bool) -> String {
        if value {
            return NSLocalizedString("Yes", comment: "")
        } else {
            return NSLocalizedString("No", comment: "")
        }
    }

    func reloadRow(_ row: Int, in section: Int) {
        DispatchQueue.main.async {
            self.tableView.reloadRows(at: [IndexPath(row: row, section: section)], with: .none)
        }
    }
}
