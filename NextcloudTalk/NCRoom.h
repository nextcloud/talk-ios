/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
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

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

#import "NCRoomParticipant.h"
#import "NCChatMessage.h"

typedef enum NCRoomType {
    kNCRoomTypeOneToOne = 1,
    kNCRoomTypeGroup,
    kNCRoomTypePublic,
    kNCRoomTypeChangelog,
    kNCRoomTypeFormerOneToOne
} NCRoomType;

typedef enum NCRoomNotificationLevel {
    kNCRoomNotificationLevelDefault = 0,
    kNCRoomNotificationLevelAlways,
    kNCRoomNotificationLevelMention,
    kNCRoomNotificationLevelNever
} NCRoomNotificationLevel;

typedef enum NCRoomReadOnlyState {
    NCRoomReadOnlyStateReadWrite = 0,
    NCRoomReadOnlyStateReadOnly
} NCRoomReadOnlyState;

typedef enum NCRoomListableScope {
    NCRoomListableScopeParticipantsOnly = 0,
    NCRoomListableScopeRegularUsersOnly,
    NCRoomListableScopeEveryone
} NCRoomListableScope;

typedef enum NCRoomLobbyState {
    NCRoomLobbyStateAllParticipants = 0,
    NCRoomLobbyStateModeratorsOnly
} NCRoomLobbyState;

typedef enum NCRoomSIPState {
    NCRoomSIPStateDisabled = 0,
    NCRoomSIPStateEnabled,
    NCRoomSIPStateEnabledWithoutPIN
} NCRoomSIPState;

typedef enum NCPermission {
    NCPermissionDefaultPermissions = 0,
    NCPermissionCustomPermissions = 1,
    NCPermissionStartCall = 2,
    NCPermissionJoinCall = 4,
    NCPermissionCanIgnoreLobby = 8,
    NCPermissionCanPublishAudio = 16,
    NCPermissionCanPublishVideo = 32,
    NCPermissionCanPublishScreen = 64,
    NCPermissionChat = 128,
} NCPermission;

typedef enum NCMessageExpiration {
    NCMessageExpirationOff = 0,
    NCMessageExpiration1Hour = 3600,
    NCMessageExpiration8Hours = 28800,
    NCMessageExpiration1Day = 86400,
    NCMessageExpiration1Week = 604800,
    NCMessageExpiration4Weeks = 2419200,
} NCMessageExpiration;

typedef enum NCCallRecordingState {
    NCCallRecordingStateStopped = 0,
    NCCallRecordingStateVideoRunning = 1,
    NCCallRecordingStateAudioRunning = 2,
    NCCallRecordingStateVideoStarting = 3,
    NCCallRecordingStateAudioStarting = 4,
    NCCallRecordingStateFailed = 5
} NCCallRecordingState;

extern NSString * const NCRoomObjectTypeFile;
extern NSString * const NCRoomObjectTypeSharePassword;
extern NSString * const NCRoomObjectTypeRoom;

@interface NCRoom : RLMObject

@property (nonatomic, copy) NSString *internalId; // accountId@token
@property (nonatomic, assign) NSInteger roomId;
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *roomDescription;
@property (nonatomic, assign) NCRoomType type;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) NCParticipantType participantType;
@property (nonatomic, assign) NSInteger attendeeId;
@property (nonatomic, copy) NSString *attendeePin;
@property (nonatomic, assign) NSInteger lastPing;
@property (nonatomic, assign) NSInteger numGuests;
@property (nonatomic, assign) NSInteger unreadMessages;
@property (nonatomic, assign) BOOL unreadMention;
@property (nonatomic, assign) BOOL unreadMentionDirect;
@property (nonatomic, copy) NSString *guestList;
@property (nonatomic, strong) RLMArray<RLMString> *participants;
@property (nonatomic, assign) NSInteger lastActivity;
@property (nonatomic, copy) NSString *lastMessageId;
@property (nonatomic, assign) BOOL isFavorite;
@property (nonatomic, assign) NCRoomNotificationLevel notificationLevel;
@property (nonatomic, assign) BOOL notificationCalls;
@property (nonatomic, copy) NSString *objectType;
@property (nonatomic, copy) NSString *objectId;
@property (nonatomic, assign) NCRoomReadOnlyState readOnlyState;
@property (nonatomic, assign) NCRoomListableScope listable;
@property (nonatomic, assign) NSInteger messageExpiration;
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
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *statusIcon;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, assign) NSInteger participantFlags;
@property (nonatomic, assign) NSInteger permissions;
@property (nonatomic, assign) NSInteger attendeePermissions;
@property (nonatomic, assign) NSInteger callPermissions;
@property (nonatomic, assign) NSInteger defaultPermissions;
@property (nonatomic, assign) NSInteger callRecording;
@property (nonatomic, assign) NSInteger callStartTime;

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict;
+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict andAccountId:(NSString *)accountId;
+ (void)updateRoom:(NCRoom *)managedRoom withRoom:(NCRoom *)room;

- (BOOL)isPublic;
- (BOOL)isBreakoutRoom;
- (BOOL)isUserOwnerOrModerator;
- (BOOL)canModerate;
- (BOOL)isNameEditable;
- (BOOL)isLeavable;
- (BOOL)userCanStartCall;
- (BOOL)hasUnreadMention;
- (BOOL)callRecordingIsInActiveState;
- (NSString *)deletionMessage;
- (NSString *)notificationLevelString;
- (NSString *)stringForNotificationLevel:(NCRoomNotificationLevel)level;
- (NSString *)messageExpirationString;
- (NSString *)stringForMessageExpiration:(NSInteger)messageExpiration;
- (NSString *)lastMessageString;
- (NCChatMessage *)lastMessage;

@end
