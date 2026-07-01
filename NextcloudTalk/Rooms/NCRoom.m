/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCRoom.h"

#import "TalkAccount.h"
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
    room.isCustomAvatar = [[roomDict objectForKey:@"isCustomAvatar"] boolValue];
    room.recordingConsent = [[roomDict objectForKey:@"recordingConsent"] integerValue];
    room.remoteServer = [roomDict objectForKey:@"remoteServer"];
    room.remoteToken = [roomDict objectForKey:@"remoteToken"];
    room.mentionPermissions = [[roomDict objectForKey:@"mentionPermissions"] integerValue];
    room.isArchived = [[roomDict objectForKey:@"isArchived"] boolValue];
    room.isImportant = [[roomDict objectForKey:@"isImportant"] boolValue];
    room.isSensitive = [[roomDict objectForKey:@"isSensitive"] boolValue];
    room.lastPinnedId = [[roomDict objectForKey:@"lastPinnedId"] integerValue];
    room.hiddenPinnedId = [[roomDict objectForKey:@"hiddenPinnedId"] integerValue];
    room.hasScheduledMessages = [[roomDict objectForKey:@"hasScheduledMessages"] boolValue];
    room.attributes = [[roomDict objectForKey:@"attributes"] integerValue];

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

+ (NSString *)primaryKey {
    return @"internalId";
}

@end
