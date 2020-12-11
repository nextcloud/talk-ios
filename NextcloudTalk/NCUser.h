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

#import <Foundation/Foundation.h>

#import "NCContact.h"

typedef enum NCShareType {
    NCShareTypeUser = 0,
    NCShareTypeGroup = 1,
    NCShareTypeEmail = 4,
    NCShareTypeCircle = 7
} NCShareType;

extern NSString * const kParticipantTypeUser;
extern NSString * const kParticipantTypeGroup;
extern NSString * const kParticipantTypeEmail;
extern NSString * const kParticipantTypeCircle;

@interface NCUser : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSString *source;

+ (instancetype)userWithDictionary:(NSDictionary *)userDict;
+ (instancetype)userFromNCContact:(NCContact *)contact;

+ (NSMutableDictionary *)indexedUsersFromUsersArray:(NSArray *)users;
// Duplicate users found in second array will be deleted
+ (NSMutableArray *)combineUsersArray:(NSArray *)firstArray withUsersArray:(NSArray *)secondArray;

@end
