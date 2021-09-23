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

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kUserStatusOnline;
extern NSString * const kUserStatusAway;
extern NSString * const kUserStatusDND;
extern NSString * const kUserStatusInvisible;
extern NSString * const kUserStatusOffline;

@interface NCUserStatus : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) BOOL statusIsUserDefined;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, assign) BOOL messageIsPredefined;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, assign) NSInteger clearAt;

+ (instancetype)userStatusWithDictionary:(NSDictionary *)userStatusDict;
+ (NSString *)readableUserStatusFromUserStatus:(NSString *)userStatus;
+ (NSString *)userStatusImageNameForStatus:(NSString *)userStatus ofSize:(NSInteger)size;
- (NSString *)readableUserStatus;
- (NSString *)readableUserStatusMessage;
- (NSString *)userStatusImageNameOfSize:(NSInteger)size;

@end

NS_ASSUME_NONNULL_END
