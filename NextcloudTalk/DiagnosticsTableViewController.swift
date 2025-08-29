//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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
        case kDiagnosticsSectionReset
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
        case kAppSectionCallKitEnabled
        case kAppSectionOpenSettings
        case kAppSectionCount
    }

    enum AccountSections: Int {
        case server = 0
        case user
        case pushSubscribed
        case testPushNotifications
    }

    enum ServerSections: Int {
        case kServerSectionName = 0
        case kServerSectionVersion
        case kServerSectionUserStatusSupported
        case kServerSectionReferenceApiSupported
        case kServerSectionNotificationsAppEnabled
        case kServerSectionGuestsAppEnabled
        case kServerSectionReachable
        case kServerSectionCount
    }

    enum TalkSections: Int {
        case kTalkSectionVersion = 0
        case kTalkSectionCanCreate
        case kTalkSectionCallEnabled
        case kTalkSectionRecordingEnabled
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

    enum ResetSections: Int {
        case kResetSectionStoredMessages = 0
        case kResetSectionCount
    }

    var signalingSections: [Int] = []

    var account: TalkAccount
    var serverCapabilities: ServerCapabilities
    var signalingConfiguration: SignalingSettings?
    var externalSignalingController: NCExternalSignalingController?
    var signalingVersion: Int

    var serverReachable: Bool?
    var serverReachableIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))

    var testingPushNotificationsIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))

    var notificationSettings: UNNotificationSettings?
    var notificationSettingsIndicator = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 24, height: 24))

    let allowedString = NSLocalizedString("Allowed", comment: "'{Microphone, Camera, ...} access is allowed'")
    let deniedString = NSLocalizedString("Denied", comment: "'{Microphone, Camera, ...} access is denied'")
    let notRequestedString = NSLocalizedString("Not requested", comment: "'{Microphone, Camera, ...} access was not requested'")
    let deniedFunctionalityString = NSLocalizedString("This will impact the functionality of this app. Please review your settings.", comment: "")

    let cellIdentifierAction = "cellIdentifierAction"
    let cellIdentifierSubtitle = "cellIdentifierSubtitle"
    let cellIdentifierSubtitleAccessory = "cellIdentifierSubtitleAccessory"

    init(withAccount account: TalkAccount) {
        self.account = account

        self.serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)!
        self.signalingConfiguration = NCSettingsController.sharedInstance().signalingConfigurations[account.accountId] as? SignalingSettings
        self.externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: account.accountId)
        self.signalingVersion = NCAPIController.sharedInstance().signalingAPIVersion(for: account)

        // Build signaling sections based on external signaling server
        signalingSections.append(AllSignalingSections.kSignalingSectionMode.rawValue)

        if externalSignalingController != nil {
            signalingSections.append(AllSignalingSections.kSignalingSectionVersion.rawValue)
        }

        signalingSections.append(AllSignalingSections.kSignalingSectionStunServers.rawValue)
        signalingSections.append(AllSignalingSections.kSignalingSectionTurnServers.rawValue)

        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Diagnostics", comment: "")

        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifierAction)
        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifierSubtitle)
        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifierSubtitleAccessory)

        runChecks()
    }

    // MARK: - Account section options

    func accountSections() -> [AccountSections] {
        var sections: [AccountSections] = [.server, .user, .pushSubscribed]
        if NCDatabaseManager.sharedInstance().serverHasNotificationsCapability(kNotificationsCapabilityTestPush, forAccountId: account.accountId) {
            sections.append(.testPushNotifications)
        }

        return sections
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
            return accountSections().count

        case DiagnosticsSections.kDiagnosticsSectionServer.rawValue:
            return ServerSections.kServerSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionTalk.rawValue:
            return TalkSections.kTalkSectionCount.rawValue

        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return signalingSections.count

        case DiagnosticsSections.kDiagnosticsSectionReset.rawValue:
            return ResetSections.kResetSectionCount.rawValue

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
            return "Talk"

        case DiagnosticsSections.kDiagnosticsSectionSignaling.rawValue:
            return NSLocalizedString("Signaling", comment: "")

        case DiagnosticsSections.kDiagnosticsSectionReset.rawValue:
            return NSLocalizedString("Reset", comment: "Title for a section where different reset options are shown")

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

        case DiagnosticsSections.kDiagnosticsSectionReset.rawValue:
            return resetCell(for: indexPath)

        default:
            break
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == DiagnosticsSections.kDiagnosticsSectionApp.rawValue,
           indexPath.row == AppSections.kAppSectionOpenSettings.rawValue {

            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)

        } else if indexPath.section == DiagnosticsSections.kDiagnosticsSectionAccount.rawValue,
                  accountSections()[indexPath.row] == .testPushNotifications {

            testPushNotifications()

        } else if indexPath.section == DiagnosticsSections.kDiagnosticsSectionTalk.rawValue,
                  indexPath.row == TalkSections.kTalkSectionVersion.rawValue {

            presentCapabilitiesDetails()

        } else if indexPath.section == DiagnosticsSections.kDiagnosticsSectionReset.rawValue,
                  indexPath.row == ResetSections.kResetSectionStoredMessages.rawValue {

            resetStoredMessages()
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
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierAction, for: indexPath)

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

        case AppSections.kAppSectionCallKitEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("CallKit supported?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: CallKitManager.isCallKitAvailable())

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
        let row: AccountSections = accountSections()[indexPath.row]

        switch row {
        case .server:
            cell.textLabel?.text = NSLocalizedString("Server", comment: "")
            cell.detailTextLabel?.text = account.server

        case .user:
            cell.textLabel?.text = NSLocalizedString("User", comment: "")
            cell.detailTextLabel?.text = account.user

        case .pushSubscribed:
            cell.textLabel?.text = NSLocalizedString("Push notifications", comment: "")
            if account.lastPushSubscription > 0 {
                let lastSubsctiptionString = NSLocalizedString("Last subscription", comment: "Last subscription to the push notification server")
                let lastTime = NSDate(timeIntervalSince1970: TimeInterval(account.lastPushSubscription))
                cell.detailTextLabel?.text = lastSubsctiptionString + ": " + NCUtils.readableDateTime(fromDate: lastTime as Date)
            } else {
                cell.detailTextLabel?.text = NSLocalizedString("Never subscribed", comment: "Never subscribed to the push notification server")
            }

        case .testPushNotifications:
            let actionCell = self.tableView.dequeueReusableCell(withIdentifier: self.cellIdentifierAction, for: indexPath)
            actionCell.textLabel?.text = NSLocalizedString("Test push notifications", comment: "")
            actionCell.textLabel?.textAlignment = .center
            actionCell.textLabel?.textColor = UIColor.systemBlue
            return actionCell
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

        case ServerSections.kServerSectionReferenceApiSupported.rawValue:
            cell.textLabel?.text = NSLocalizedString("Reference API supported?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.referenceApiSupported)

        case ServerSections.kServerSectionNotificationsAppEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("Notifications app enabled?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.notificationsCapabilities.count > 0)

        case ServerSections.kServerSectionGuestsAppEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("Guests app enabled?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.guestsAppEnabled)

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

        case TalkSections.kTalkSectionRecordingEnabled.rawValue:
            cell.textLabel?.text = NSLocalizedString("Call recording enabled?", comment: "")
            cell.detailTextLabel?.text = readableBool(for: serverCapabilities.recordingEnabled)

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
            let externalSignalingServerUsed = externalSignalingController != nil

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

            var stunServers: [String] = []

            signalingConfiguration?.stunServers.forEach { stunServers += $0.urls ?? [] }

            if !stunServers.isEmpty {
                cell.detailTextLabel?.text = stunServers.joined(separator: "\n")
            }

        case AllSignalingSections.kSignalingSectionTurnServers.rawValue:
            cell.textLabel?.text = NSLocalizedString("TURN servers", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Unavailable", comment: "")

            var turnServers: [String] = []

            signalingConfiguration?.turnServers.forEach { turnServers += $0.urls ?? [] }

            if !turnServers.isEmpty {
                cell.detailTextLabel?.text = turnServers.joined(separator: "\n")
            }

        default:
            break
        }

        return cell
    }

    func resetCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == ResetSections.kResetSectionStoredMessages.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierAction, for: indexPath)

            cell.textLabel?.text = NSLocalizedString("Clear cached chat messages", comment: "")
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = UIColor.systemRed

            return cell
        }

        return UITableViewCell()
    }

    // MARK: Test push notifications

    func testPushNotifications() {
        self.showPushNotificationTestRunningIndicator()
        NCAPIController.sharedInstance().testPushnotifications(forAccount: account) { result in
            let isEmptyResult = result?.isEmpty ?? true
            let title = isEmptyResult ? NSLocalizedString("Test failed", comment: "") : NSLocalizedString("Test results", comment: "")
            let message = isEmptyResult ? NSLocalizedString("An error occurred while testing push notifications", comment: "") : result
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            if !isEmptyResult {
                alert.addAction(UIAlertAction(title: NSLocalizedString("Copy", comment: ""), style: .default) { _ in
                    UIPasteboard.general.string = result
                    NotificationPresenter.shared().present(text: NSLocalizedString("Test results copied", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
                })
            }
            NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            self.hidePushNotificationTestRunningIndicator()
        }
    }

    func testPushNotificationsCell() -> UITableViewCell? {
        if let index = accountSections().firstIndex(of: AccountSections.testPushNotifications),
           let testPushCell = tableView.cellForRow(at: IndexPath(row: index, section: DiagnosticsSections.kDiagnosticsSectionAccount.rawValue)) {
            return testPushCell
        }

        return nil
    }

    func showPushNotificationTestRunningIndicator() {
        if let testPushNotificationsCell = testPushNotificationsCell() {
            testPushNotificationsCell.isUserInteractionEnabled = false
            testPushNotificationsCell.textLabel?.textColor = UIColor.systemBlue.withAlphaComponent(0.5)
            testingPushNotificationsIndicator.startAnimating()
            testPushNotificationsCell.accessoryView = testingPushNotificationsIndicator
        }
    }

    func hidePushNotificationTestRunningIndicator() {
        if let testPushNotificationsCell = testPushNotificationsCell() {
            testPushNotificationsCell.isUserInteractionEnabled = true
            testPushNotificationsCell.textLabel?.textColor = UIColor.systemBlue
            testingPushNotificationsIndicator.stopAnimating()
            testPushNotificationsCell.accessoryView = nil
        }
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

    // MARK: Reset actions

    func resetStoredMessages() {
        NCDatabaseManager.sharedInstance().removeStoredMessages(forAccountId: account.accountId)
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
