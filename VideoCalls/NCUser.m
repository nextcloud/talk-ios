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

#import "NCUser.h"

NSString * const kParticipantTypeUser   = @"users";
NSString * const kParticipantTypeGroup  = @"groups";
NSString * const kParticipantTypeEmail  = @"emails";
NSString * const kParticipantTypeCircle = @"circles";

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
