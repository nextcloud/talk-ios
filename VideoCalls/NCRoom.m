//
//  NCRoom.m
//  VideoCalls
//
//  Created by Ivan Sein on 12.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCRoom.h"

#import "NCSettingsController.h"

NSString * const NCRoomObjectTypeFile           = @"file";
NSString * const NCRoomObjectTypeSharePassword  = @"share:password";

@implementation NCRoom

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict
{
    if (!roomDict) {
        return nil;
    }
    
    NCRoom *room = [[NCRoom alloc] init];
    room.roomId = [[roomDict objectForKey:@"id"] integerValue];
    room.token = [roomDict objectForKey:@"token"];
    room.type = (NCRoomType)[[roomDict objectForKey:@"type"] integerValue];
    room.count = [[roomDict objectForKey:@"count"] integerValue];
    room.hasPassword = [[roomDict objectForKey:@"hasPassword"] boolValue];
    room.participantType = (NCParticipantType)[[roomDict objectForKey:@"participantType"] integerValue];
    room.lastPing = [[roomDict objectForKey:@"lastPing"] integerValue];
    room.numGuests = [[roomDict objectForKey:@"numGuests"] integerValue];
    room.unreadMessages = [[roomDict objectForKey:@"unreadMessages"] integerValue];
    room.unreadMention = [[roomDict objectForKey:@"unreadMention"] boolValue];
    room.guestList = [roomDict objectForKey:@"guestList"];
    room.participants = [roomDict objectForKey:@"participants"];
    room.lastActivity = [[roomDict objectForKey:@"lastActivity"] integerValue];
    room.lastMessage = [NCChatMessage messageWithDictionary:[roomDict objectForKey:@"lastMessage"]];
    room.isFavorite = [[roomDict objectForKey:@"isFavorite"] boolValue];
    room.notificationLevel = (NCRoomNotificationLevel)[[roomDict objectForKey:@"notificationLevel"] integerValue];
    room.objectType = [roomDict objectForKey:@"objectType"];
    room.objectId = [roomDict objectForKey:@"objectId"];
    
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
    
    return room;
}

- (BOOL)isPublic
{
    return _type == kNCRoomTypePublicCall;
}

- (BOOL)canModerate
{
    return _participantType == kNCParticipantTypeOwner || _participantType == kNCParticipantTypeModerator;
}

- (BOOL)isNameEditable
{
    if ([self canModerate] && _type != kNCRoomTypeOneToOneCall) {
        return  YES;
    }
    return NO;
}

- (BOOL)isLeavable
{
    // Allow users to leave when there are no moderators in the room
    // (No need to check room type because in one2one rooms users will always be moderators)
    // or when in a group call and there are other participants.
    if (![self canModerate] || (_type != kNCRoomTypeOneToOneCall && [_participants count] > 1)) {
        return  YES;
    }
    return NO;
}

- (BOOL)shouldShowLastMessageActorName
{
    return _type != kNCRoomTypeOneToOneCall && !_lastMessage.isSystemMessage;
}

- (NSString *)notificationLevelString
{
    return [self stringForNotificationLevel:_notificationLevel];
}

- (NSString *)stringForNotificationLevel:(NCRoomNotificationLevel)level
{
    NSString *levelString = @"Default";
    switch (level) {
        case kNCRoomNotificationLevelAlways:
            levelString = @"Always";
            break;
        case kNCRoomNotificationLevelMention:
            levelString = @"On mention";
            break;
        case kNCRoomNotificationLevelNever:
            levelString = @"Never";
            break;
        default:
            break;
    }
    return levelString;
}

- (NSMutableAttributedString *)lastMessageActorString
{
    if (![self shouldShowLastMessageActorName]) {
        return nil;
    }
    
    NSString *displayName = _lastMessage.actorDisplayName;
    // For own messages
    if ([_lastMessage.actorId isEqualToString:[NCSettingsController sharedInstance].ncUserId]) {
        displayName = @"You";
    }
    // For guests
    if ([_lastMessage.actorDisplayName isEqualToString:@""]) {
        displayName = @"Guest";
    }
    NSString *messageActor = [NSString stringWithFormat:@"%@: ", displayName];
    NSMutableAttributedString *actorDisplayName = [[NSMutableAttributedString alloc] initWithString:messageActor];
    [actorDisplayName addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular] range:NSMakeRange(0,actorDisplayName.length)];
    [actorDisplayName addAttribute:NSForegroundColorAttributeName value:[UIColor darkTextColor] range:NSMakeRange(0,actorDisplayName.length)];
    
    return actorDisplayName;
}

- (NSMutableAttributedString *)lastMessageString
{
    NSMutableAttributedString *lastMessage = _lastMessage.parsedMessage;
    [lastMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular] range:NSMakeRange(0,lastMessage.length)];
    [lastMessage addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:0 alpha:0.4] range:NSMakeRange(0,lastMessage.length)];
    
    return lastMessage;
}


@end
