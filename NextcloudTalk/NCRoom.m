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

#import "NCRoom.h"

#import "NCDatabaseManager.h"

NSString * const NCRoomObjectTypeFile           = @"file";
NSString * const NCRoomObjectTypeSharePassword  = @"share:password";
NSString * const NCRoomObjectTypeRoom           = @"room";

@implementation NCRoom

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict
{
    if (!roomDict) {
        return nil;
    }
    
    NCRoom *room = [[self alloc] init];
    room.roomId = [[roomDict objectForKey:@"id"] integerValue];
    room.token = [roomDict objectForKey:@"token"];
    room.type = (NCRoomType)[[roomDict objectForKey:@"type"] integerValue];
    room.roomDescription = [roomDict objectForKey:@"description"];
    room.count = [[roomDict objectForKey:@"count"] integerValue];
    room.hasPassword = [[roomDict objectForKey:@"hasPassword"] boolValue];
    room.participantType = (NCParticipantType)[[roomDict objectForKey:@"participantType"] integerValue];
    room.attendeeId = [[roomDict objectForKey:@"attendeeId"] integerValue];
    room.attendeePin = [roomDict objectForKey:@"attendeePin"];
    room.lastPing = [[roomDict objectForKey:@"lastPing"] integerValue];
    room.numGuests = [[roomDict objectForKey:@"numGuests"] integerValue];
    room.unreadMessages = [[roomDict objectForKey:@"unreadMessages"] integerValue];
    room.unreadMention = [[roomDict objectForKey:@"unreadMention"] boolValue];
    room.unreadMentionDirect = [[roomDict objectForKey:@"unreadMentionDirect"] boolValue];
    room.guestList = [roomDict objectForKey:@"guestList"];
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
    room.participantFlags = [[roomDict objectForKey:@"participantFlags"] integerValue];
    room.permissions = [[roomDict objectForKey:@"permissions"] integerValue];
    room.attendeePermissions = [[roomDict objectForKey:@"attendeePermissions"] integerValue];
    room.callPermissions = [[roomDict objectForKey:@"callPermissions"] integerValue];
    room.defaultPermissions = [[roomDict objectForKey:@"defaultPermissions"] integerValue];
    room.callRecording = [[roomDict objectForKey:@"callRecording"] integerValue];
    room.callStartTime = [[roomDict objectForKey:@"callStartTime"] integerValue];
    
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
    
    id participants = [roomDict objectForKey:@"participants"];
    if ([participants isKindOfClass:[NSDictionary class]]) {
        room.participants = (RLMArray<RLMString> *)[participants allKeys];
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
    
    return room;
}

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict andAccountId:(NSString *)accountId
{
    NCRoom *room = [self roomWithDictionary:roomDict];
    if (room) {
        room.accountId = accountId;
        room.internalId = [NSString stringWithFormat:@"%@@%@", room.accountId, room.token];
    }
    
    return room;
}

+ (void)updateRoom:(NCRoom *)managedRoom withRoom:(NCRoom *)room
{
    managedRoom.name = room.name;
    managedRoom.displayName = room.displayName;
    managedRoom.type = room.type;
    managedRoom.roomDescription = room.roomDescription;
    managedRoom.count = room.count;
    managedRoom.hasPassword = room.hasPassword;
    managedRoom.participantType = room.participantType;
    managedRoom.attendeeId = room.attendeeId;
    managedRoom.attendeePin = room.attendeePin;
    managedRoom.lastPing = room.lastPing;
    managedRoom.numGuests = room.numGuests;
    managedRoom.unreadMessages = room.unreadMessages;
    managedRoom.unreadMention = room.unreadMention;
    managedRoom.unreadMentionDirect = room.unreadMentionDirect;
    managedRoom.guestList = room.guestList;
    managedRoom.participants = room.participants;
    managedRoom.lastActivity = room.lastActivity;
    managedRoom.lastMessageId = room.lastMessageId;
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
    managedRoom.callPermissions = room.callPermissions;
    managedRoom.defaultPermissions = room.defaultPermissions;
    managedRoom.callRecording = room.callRecording;
    managedRoom.callStartTime = room.callStartTime;
}

+ (NSString *)primaryKey {
    return @"internalId";
}

- (BOOL)isPublic
{
    return self.type == kNCRoomTypePublic;
}

- (BOOL)isBreakoutRoom
{
    return [self.objectType isEqualToString:NCRoomObjectTypeRoom];
}

- (BOOL)isUserOwnerOrModerator
{
    return self.participantType == kNCParticipantTypeOwner || self.participantType == kNCParticipantTypeModerator;
}

- (BOOL)canModerate
{
    return [self isUserOwnerOrModerator] && ![self isLockedOneToOne];
}

- (BOOL)isNameEditable
{
    return [self canModerate] && self.type != kNCRoomTypeOneToOne && self.type != kNCRoomTypeFormerOneToOne;
}

- (BOOL)isLockedOneToOne
{
    return (self.type == kNCRoomTypeOneToOne && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityLockedOneToOneRooms])
        || self.type == kNCRoomTypeFormerOneToOne;
}

- (BOOL)userCanStartCall
{
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityStartCallFlag] && !self.canStartCall) {
        return NO;
    }
    return YES;
}

- (BOOL)callRecordingIsInActiveState
{
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRecordingV1]) {
        // Starting states and running states are considered active
        if (self.callRecording != NCCallRecordingStateStopped && self.callRecording != NCCallRecordingStateFailed) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)hasUnreadMention
{
    return self.unreadMention || self.unreadMentionDirect || (self.type == kNCRoomTypeOneToOne && self.unreadMessages > 0)
        || (self.type == kNCRoomTypeFormerOneToOne && self.unreadMessages > 0);
}

- (BOOL)isLeavable
{
    // Allow users to leave when there are no moderators in the room
    // (No need to check room type because in one2one rooms users will always be moderators)
    // or when in a group call and there are other participants.
    // We can also check "canLeaveConversation" since v2
    return self.canLeaveConversation || ![self canModerate] || (self.type != kNCRoomTypeOneToOne && [self.participants count] > 1)
        || (self.type != kNCRoomTypeFormerOneToOne && [self.participants count] > 1);
}

- (NSString *)deletionMessage
{
    NSString *message = NSLocalizedString(@"Do you really want to delete this conversation?", nil);
    if (self.type == kNCRoomTypeOneToOne || self.type == kNCRoomTypeFormerOneToOne) {
        message = [NSString stringWithFormat:NSLocalizedString(@"If you delete the conversation, it will also be deleted for %@", nil), self.displayName];
    } else if ([self.participants count] > 1) {
        message = NSLocalizedString(@"If you delete the conversation, it will also be deleted for all other participants.", nil);
    }
    
    return message;
}

- (NSString *)notificationLevelString
{
    return [self stringForNotificationLevel:self.notificationLevel];
}

- (NSString *)stringForNotificationLevel:(NCRoomNotificationLevel)level
{
    NSString *levelString = NSLocalizedString(@"Default", nil);
    switch (level) {
        case kNCRoomNotificationLevelAlways:
            levelString = NSLocalizedString(@"All messages", nil);
            break;
        case kNCRoomNotificationLevelMention:
            levelString = NSLocalizedString(@"@-mentions only", nil);
            break;
        case kNCRoomNotificationLevelNever:
            levelString = NSLocalizedString(@"Off", nil);
            break;
        default:
            break;
    }
    return levelString;
}

- (NSString *)messageExpirationString
{
    return [self stringForMessageExpiration:self.messageExpiration];
}

- (NSString *)stringForMessageExpiration:(NSInteger)messageExpiration
{
    NSString *levelString = NSLocalizedString(@"Off", nil);
    switch (messageExpiration) {
        case NCMessageExpiration4Weeks:
            levelString = NSLocalizedString(@"4 weeks", nil);
            break;
        case NCMessageExpiration1Week:
            levelString = NSLocalizedString(@"1 week", nil);
            break;
        case NCMessageExpiration1Day:
            levelString = NSLocalizedString(@"1 day", nil);
            break;
        case NCMessageExpiration8Hours:
            levelString = NSLocalizedString(@"8 hours", nil);
            break;
        case NCMessageExpiration1Hour:
            levelString = NSLocalizedString(@"1 hour", nil);
            break;
        default:
            break;
    }
    return levelString;
}

- (NSString *)lastMessageString
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    BOOL ownMessage = [self.lastMessage.actorId isEqualToString:activeAccount.userId];
    NSString *actorName = [[self.lastMessage.actorDisplayName componentsSeparatedByString:@" "] objectAtIndex:0];
    // For own messages
    if (ownMessage) {
        actorName = NSLocalizedString(@"You", nil);
    }
    // For guests
    if ([self.lastMessage.actorDisplayName isEqualToString:@""]) {
        actorName = NSLocalizedString(@"Guest", nil);
    }
    // No actor name cases
    if (self.lastMessage.isSystemMessage || (self.type == kNCRoomTypeOneToOne && !ownMessage) || self.type == kNCRoomTypeChangelog) {
        actorName = @"";
    }
    // Use only the first name
    if (![actorName isEqualToString:@""]) {
        actorName = [NSString stringWithFormat:@"%@: ", [[actorName componentsSeparatedByString:@" "] objectAtIndex:0]];
    }
    // Add the last message
    NSString *lastMessage = [NSString stringWithFormat:@"%@%@", actorName, self.lastMessage.parsedMessage.string];
    
    return lastMessage;
}

- (NCChatMessage *)lastMessage
{
    if (self.lastMessageId) {
        NCChatMessage *unmanagedChatMessage = nil;
        NCChatMessage *managedChatMessage = [NCChatMessage objectsWhere:@"internalId = %@", self.lastMessageId].firstObject;
        if (managedChatMessage) {
            unmanagedChatMessage = [[NCChatMessage alloc] initWithValue:managedChatMessage];
        }
        return unmanagedChatMessage;
    }
    
    return nil;
}


@end
