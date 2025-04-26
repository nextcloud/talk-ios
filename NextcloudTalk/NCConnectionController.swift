//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension Notification.Name {
    static let NCAppStateHasChangedNotification = Notification.Name(rawValue: "NCAppStateHasChangedNotification")
    static let NCConnectionStateHasChangedNotification = Notification.Name(rawValue: "NCConnectionStateHasChangedNotification")
}

@objc extension NSNotification {
    public static let NCAppStateHasChangedNotification = Notification.Name.NCAppStateHasChangedNotification
    public static let NCConnectionStateHasChangedNotification = Notification.Name.NCConnectionStateHasChangedNotification
}

@objc enum AppState: Int {
    case unknown = 0
    case noServerProvided
    case missingUserProfile
    case missingServerCapabilities
    case missingSignalingConfiguration
    case ready
}

@objc public enum ConnectionState: Int {
    case unknown = 0
    case disconnected
    case connected
}

@objcMembers
class NCConnectionController: NSObject {

    static let shared = NCConnectionController()

    public var appState: AppState = .unknown
    public var connectionState: ConnectionState = .unknown

    override init() {
        super.init()

        self.checkAppState()

        AFNetworkReachabilityManager.shared().setReachabilityStatusChange { status in
            print("Reachability: \(AFStringFromNetworkReachabilityStatus(status))")
            self.checkConnectionState()
        }
    }

    internal func notifyAppState() {
        // Use NSNumber for objc compatibility
        let dict = ["appState": NSNumber(value: self.appState.rawValue)]
        NotificationCenter.default.post(name: .NCAppStateHasChangedNotification, object: self, userInfo: dict)
    }

    internal func notifyConnectionState() {
        // Use NSNumber for objc compatibility
        let dict = ["connectionState": NSNumber(value: self.connectionState.rawValue)]
        NotificationCenter.default.post(name: .NCConnectionStateHasChangedNotification, object: self, userInfo: dict)
    }

    public func checkConnectionState() {
        if !AFNetworkReachabilityManager.shared().isReachable {
            self.connectionState = .disconnected
            self.notifyConnectionState()
        } else {
            let previousState = self.connectionState
            self.connectionState = .connected
            self.checkAppState()

            if previousState == .disconnected {
                self.notifyConnectionState()
            }
        }
    }

    public func checkAppState() {
        if NCDatabaseManager.sharedInstance().numberOfAccounts() == 0 {
            self.appState = .noServerProvided
            NCUserInterfaceController.sharedInstance().presentLoginViewController()
            self.notifyAppState()

            return
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let signalingConfig = NCSettingsController.sharedInstance().signalingConfigurations.object(forKey: activeAccount.accountId)

        if activeAccount.user.isEmpty || activeAccount.userDisplayName.isEmpty {
            self.appState = .missingUserProfile

            NCSettingsController.sharedInstance().getUserProfile(forAccountId: activeAccount.accountId) { error in
                if error != nil {
                    self.notifyAppState()
                } else {
                    self.checkAppState()
                }
            }
        } else if signalingConfig == nil {
            self.appState = .missingServerCapabilities

            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId) { error in
                if error != nil {
                    self.notifyAppState()
                    return
                }

                self.appState = .missingSignalingConfiguration

                NCSettingsController.sharedInstance().updateSignalingConfiguration(forAccountId: activeAccount.accountId) { _, error in
                    if error != nil {
                        self.notifyAppState()
                        return
                    }

                    self.checkAppState()
                }
            }
        } else {
            // Fetch additional data asynchronously.
            // We set the app as ready, so we don’t need to wait for this to complete.
            NCSettingsController.sharedInstance().getUserGroupsAndTeams(forAccountId: activeAccount.accountId)
            self.appState = .ready
        }

        self.notifyAppState()
    }

}
