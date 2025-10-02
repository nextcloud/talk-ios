/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCRoom.h"

#import "NCDatabaseManager.h"
#import "NextcloudTalk-Swift.h"

NSString * const NCRoomObjectTypeFile                   = @"file";
NSString * const NCRoomObjectTypeSharePassword          = @"share:password";
NSString * const NCRoomObjectTypeRoom                   = @"room";
NSString * const NCRoomObjectTypeEvent                  = @"event";
NSString * const NCRoomObjectTypeExtendedConversation   = @"extended_conversation";

@implementation NCRoom

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict andAccountId:(NSString *)accountId
{

    if (!roomDict) {
        return nil;
    }

    NCRoom *room = [[self alloc] init];
    room.accountId = accountId;
    room.token = [roomDict objectForKey:@"token"];
    room.internalId = [NSString stringWithFormat:@"%@@%@", room.accountId, room.token];
    room.type = (NCRoomType)[[roomDict objectForKey:@"type"] integerValue];
    room.roomDescription = [roomDict objectForKey:@"description"];
    room.hasPassword = [[roomDict objectForKey:@"hasPassword"] boolValue];
    room.participantType = (NCParticipantType)[[roomDict objectForKey:@"participantType"] integerValue];
    room.attendeeId = [[roomDict objectForKey:@"attendeeId"] integerValue];
    room.attendeePin = [roomDict objectForKey:@"attendeePin"];
    room.unreadMessages = [[roomDict objectForKey:@"unreadMessages"] integerValue];
    room.unreadMention = [[roomDict objectForKey:@"unreadMention"] boolValue];
    room.unreadMentionDirect = [[roomDict objectForKey:@"unreadMentionDirect"] boolValue];
    room.lastActivity = [[roomDict objectForKey:@"lastActivity"] integerValue];
    room.isFavorite = [[roomDict objectForKey:@"isFavorite"] boolValue];
    room.notificationLevel = (NCRoomNotificationLevel)[[roomDict objectForKey:@"notificationLevel"] integerValue];
    room.notificationCalls = [[roomDict objectForKey:@"notificationCalls"] boolValue];
    room.objectType = [roomDict objectForKey:@"objectType"];
    room.objectId = [roomDict objectForKey:@"objectId"];
    room.readOnlyState = (NCRoomReadOnlyState)[[roomDict objectForKey:@"readOnly"] integerValue];
    room.listable = (NCRoomListableScope)[[roomDict objectForKey:@"listable"] integerValue];
    room.messageExpiration = [[roomDict objectForKey:@"messageExpiration"] integerValue];
    room.lobbyState = (NCRoomLobbyState)[[roomDict objectForKey:@"lobbyState"] integerValue];
    room.lobbyTimer = [[roomDict objectForKey:@"lobbyTimer"] integerValue];
    room.sipState = (NCRoomSIPState)[[roomDict objectForKey:@"sipEnabled"] integerValue];
    room.canEnableSIP = [[roomDict objectForKey:@"canEnableSIP"] boolValue];
    room.lastReadMessage = [[roomDict objectForKey:@"lastReadMessage"] integerValue];
    room.lastCommonReadMessage = [[roomDict objectForKey:@"lastCommonReadMessage"] integerValue];
    room.canStartCall = [[roomDict objectForKey:@"canStartCall"] boolValue];
    room.hasCall = [[roomDict objectForKey:@"hasCall"] boolValue];
    room.canLeaveConversation = [[roomDict objectForKey:@"canLeaveConversation"] boolValue];
    room.canDeleteConversation = [[roomDict objectForKey:@"canDeleteConversation"] boolValue];
    room.permissions = [[roomDict objectForKey:@"permissions"] integerValue];
    room.attendeePermissions = [[roomDict objectForKey:@"attendeePermissions"] integerValue];
    room.defaultPermissions = [[roomDict objectForKey:@"defaultPermissions"] integerValue];
    room.callRecording = [[roomDict objectForKey:@"callRecording"] integerValue];
    room.callStartTime = [[roomDict objectForKey:@"callStartTime"] integerValue];
    room.avatarVersion = [roomDict objectForKey:@"avatarVersion"];
    room.isCustomAvatar = [roomDict objectForKey:@"isCustomAvatar"];
    room.recordingConsent = [[roomDict objectForKey:@"recordingConsent"] integerValue];
    room.remoteServer = [roomDict objectForKey:@"remoteServer"];
    room.remoteToken = [roomDict objectForKey:@"remoteToken"];
    room.mentionPermissions = [[roomDict objectForKey:@"mentionPermissions"] integerValue];
    room.isArchived = [[roomDict objectForKey:@"isArchived"] boolValue];
    room.isImportant = [[roomDict objectForKey:@"isImportant"] boolValue];
    room.isSensitive = [[roomDict objectForKey:@"isSensitive"] boolValue];

    // Local-only field -> update only if there's actually a value
    if ([roomDict objectForKey:@"pendingMessage"] != nil) {
        room.pendingMessage = [roomDict objectForKey:@"pendingMessage"];
    }
    
    id name = [roomDict objectForKey:@"name"];
    if ([name isKindOfClass:[NSString class]]) {
        room.name = name;
    } else {
        room.name = [name stringValue];
    }
    
    id displayName = [roomDict objectForKey:@"displayName"];
    if ([displayName isKindOfClass:[NSString class]]) {
        room.displayName = displayName;
    } else {
        room.displayName = [displayName stringValue];
    }
    
    // Optional attribute
    id status = [roomDict objectForKey:@"status"];
    if ([status isKindOfClass:[NSString class]]) {
        room.status = status;
    }
    
    // Optional attribute
    id statusIcon = [roomDict objectForKey:@"statusIcon"];
    if ([statusIcon isKindOfClass:[NSString class]]) {
        room.statusIcon = statusIcon;
    }
    
    // Optional attribute
    id statusMessage = [roomDict objectForKey:@"statusMessage"];
    if ([statusMessage isKindOfClass:[NSString class]]) {
        room.statusMessage = statusMessage;
    }

    // Participants flags is null in Talk versions that don't support conversation v4 API
    id participantFlags = [roomDict objectForKey:@"participantFlags"];
    if ([participantFlags isKindOfClass:[NSNumber class]]) {
        room.participantFlags = [participantFlags integerValue];
    }

    // Last message proxied (only for Federated rooms)
    if ([room isFederated]) {
        id lastMessageProxied = [roomDict objectForKey:@"lastMessage"];
        if ([lastMessageProxied isKindOfClass:[NSDictionary class]]) {
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:lastMessageProxied
                                                               options:0
                                                                 error:&error];
            if (jsonData) {
                room.lastMessageProxiedJSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            } else {
                NSLog(@"Error generating reactions JSON string: %@", error);
            }
        }
    }

    return room;
}

+ (void)updateRoom:(NCRoom *)managedRoom withRoom:(NCRoom *)room
{
    managedRoom.name = room.name;
    managedRoom.displayName = room.displayName;
    managedRoom.type = room.type;
    managedRoom.roomDescription = room.roomDescription;
    managedRoom.hasPassword = room.hasPassword;
    managedRoom.participantType = room.participantType;
    managedRoom.attendeeId = room.attendeeId;
    managedRoom.attendeePin = room.attendeePin;
    managedRoom.unreadMessages = room.unreadMessages;
    managedRoom.unreadMention = room.unreadMention;
    managedRoom.unreadMentionDirect = room.unreadMentionDirect;
    managedRoom.lastActivity = room.lastActivity;
    managedRoom.lastMessageId = room.lastMessageId;
    managedRoom.lastMessageProxiedJSONString = room.lastMessageProxiedJSONString;
    managedRoom.isFavorite = room.isFavorite;
    managedRoom.notificationLevel = room.notificationLevel;
    managedRoom.notificationCalls = room.notificationCalls;
    managedRoom.objectType = room.objectType;
    managedRoom.objectId = room.objectId;
    managedRoom.readOnlyState = room.readOnlyState;
    managedRoom.listable = room.listable;
    managedRoom.messageExpiration = room.messageExpiration;
    managedRoom.lobbyState = room.lobbyState;
    managedRoom.lobbyTimer = room.lobbyTimer;
    managedRoom.sipState = room.sipState;
    managedRoom.canEnableSIP = room.canEnableSIP;
    managedRoom.lastReadMessage = room.lastReadMessage;
    managedRoom.lastCommonReadMessage = room.lastCommonReadMessage;
    managedRoom.canStartCall = room.canStartCall;
    managedRoom.hasCall = room.hasCall;
    managedRoom.lastUpdate = room.lastUpdate;
    managedRoom.canLeaveConversation = room.canLeaveConversation;
    managedRoom.canDeleteConversation = room.canDeleteConversation;
    managedRoom.status = room.status;
    managedRoom.statusIcon = room.statusIcon;
    managedRoom.statusMessage = room.statusMessage;
    managedRoom.participantFlags = room.participantFlags;
    managedRoom.permissions = room.permissions;
    managedRoom.attendeePermissions = room.attendeePermissions;
    managedRoom.defaultPermissions = room.defaultPermissions;
    managedRoom.callRecording = room.callRecording;
    managedRoom.callStartTime = room.callStartTime;
    managedRoom.avatarVersion = room.avatarVersion;
    managedRoom.isCustomAvatar = room.isCustomAvatar;
    managedRoom.recordingConsent = room.recordingConsent;
    managedRoom.remoteToken = room.remoteToken;
    managedRoom.remoteServer = room.remoteServer;
    managedRoom.mentionPermissions = room.mentionPermissions;
    managedRoom.isArchived = room.isArchived;
    managedRoom.isImportant = room.isImportant;
    managedRoom.isSensitive = room.isSensitive;
}

+ (NSString *)primaryKey {
    return @"internalId";
}

@end
