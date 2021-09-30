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

- (NSString *)userStatusImageNameOfSize:(NSInteger)size
{
    return [NCUserStatus userStatusImageNameForStatus:_status ofSize:size];
}

@end
