//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//


#ifndef NCTypes_h
#define NCTypes_h

typedef NS_ENUM(NSInteger, NCNotificationType) {
    kNCNotificationTypeRoom = 0,
    kNCNotificationTypeChat,
    kNCNotificationTypeCall,
    kNCNotificationTypeRecording,
    kNCNotificationTypeFederation
};

typedef NS_OPTIONS(NSInteger, CallFlag) {
    CallFlagDisconnected = 0,
    CallFlagInCall = 1,
    CallFlagWithAudio = 2,
    CallFlagWithVideo = 4,
    CallFlagWithPhone = 8
};

typedef NS_ENUM(NSInteger, CallState) {
    CallStateJoining,
    CallStateWaitingParticipants,
    CallStateReconnecting,
    CallStateInCall,
    CallStateSwitchingToAnotherRoom
};

typedef NS_ENUM(NSInteger, NCParticipantType) {
    kNCParticipantTypeUnknown = 0,
    kNCParticipantTypeOwner,
    kNCParticipantTypeModerator,
    kNCParticipantTypeUser,
    kNCParticipantTypeGuest,
    kNCParticipantTypeUserSelfJoined,
    kNCParticipantTypeGuestModerator
};

typedef NS_ENUM(NSInteger, NCRoomType) {
    kNCRoomTypeOneToOne = 1,
    kNCRoomTypeGroup,
    kNCRoomTypePublic,
    kNCRoomTypeChangelog,
    kNCRoomTypeFormerOneToOne,
    kNCRoomTypeNoteToSelf
};

typedef NS_ENUM(NSInteger, NCRoomNotificationLevel) {
    kNCRoomNotificationLevelDefault = 0,
    kNCRoomNotificationLevelAlways,
    kNCRoomNotificationLevelMention,
    kNCRoomNotificationLevelNever
};

typedef NS_ENUM(NSInteger, NCRoomReadOnlyState) {
    NCRoomReadOnlyStateReadWrite = 0,
    NCRoomReadOnlyStateReadOnly
};

typedef NS_ENUM(NSInteger, NCRoomListableScope) {
    NCRoomListableScopeParticipantsOnly = 0,
    NCRoomListableScopeRegularUsersOnly,
    NCRoomListableScopeEveryone
};

typedef NS_ENUM(NSInteger, NCRoomMentionPermissions) {
    NCRoomMentionPermissionsEveryone = 0,
    NCRoomMentionPermissionsModeratorsOnly
};

typedef NS_ENUM(NSInteger, NCRoomLobbyState) {
    NCRoomLobbyStateAllParticipants = 0,
    NCRoomLobbyStateModeratorsOnly
};

typedef NS_ENUM(NSInteger, NCRoomSIPState) {
    NCRoomSIPStateDisabled = 0,
    NCRoomSIPStateEnabled,
    NCRoomSIPStateEnabledWithoutPIN
};

typedef NS_OPTIONS(NSInteger, NCPermission) {
    NCPermissionDefaultPermissions = 0,
    NCPermissionCustomPermissions = 1,
    NCPermissionStartCall = 2,
    NCPermissionJoinCall = 4,
    NCPermissionCanIgnoreLobby = 8,
    NCPermissionCanPublishAudio = 16,
    NCPermissionCanPublishVideo = 32,
    NCPermissionCanPublishScreen = 64,
    NCPermissionChat = 128,
};

typedef NS_ENUM(NSInteger, NCMessageExpiration) {
    NCMessageExpirationOff = 0,
    NCMessageExpiration1Hour = 3600,
    NCMessageExpiration8Hours = 28800,
    NCMessageExpiration1Day = 86400,
    NCMessageExpiration1Week = 604800,
    NCMessageExpiration4Weeks = 2419200,
};

typedef NS_ENUM(NSInteger, NCCallRecordingState) {
    NCCallRecordingStateStopped = 0,
    NCCallRecordingStateVideoRunning = 1,
    NCCallRecordingStateAudioRunning = 2,
    NCCallRecordingStateVideoStarting = 3,
    NCCallRecordingStateAudioStarting = 4,
    NCCallRecordingStateFailed = 5
};

typedef NS_ENUM(NSInteger, ChatMessageDeliveryState) {
    ChatMessageDeliveryStateSent = 0,
    ChatMessageDeliveryStateRead,
    ChatMessageDeliveryStateSending,
    ChatMessageDeliveryStateDeleting,
    ChatMessageDeliveryStateFailed
};

typedef NS_ENUM(NSInteger, NCChatReactionState) {
    NCChatReactionStateSet = 0,
    NCChatReactionStateAdding,
    NCChatReactionStateRemoving,
    NCChatReactionStateAdded,
    NCChatReactionStateRemoved
};

typedef NS_ENUM(NSInteger, NCPollStatus) {
    NCPollStatusOpen = 0,
    NCPollStatusClosed
};

typedef NS_ENUM(NSInteger, NCPollResultMode) {
    NCPollResultModePublic = 0,
    NCPollResultModeHidden
};

typedef NS_ENUM(NSInteger, NCShareType) {
    NCShareTypeUser = 0,
    NCShareTypeGroup = 1,
    NCShareTypeEmail = 4,
    NCShareTypeRemote = 6,
    NCShareTypeCircle = 7
};

typedef NS_ENUM(NSInteger, NCLocalNotificationType) {
    kNCLocalNotificationTypeMissedCall = 1,
    kNCLocalNotificationTypeCancelledCall,
    kNCLocalNotificationTypeFailedSendChat,
    kNCLocalNotificationTypeCallFromOldAccount,
    kNCLocalNotificationTypeChatNotification,
    kNCLocalNotificationTypeFailedToShareRecording,
    kNCLocalNotificationTypeFailedToAcceptInvitation,
    kNCLocalNotificationTypeRecordingConsentRequired,
    kNCLocalNotificationTypeEndToEndEncryptionUnsupported
};

typedef NS_ENUM(NSInteger, NCPushNotificationType) {
    NCPushNotificationTypeUnknown,
    NCPushNotificationTypeCall,
    NCPushNotificationTypeRoom,
    NCPushNotificationTypeChat,
    NCPushNotificationTypeDelete,
    NCPushNotificationTypeDeleteAll,
    NCPushNotificationTypeDeleteMultiple,
    NCPushNotificationTypeAdminNotification,
    NCPushNotificationTypeRecording,
    NCPUshNotificationTypeFederation,
    NCPushNotificationTypeReminder
};

typedef NS_ENUM(NSInteger, NCPreferredFileSorting) {
    NCAlphabeticalSorting = 1,
    NCModificationDateSorting
};

typedef NS_ENUM(NSInteger, NCSignalingMessageType) {
    kNCSignalingMessageTypeUnknown,
    kNCSignalingMessageTypeCandidate,
    kNCSignalingMessageTypeOffer,
    kNCSignalingMessageTypeAnswer,
    kNCSignalingMessageTypeUnshareScreen,
    kNCSignalingMessageTypeControl,
    kNCSignalingMessageTypeMute,
    kNCSignalingMessageTypeUnmute,
    kNCSignalingMessageTypeNickChanged,
    kNCSignalingMessageTypeRaiseHand,
    kNCSignalingMessageTypeRecording,
    kNCSignalingMessageTypeReaction,
    kNCSignalingMessageTypeStartedTyping,
    kNCSignalingMessageTypeStoppedTyping
};

typedef NS_ENUM(NSInteger, DetailedOptionsSelectorType) {
    DetailedOptionsSelectorTypeDefault = 0,
    DetailedOptionsSelectorTypeAccounts
};

#endif
