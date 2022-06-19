/**
 * @copyright Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import UIKit
import Contacts
import Photos
import UserNotifications

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
    case kServerSectionWebDavRoot
    case kServerSectionUserStatusSupported
    case kServerSectionReachable
    case kServerSectionCount
}

enum TalkSections: Int {
    case kTalkSectionCapabilites = 0
    case kTalkSectionCanCreate
    case kTalkSectionCallEnabled
    case kTalkSectionAttachmentsAllowed
    case kTalkSectionCount
}

enum SignalingSections: Int {
    case kSignalingSectionApiVersion = 0
    case kSignalingSectionIsExternal
    case kSignalingSectionStunServers
    case kSignalingSectionTurnServers
    case kSignalingSectionCount
}

class DiagnosticsTableViewController: UITableViewController {
    var account: TalkAccount
    var serverCapabilities: ServerCapabilities
    var signalingConfiguration: NSDictionary?
    var externalSignalingController: NCExternalSignalingController?
    var signalingVersion: Int
    
    var serverReachable : Bool?
    var serverReachableIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))
    
    var notificationSettings : UNNotificationSettings?
    var notificationSettingsIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))
    
    let allowedString = NSLocalizedString("Allowed", comment: "TRANSLATORS '{Microphone, Camera, ...} access is allowed'")
    let deniedString = NSLocalizedString("Denied", comment: "TRANSLATORS '{Microphone, Camera, ...} access is denied'")
    let deniedFunctionalityString = NSLocalizedString("This will impact the functionality of this app. Please review your settings.", comment: "")


    init(withAccount account: TalkAccount) {
        self.account = account
        
        self.serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        self.signalingConfiguration = NCSettingsController.sharedInstance().signalingConfigutations[account.accountId] as? NSDictionary
        self.externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: account.accountId)
        self.signalingVersion = NCAPIController.sharedInstance().signalingAPIVersion(for: account)
        
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
        
        NCAPIController.sharedInstance().getServerCapabilities(for: account) { serverCapabilities, error in
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

        current.getNotificationSettings(completionHandler: { (settings) in
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
            return SignalingSections.kSignalingSectionCount.rawValue
            
        default:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case DiagnosticsSections.kDiagnosticsSectionApp.rawValue:
            return NSLocalizedString("App Diagnostics", comment: "")
            
        case DiagnosticsSections.kDiagnosticsSectionAccount.rawValue:
            return NSLocalizedString("Account Diagnostics", comment: "")
            
        case DiagnosticsSections.kDiagnosticsSectionServer.rawValue:
            return NSLocalizedString("Server Diagnostics", comment: "")
            
        case DiagnosticsSections.kDiagnosticsSectionTalk.rawValue:
            return NSLocalizedString("Talk Diagnostics", comment: "")
            
        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return NSLocalizedString("Signaling Diagnostics", comment: "")
            
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
            break;
        }
        
        return UITableViewCell()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == DiagnosticsSections.kDiagnosticsSectionApp.rawValue,
           indexPath.row == AppSections.kAppSectionOpenSettings.rawValue {
            
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
            
        } else if indexPath.section == DiagnosticsSections.kDiagnosticsSectionTalk.rawValue,
                  indexPath.row == TalkSections.kTalkSectionCapabilites.rawValue {
            
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
            return appNotificationsCell()
            
        case AppSections.kAppSectionAllowMicrophoneAccess.rawValue:
            return appAVAccessCell(for: .audio)
            
        case AppSections.kAppSectionAllowCameraAccess.rawValue:
            return appAVAccessCell(for: .video)
            
        case AppSections.kAppSectionAllowContactsAccess.rawValue:
            return appContactsAccessCell()
            
        case AppSections.kAppSectionAllowLocationAccess.rawValue:
            return appLocationAccessCell()
            
        case AppSections.kAppSectionAllowPhotoLibraryAccess.rawValue:
            return appPhotoLibraryAccessCell()
            
        case AppSections.kAppSectionOpenSettings.rawValue:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "appOpenSettingsCellIdentifier")
            cell.textLabel?.text = NSLocalizedString("Open app settings", comment: "")
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = UIColor.systemBlue
            
            return cell
            
        default:
            break
        }
        
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appCellIdentifier")
        
        switch indexPath.row {
        case AppSections.kAppSectionName.rawValue:
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)!
            cell.textLabel?.text = NSLocalizedString("Name", comment: "")
            cell.detailTextLabel?.text = appName
            
        case AppSections.kAppSectionVersion.rawValue:
            let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)!
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")
            cell.detailTextLabel?.text = appVersion
            
        default:
            break;
        }
        
        return cell
    }
    
    func appAVAccessCell(for mediaType: AVMediaType) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appAVAccessCellIdentifier")
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
            cell.detailTextLabel?.numberOfLines = 2
            
        default:
            cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
        }
        
        return cell
    }
    
    func appContactsAccessCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appContactsAccessCellIdentifier")
        cell.textLabel?.text = NSLocalizedString("Contact access", comment: "")
        cell.detailTextLabel?.numberOfLines = 1
        
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            cell.detailTextLabel?.text = allowedString
            
        case .denied:
            cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString
            cell.detailTextLabel?.numberOfLines = 2
            
        default:
            cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
        }
        
        return cell
    }
    
    func appLocationAccessCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appLocationAccessCellIdentifier")
        cell.textLabel?.text = NSLocalizedString("Location access", comment: "")
        cell.detailTextLabel?.numberOfLines = 1
        
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .authorizedAlways, .authorizedWhenInUse:
                cell.detailTextLabel?.text = allowedString
                
            case .denied:
                cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString
                cell.detailTextLabel?.numberOfLines = 2
            
            default:
                cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
                
            }
        } else {
            cell.detailTextLabel?.text = NSLocalizedString("Location service is not enabled", comment: "")
        }
        
        return cell
    }
    
    func appPhotoLibraryAccessCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appPhotoLibraryAccessCellIdentifier")
        cell.textLabel?.text = NSLocalizedString("Photo library access", comment: "")
        cell.detailTextLabel?.numberOfLines = 1
        
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            cell.detailTextLabel?.text = allowedString
            
        case .denied:
            cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString
            cell.detailTextLabel?.numberOfLines = 2
            
        default:
            cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
        }
        
        return cell
    }
    
    func appNotificationsCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "appNotificationsCellIdentifier")
        cell.textLabel?.text = NSLocalizedString("Notifications", comment: "")
        cell.detailTextLabel?.numberOfLines = 1
        cell.accessoryView = nil
        
        if notificationSettingsIndicator.isAnimating {
            cell.accessoryView = notificationSettingsIndicator
            
        } else if let settings = notificationSettings {
            switch settings.authorizationStatus {
            case .authorized:
                cell.detailTextLabel?.text = allowedString
                
            case .denied:
                cell.detailTextLabel?.text = deniedString + "\n" + deniedFunctionalityString
                cell.detailTextLabel?.numberOfLines = 2
                
            default:
                cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
            }
        }
        
        return cell
    }
    
    func accountCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "accountCellIdentifier")
        
        switch indexPath.row {
        case AccountSections.kAccountSectionServer.rawValue:
            cell.textLabel?.text = NSLocalizedString("Server", comment: "")
            cell.detailTextLabel?.text = account.server
            
        case AccountSections.kAccountSectionUser.rawValue:
            cell.textLabel?.text = NSLocalizedString("User", comment: "")
            cell.detailTextLabel?.text = account.user
            
        case AccountSections.kAccountPushSubscribed.rawValue:
            cell.textLabel?.text = NSLocalizedString("Subscribed to push server?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: account.pushNotificationSubscribed)
            
        default:
            break
        }
        
        return cell
    }
    
    func serverCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "serverCellIdentifier")
        cell.accessoryView = nil
        
        switch indexPath.row {
        case ServerSections.kServerSectionName.rawValue:
            cell.textLabel?.text = NSLocalizedString("Name", comment: "")
            cell.detailTextLabel?.text = serverCapabilities.name
            
        case ServerSections.kServerSectionVersion.rawValue:
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")
            cell.detailTextLabel?.text = serverCapabilities.version
            
        case ServerSections.kServerSectionWebDavRoot.rawValue:
            cell.textLabel?.text = NSLocalizedString("WebDAV root", comment: "")
            cell.detailTextLabel?.text = serverCapabilities.webDAVRoot
            
        case ServerSections.kServerSectionUserStatusSupported.rawValue:
            cell.textLabel?.text = NSLocalizedString("User status suppported?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.userStatus)
            
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
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "talkCellIdentifier")
        cell.accessoryType = .none
        
        switch indexPath.row {
        case TalkSections.kTalkSectionCapabilites.rawValue:
            cell.textLabel?.text = NSLocalizedString("Capabilities", comment: "")
            cell.detailTextLabel?.text = String(serverCapabilities.talkCapabilities.count)
            cell.accessoryType = .disclosureIndicator
            
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
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "signalingCellIdentifier")
        cell.accessoryType = .none
        cell.detailTextLabel?.numberOfLines = 1
        
        switch indexPath.row {
        case SignalingSections.kSignalingSectionApiVersion.rawValue:
            cell.textLabel?.text = NSLocalizedString("Version", comment: "")
            cell.detailTextLabel?.text = String(signalingVersion)
            
        case SignalingSections.kSignalingSectionIsExternal.rawValue:
            cell.textLabel?.text = NSLocalizedString("External signaling server?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: externalSignalingController?.isEnabled() ?? false)
            
        case SignalingSections.kSignalingSectionStunServers.rawValue:
            cell.textLabel?.text = NSLocalizedString("STUN servers", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Unavailable", comment: "")
            
            let stunServersConfig = signalingConfiguration?.object(forKey: "stunservers") as? [NSDictionary]
            var stunServers: [String] = []
            
            if let stunServersArray = stunServersConfig {
                for stunServerDict in stunServersArray {
                    if signalingVersion >= APIv3 {
                        stunServers += stunServerDict["urls"] as! [String]
                    } else {
                        stunServers.append(stunServerDict["url"] as! String)
                    }
                }
                
                cell.detailTextLabel?.text = stunServers.joined(separator: "\n")
                cell.detailTextLabel?.numberOfLines = stunServers.count
            }
            
        case SignalingSections.kSignalingSectionTurnServers.rawValue:
            cell.textLabel?.text = NSLocalizedString("TURN servers", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Unavailable", comment: "")
            
            let turnServersConfig = signalingConfiguration?.object(forKey: "turnservers") as? [NSDictionary]
            var turnServers: [String] = []
            
            if let turnServersArray = turnServersConfig {
                for turnServerDict in turnServersArray {
                    if signalingVersion >= APIv3 {
                        turnServers += turnServerDict["urls"] as! [String]
                    } else {
                        turnServers.append(turnServerDict["url"] as! String)
                    }
                }
                
                cell.detailTextLabel?.text = turnServers.joined(separator: "\n")
                cell.detailTextLabel?.numberOfLines = turnServers.count
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
            return;
        }
                
        let capabilitiesVC = SimpleTableViewController(withOptions: capabilities.sorted(),
                                                       withTitle: NSLocalizedString("Capabilities", comment: ""))
        
        self.navigationController?.pushViewController(capabilitiesVC, animated: true)
    }
    
    // MARK: Utils
    
    func readableBool(for value:Bool) -> String {
        if (value) {
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
