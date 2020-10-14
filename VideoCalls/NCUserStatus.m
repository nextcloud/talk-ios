//
//  NCUserStatus.m
//  VideoCalls
//
//  Created by Ivan Sein on 16.09.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import "NCUserStatus.h"

NSString * const kUserStatusOnline      = @"online";
NSString * const kUserStatusAway        = @"away";
NSString * const kUserStatusDND         = @"dnd";
NSString * const kUserStatusInvisible   = @"invisible";
NSString * const kUserStatusOffline     = @"offline";

@implementation NCUserStatus

+ (instancetype)userStatusWithDictionary:(NSDictionary *)userStatusDict
{
    if (!userStatusDict) {
        return nil;
    }
    
    NCUserStatus *userStatus = [[NCUserStatus alloc] init];
    userStatus.userId = [userStatusDict objectForKey:@"userId"];
    userStatus.status = [userStatusDict objectForKey:@"status"];
    userStatus.statusIsUserDefined = [[userStatusDict objectForKey:@"statusIsUserDefined"] boolValue];
    userStatus.message = [userStatusDict objectForKey:@"message"];
    userStatus.messageId = [userStatusDict objectForKey:@"messageId"];
    userStatus.messageIsPredefined = [[userStatusDict objectForKey:@"messageIsPredefined"] boolValue];
    userStatus.icon = [userStatusDict objectForKey:@"icon"];
    
    id clearAt = [userStatusDict objectForKey:@"clearAt"];
    if ([clearAt isKindOfClass:[NSNull class]]) {
        userStatus.clearAt = 0;
    } else {
        userStatus.clearAt = [[userStatusDict objectForKey:@"clearAt"] integerValue];
    }
    
    return userStatus;
}

+ (NSString *)readableUserStatusFromUserStatus:(NSString *)userStatus
{
    NSString *readableUserStatus = nil;
    
    if ([userStatus isEqualToString:kUserStatusOnline]) {
        readableUserStatus = NSLocalizedString(@"Online", nil);
    } else if ([userStatus isEqualToString:kUserStatusAway]) {
        readableUserStatus = NSLocalizedString(@"Away", nil);
    } else if ([userStatus isEqualToString:kUserStatusDND]) {
        readableUserStatus = NSLocalizedString(@"Do not disturb", nil);
    } else if ([userStatus isEqualToString:kUserStatusInvisible]) {
        readableUserStatus = NSLocalizedString(@"Invisible", nil);
    } else if ([userStatus isEqualToString:kUserStatusOffline]) {
        readableUserStatus = NSLocalizedString(@"Offline", nil);
    }
    
    return readableUserStatus;
}

+ (NSString *)userStatusImageNameForStatus:(NSString *)userStatus ofSize:(NSInteger)size
{
    NSString *userStatusImageName = nil;
    NSString *sizeString = size ? [NSString stringWithFormat:@"-%ld", (long)size] : @"";
    
    if ([userStatus isEqualToString:kUserStatusOnline]) {
        userStatusImageName = [NSString stringWithFormat:@"user-status-online%@", sizeString];
    } else if ([userStatus isEqualToString:kUserStatusAway]) {
        userStatusImageName = [NSString stringWithFormat:@"user-status-away%@", sizeString];
    } else if ([userStatus isEqualToString:kUserStatusDND]) {
        userStatusImageName = [NSString stringWithFormat:@"user-status-dnd%@", sizeString];
    } else if ([userStatus isEqualToString:kUserStatusInvisible]) {
        userStatusImageName = [NSString stringWithFormat:@"user-status-invisible%@", sizeString];
    }
    
    return userStatusImageName;
}

- (NSString *)readableUserStatus
{
    return [NCUserStatus readableUserStatusFromUserStatus:_status];
}

- (NSString *)userStatusImageNameOfSize:(NSInteger)size
{
    return [NCUserStatus userStatusImageNameForStatus:_status ofSize:size];
}

@end
