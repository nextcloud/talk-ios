//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public extension Notification.Name {
    static let NCTalkNotInstalled = Notification.Name(rawValue: "NCTalkNotInstalledNotification")
    static let NCOutdatedTalkVersion = Notification.Name(rawValue: "NCOutdatedTalkVersionNotification")
    static let NCServerCapabilitiesUpdated = Notification.Name(rawValue: "NCServerCapabilitiesUpdatedNotification")
    static let NCUserProfileImageUpdated = Notification.Name(rawValue: "NCUserProfileImageUpdatedNotification")
    static let NCTokenRevokedResponseReceived = Notification.Name(rawValue: "NCTokenRevokedResponseReceivedNotification")
    static let NCUpgradeRequiredResponseReceived = Notification.Name(rawValue: "NCUpgradeRequiredResponseReceivedNotification")
    static let NCURLWantsToOpenConversation = Notification.Name(rawValue: "NCURLWantsToOpenConversationNotification")
    static let NCServerMaintenanceMode = Notification.Name(rawValue: "NCServerMaintenanceModeNotification")
    static let NCTalkConfigurationHashChanged = Notification.Name(rawValue: "NCTalkConfigurationHashChangedNotification")
    static let NCPresentChatHighlightingMessage = Notification.Name(rawValue: "NCPresentChatHighlightingMessageNotification")
    static let NCRoomCreated = Notification.Name(rawValue: "NCRoomCreatedNotification")
    static let NCSelectedUserForChat = Notification.Name(rawValue: "NCSelectedUserForChatNotification")
    static let NCUserThreadsUpdated = Notification.Name(rawValue: "NCUserThreadsUpdatedNotification")
    static let NCUserHasThreadsFlagUpdated = Notification.Name(rawValue: "NCUserHasThreadsFlagUpdatedNotification")
    static let NCConversationTagsUpdated = Notification.Name(rawValue: "NCConversationTagsUpdatedNotification")
    static let AudioSessionDidChangeRoute = Notification.Name(rawValue: "AudioSessionDidChangeRouteNotification")
    static let AudioSessionWasActivatedByProvider = Notification.Name(rawValue: "AudioSessionWasActivatedByProviderNotification")
    static let AudioSessionDidChangeRoutingInformation = Notification.Name(rawValue: "AudioSessionDidChangeRoutingInformationNotification")
    static let NCRoomsManagerDidJoinRoom = Notification.Name(rawValue: "NCRoomsManagerDidJoinRoomNotification")
    static let NCRoomsManagerDidLeaveRoom = Notification.Name(rawValue: "NCRoomsManagerDidLeaveRoomNotification")
    static let NCRoomsManagerDidUpdateRooms = Notification.Name(rawValue: "NCRoomsManagerDidUpdateRoomsNotification")
    static let NCRoomsManagerDidUpdateRoom = Notification.Name(rawValue: "NCRoomsManagerDidUpdateRoomNotification")
    static let NCRoomsManagerDidStartCall = Notification.Name(rawValue: "NCRoomsManagerDidStartCallNotification")
}
