/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

#import "NCChatMessage.h"
#import "NCTypes.h"

extern NSString * const NCRoomObjectTypeFile;
extern NSString * const NCRoomObjectTypeSharePassword;
extern NSString * const NCRoomObjectTypeRoom;
extern NSString * const NCRoomObjectTypeEvent;
extern NSString * const NCRoomObjectTypeExtendedConversation;

@interface NCRoom : RLMObject

@property (nonatomic, copy, nonnull) NSString *internalId; // accountId@token
@property (nonatomic, copy, nonnull) NSString *accountId;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *roomDescription;
@property (nonatomic, assign) NCRoomType type;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) NCParticipantType participantType;
@property (nonatomic, assign) NSInteger attendeeId;
@property (nonatomic, copy) NSString *attendeePin;
@property (nonatomic, assign) NSInteger unreadMessages;
@property (nonatomic, assign) BOOL unreadMention;
@property (nonatomic, assign) BOOL unreadMentionDirect;
@property (nonatomic, assign) NSInteger lastActivity;
@property (nonatomic, copy, nullable) NSString *lastMessageId;
@property (nonatomic, copy) NSString *lastMessageProxiedJSONString;
@property (nonatomic, assign) BOOL isFavorite;
@property (nonatomic, assign) NCRoomNotificationLevel notificationLevel;
@property (nonatomic, assign) BOOL notificationCalls;
@property (nonatomic, copy) NSString *objectType;
@property (nonatomic, copy) NSString *objectId;
@property (nonatomic, assign) NCRoomReadOnlyState readOnlyState;
@property (nonatomic, assign) NCRoomListableScope listable;
@property (nonatomic, assign) NCMessageExpiration messageExpiration;
@property (nonatomic, assign) NCRoomLobbyState lobbyState;
@property (nonatomic, assign) NSInteger lobbyTimer;
@property (nonatomic, assign) NCRoomSIPState sipState;
@property (nonatomic, assign) BOOL canEnableSIP;
@property (nonatomic, assign) NSInteger lastReadMessage;
@property (nonatomic, assign) NSInteger lastCommonReadMessage;
@property (nonatomic, assign) BOOL canStartCall;
@property (nonatomic, assign) BOOL hasCall;
@property (nonatomic, assign) NSInteger lastUpdate;
@property (nonatomic, copy) NSString *pendingMessage;
@property (nonatomic, assign) BOOL canLeaveConversation;
@property (nonatomic, assign) BOOL canDeleteConversation;
@property (nonatomic, copy, nullable) NSString *status;
@property (nonatomic, copy, nullable) NSString *statusIcon;
@property (nonatomic, copy, nullable) NSString *statusMessage;
@property (nonatomic, assign) CallFlag participantFlags;
@property (nonatomic, assign) NCPermission permissions;
@property (nonatomic, assign) NSInteger attendeePermissions;
@property (nonatomic, assign) NSInteger defaultPermissions;
@property (nonatomic, assign) NCCallRecordingState callRecording;
@property (nonatomic, assign) NSInteger callStartTime;
@property (nonatomic, copy) NSString *avatarVersion;
@property (nonatomic, assign) BOOL isCustomAvatar;
@property (nonatomic, assign) BOOL recordingConsent;
@property (nonatomic, copy) NSString *remoteServer;
@property (nonatomic, copy) NSString *remoteToken;
@property (nonatomic, copy) NSString *lastReceivedProxyHash;
@property (nonatomic, assign) NCRoomMentionPermissions mentionPermissions;
@property (nonatomic, assign) BOOL isArchived;
@property (nonatomic, assign) BOOL isImportant;
@property (nonatomic, assign) BOOL isSensitive;
@property (nonatomic, assign) NSInteger lastPinnedId;
@property (nonatomic, assign) NSInteger hiddenPinnedId;
@property (nonatomic, assign) BOOL hasScheduledMessages;

+ (instancetype _Nullable)roomWithDictionary:(NSDictionary * _Nullable)roomDict andAccountId:(NSString * _Nullable)accountId;
+ (void)updateRoom:(NCRoom * _Nonnull)managedRoom withRoom:(NCRoom * _Nonnull)room;

@end
