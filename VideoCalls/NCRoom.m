//
//  NCRoom.m
//  VideoCalls
//
//  Created by Ivan Sein on 12.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCRoom.h"

#import "NCSettingsController.h"

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

- (BOOL)isDeletable
{
    if ([self canModerate] && ([_participants count] > 2 || _numGuests > 0)) {
        return  YES;
    }
    return NO;
}

- (NSMutableAttributedString *)lastMessageString
{
    BOOL ownMessage = [_lastMessage.actorId isEqualToString:[NCSettingsController sharedInstance].ncUserId];
    NSMutableAttributedString *lastMessage = _lastMessage.parsedMessage;
    
    if (_type == kNCRoomTypeOneToOneCall && !ownMessage) {
        return lastMessage;
    } else {
        NSString *displayName = _lastMessage.actorDisplayName;
        if (ownMessage) {
            displayName = @"You";
        }
        if ([_lastMessage.actorDisplayName isEqualToString:@""]) {
            displayName = @"Guest";
        }
        NSString *messageActor = [NSString stringWithFormat:@"%@: ", [[displayName componentsSeparatedByString:@" "] objectAtIndex:0]];
        lastMessage = [[NSMutableAttributedString alloc] initWithString:messageActor];
        [lastMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold] range:NSMakeRange(0,lastMessage.length)];
        [lastMessage addAttribute:NSForegroundColorAttributeName value:[UIColor lightGrayColor] range:NSMakeRange(0,lastMessage.length)];
        [lastMessage appendAttributedString:_lastMessage.parsedMessage];
    }
    
    return lastMessage;
}


@end
