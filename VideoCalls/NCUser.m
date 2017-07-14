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
    user.userId = [[userDict objectForKey:@"value"] objectForKey:@"shareWith"];
    user.name = [userDict objectForKey:@"label"];
    
    return user;
}

@end
