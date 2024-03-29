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
    return [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:[UIColor systemGreenColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getAwaySFIcon
{
    return [[UIImage systemImageNamed:@"moon.fill"] imageWithTintColor:[UIColor systemYellowColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *)getDoNotDisturbSFIcon
{
    UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithPaletteColors:@[[UIColor whiteColor], [UIColor systemRedColor]]];

    if (@available(iOS 16.1, *)) {
        return [[UIImage systemImageNamed:@"wrongwaysign.fill"] imageByApplyingSymbolConfiguration:conf];
    }

    return [[UIImage systemImageNamed:@"minus.circle.fill"] imageByApplyingSymbolConfiguration:conf];
}

+ (UIImage *)getInvisibleSFIcon
{
    UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBlack];
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
    } else if ([_status isEqualToString:kUserStatusDND]) {
        return [NCUserStatus getDoNotDisturbSFIcon];
    } else if ([_status isEqualToString:kUserStatusInvisible]) {
        return [NCUserStatus getInvisibleSFIcon];
    }

    return [UIImage systemImageNamed:@"person.fill.questionmark"];
}

@end
