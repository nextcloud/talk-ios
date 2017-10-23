//
//  NCRoom.m
//  VideoCalls
//
//  Created by Ivan Sein on 12.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCRoom.h"

@implementation NCRoom

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict
{
    if (!roomDict) {
        return nil;
    }
    
    NCRoom *room = [[NCRoom alloc] init];
    room.roomId = [roomDict objectForKey:@"id"];
    room.token = [roomDict objectForKey:@"token"];
    room.name = [roomDict objectForKey:@"name"];
    room.displayName = [roomDict objectForKey:@"displayName"];
    room.type = (NCRoomType)[[roomDict objectForKey:@"type"] integerValue];
    room.count = [[roomDict objectForKey:@"count"] integerValue];
    room.hasPassword = [[roomDict objectForKey:@"hasPassword"] boolValue];
    room.participantType = (NCParticipantType)[[roomDict objectForKey:@"participantType"] integerValue];
    room.lastPing = [[roomDict objectForKey:@"lastPing"] integerValue];
    room.numGuests = [[roomDict objectForKey:@"numGuests"] integerValue];
    room.guestList = [roomDict objectForKey:@"guestList"];
    room.participants = [roomDict objectForKey:@"participants"];
    
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


@end
