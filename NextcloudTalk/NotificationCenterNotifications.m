/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NotificationCenterNotifications.h"

NSString * const NCTalkNotInstalledNotification = @"NCTalkNotInstalledNotification";
NSString * const NCOutdatedTalkVersionNotification = @"NCOutdatedTalkVersionNotification";
NSString * const NCServerCapabilitiesUpdatedNotification = @"NCServerCapabilitiesUpdatedNotification";
NSString * const NCUserProfileImageUpdatedNotification = @"NCUserProfileImageUpdatedNotification";
NSString * const NCTokenRevokedResponseReceivedNotification = @"NCTokenRevokedResponseReceivedNotification";
NSString * const NCUpgradeRequiredResponseReceivedNotification = @"NCUpgradeRequiredResponseReceivedNotification";
NSString * const NCURLWantsToOpenConversationNotification = @"NCURLWantsToOpenConversationNotification";
NSString * const NCServerMaintenanceModeNotification = @"NCServerMaintenanceModeNotification";
NSString * const NCTalkConfigurationHashChangedNotification = @"NCTalkConfigurationHashChangedNotification";
NSString * const NCPresentChatHighlightingMessageNotification = @"NCPresentChatHighlightingMessageNotification";
NSString * const NCRoomCreatedNotification  = @"NCRoomCreatedNotification";
NSString * const NCSelectedUserForChatNotification = @"NCSelectedUserForChatNotification";
NSString * const NCUserThreadsUpdatedNotification = @"NCUserThreadsUpdatedNotification";
NSString * const NCUserHasThreadsFlagUpdatedNotification = @"NCUserHasThreadsFlagUpdatedNotification";

NSString * const AudioSessionDidChangeRouteNotification = @"AudioSessionDidChangeRouteNotification";
NSString * const AudioSessionWasActivatedByProviderNotification = @"AudioSessionWasActivatedByProviderNotification";
NSString * const AudioSessionDidChangeRoutingInformationNotification = @"AudioSessionDidChangeRoutingInformationNotification";

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidUpdateRoomsNotification           = @"NCRoomsManagerDidUpdateRoomsNotification";
NSString * const NCRoomsManagerDidUpdateRoomNotification            = @"NCRoomsManagerDidUpdateRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";
