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
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface TalkAccount : RLMObject

@property NSString *accountId;
@property NSString *server;
@property NSString *user;
@property NSString *userId;
@property NSString *userDisplayName;
@property NSString *userDisplayNameScope;
@property NSString *phone;
@property NSString *phoneScope;
@property NSString *email;
@property NSString *emailScope;
@property NSString *address;
@property NSString *addressScope;
@property NSString *website;
@property NSString *websiteScope;
@property NSString *twitter;
@property NSString *twitterScope;
@property NSInteger lastPushSubscription;
@property NSString *deviceIdentifier;
@property NSString *deviceSignature;
@property NSString *userPublicKey;
@property NSInteger unreadBadgeNumber;
@property BOOL unreadNotification;
@property NSInteger lastContactSync;
@property NSString *avatarScope;
@property BOOL hasCustomAvatar;
@property BOOL hasContactSyncEnabled;
@property BOOL active;
@property NSString *lastReceivedConfigurationHash;
@property NSInteger lastNotificationId;
@property NSString *lastNotificationETag;

@end

NS_ASSUME_NONNULL_END
