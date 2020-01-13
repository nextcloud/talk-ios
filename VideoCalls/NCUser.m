//
//  NCUser.m
//  VideoCalls
//
//  Created by Ivan Sein on 13.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCUser.h"

@implementation NCUser

+ (instancetype)userWithDictionary:(NSDictionary *)userDict
{
    if (!userDict) {
        return nil;
    }
    
    NCUser *user = [[NCUser alloc] init];
    
    id userId = [userDict objectForKey:@"id"];
    if ([userId isKindOfClass:[NSString class]]) {
        user.userId = userId;
    } else {
        user.userId = [userId stringValue];
    }
    
    id name = [userDict objectForKey:@"label"];
    if ([name isKindOfClass:[NSString class]]) {
        user.name = name;
    } else {
        user.name = [name stringValue];
    }
    
    id source = [userDict objectForKey:@"source"];
    if ([source isKindOfClass:[NSString class]]) {
        user.source = source;
    } else {
        user.source = [source stringValue];
    }
    
    return user;
}

@end
