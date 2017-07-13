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
    room.lastPing = [[roomDict objectForKey:@"lastPing"] integerValue];
    room.guestList = [roomDict objectForKey:@"guestList"];
    room.participants = [roomDict objectForKey:@"participants"];
    
    return room;
}


@end
