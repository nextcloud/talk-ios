/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCUserStatus.h"

NSString * const kUserStatusOnline      = @"online";
NSString * const kUserStatusAway        = @"away";
NSString * const kUserStatusBusy        = @"busy";
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
    userStatus.messageId = [userStatusDict objectForKey:@"messageId"];
    userStatus.messageIsPredefined = [[userStatusDict objectForKey:@"messageIsPredefined"] boolValue];
    
    id message = [userStatusDict objectForKey:@"message"];
    if ([message isKindOfClass:[NSString class]]) {
        userStatus.message = message;
    }
    
    id icon = [userStatusDict objectForKey:@"icon"];
    if ([icon isKindOfClass:[NSString class]]) {
        userStatus.icon = icon;
    }
    
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
    } else if ([userStatus isEqualToString:kUserStatusBusy]) {
        readableUserStatus = NSLocalizedString(@"Busy", nil);
    } else if ([userStatus isEqualToString:kUserStatusDND]) {
        readableUserStatus = NSLocalizedString(@"Do not disturb", nil);
    } else if ([userStatus isEqualToString:kUserStatusInvisible]) {
        readableUserStatus = NSLocalizedString(@"Invisible", nil);
    } else if ([userStatus isEqualToString:kUserStatusOffline]) {
        readableUserStatus = NSLocalizedString(@"Offline", nil);
    }
    
    return readableUserStatus;
}

+ (UIImage *)getOnlineSFIcon
{
    return [[UIImage systemImageNamed:@"checkmark.circle.fill"] imageWithTintColor:[UIColor systemGreenColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getAwaySFIcon
{
    return [[UIImage systemImageNamed:@"clock.fill"] imageWithTintColor:[UIColor systemYellowColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getBusySFIcon
{
    return [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:[UIColor systemRedColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getDoNotDisturbSFIcon
{
    return [[UIImage systemImageNamed:@"minus.circle.fill"] imageWithTintColor:[UIColor systemRedColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getInvisibleSFIcon
{
    UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBold];
    return [[[UIImage systemImageNamed:@"circle"] imageByApplyingSymbolConfiguration:conf] imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (NSString *)readableUserStatus
{
    return [NCUserStatus readableUserStatusFromUserStatus:_status];
}

- (NSString *)readableUserStatusMessage
{
    NSString *userStatusIcon = nil;
    if (_icon && ![_icon isEqualToString:@""]) {
        userStatusIcon = _icon;
    }
    
    NSString *userStatusMessage = nil;
    if (_message && ![_message isEqualToString:@""]) {
        userStatusMessage = _message;
    }
    
    return userStatusIcon ? [NSString stringWithFormat:@"%@  %@", userStatusIcon, _message] : userStatusMessage;
}

- (NSString *)readableUserStatusOrMessage
{
    NSString *userStatusMessage = [self readableUserStatusMessage];

    if ([userStatusMessage length] > 0) {
        return userStatusMessage;
    }

    return [self readableUserStatus];
}

- (UIImage *)getSFUserStatusIcon
{
    if ([_status isEqualToString:kUserStatusOnline]) {
        return [NCUserStatus getOnlineSFIcon];
    } else if ([_status isEqualToString:kUserStatusAway]) {
        return [NCUserStatus getAwaySFIcon];
    } else if ([_status isEqualToString:kUserStatusBusy]) {
        return [NCUserStatus getBusySFIcon];
    } else if ([_status isEqualToString:kUserStatusDND]) {
        return [NCUserStatus getDoNotDisturbSFIcon];
    } else if ([_status isEqualToString:kUserStatusInvisible]) {
        return [NCUserStatus getInvisibleSFIcon];
    }

    return [UIImage systemImageNamed:@"person.fill.questionmark"];
}

- (BOOL)hasVisibleStatusIcon
{
    return [_status isEqualToString:kUserStatusOnline] ||
    [_status isEqualToString:kUserStatusAway] ||
    [_status isEqualToString:kUserStatusBusy] ||
    [_status isEqualToString:kUserStatusDND] ||
    [_status isEqualToString:kUserStatusInvisible];
}

@end
