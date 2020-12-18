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

+ (instancetype)userFromNCContact:(NCContact *)contact
{
    if (!contact) {
        return nil;
    }
    
    NCUser *user = [[NCUser alloc] init];
    user.name = contact.name;
    user.userId = contact.userId;
    user.source = kParticipantTypeUser;
    
    return user;
}

+ (NSMutableDictionary *)indexedUsersFromUsersArray:(NSArray *)users
{
    NSMutableDictionary *indexedUsers = [[NSMutableDictionary alloc] init];
    for (NCUser *user in users) {
        NSString *index = [[user.name substringToIndex:1] uppercaseString];
        NSRange first = [user.name rangeOfComposedCharacterSequenceAtIndex:0];
        NSRange match = [user.name rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet] options:0 range:first];
        if (match.location == NSNotFound) {
            index = @"#";
        }
        NSMutableArray *usersForIndex = [indexedUsers valueForKey:index];
        if (usersForIndex == nil) {
            usersForIndex = [[NSMutableArray alloc] init];
        }
        [usersForIndex addObject:user];
        [indexedUsers setObject:usersForIndex forKey:index];
    }
    return indexedUsers;
}

+ (NSMutableArray *)combineUsersArray:(NSArray *)firstArray withUsersArray:(NSArray *)secondArray
{
    // Add first array of users
    NSMutableArray *combinedUserArray = [[NSMutableArray alloc] initWithArray:firstArray];
    // Remove first array users from second array
    NSMutableArray *filteredSecondUserArray = [[NSMutableArray alloc] init];
    for (NCUser *secondArrayUser in secondArray) {
        BOOL duplicate = NO;
        for (NCUser *user in combinedUserArray) {
            if ([secondArrayUser.userId isEqualToString:user.userId] && [secondArrayUser.source isEqualToString:kParticipantTypeUser]) {
                duplicate = YES;
                break;
            }
        }
        if (!duplicate) {
            [filteredSecondUserArray addObject:secondArrayUser];
        }
    }
    // Combine both arrays
    [combinedUserArray addObjectsFromArray:filteredSecondUserArray];
    return combinedUserArray;
}

@end
