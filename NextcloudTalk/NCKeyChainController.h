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
#import "UICKeyChainStore.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kNCServerKey;
extern NSString * const kNCUserKey;
extern NSString * const kNCUserIdKey;
extern NSString * const kNCUserDisplayNameKey;
extern NSString * const kNCTokenKey;
extern NSString * const kNCPushTokenKey;
extern NSString * const kNCNormalPushTokenKey;
extern NSString * const kNCPushKitTokenKey;
extern NSString * const kNCPushSubscribedKey;
extern NSString * const kNCPNPublicKey;
extern NSString * const kNCPNPrivateKey;
extern NSString * const kNCDeviceIdentifier;
extern NSString * const kNCDeviceSignature;
extern NSString * const kNCUserPublicKey;
extern NSString * const kNCUserDefaultBrowser;
extern NSString * const kNCLockScreenPasscode;
extern NSString * const kNCLockScreenPasscodeType;

@interface NCKeyChainController : NSObject

@property (nonatomic, copy) UICKeyChainStore *keychain;

+ (instancetype)sharedInstance;
- (void)setToken:(NSString *)token forAccountId:(NSString *)accountId;
- (NSString *)tokenForAccountId:(NSString *)accountId;
- (void)setPushNotificationPrivateKey:(NSData *)privateKey forAccountId:(NSString *)accountId;
- (NSData *)pushNotificationPrivateKeyForAccountId:(NSString *)accountId;
- (NSString *)pushTokenSHA512;
- (NSString *)combinedPushToken;
- (void)removeAllItems;

@end

NS_ASSUME_NONNULL_END
