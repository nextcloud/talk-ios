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

extern NSString *const kTalkDatabaseFolder;
extern NSString *const kTalkDatabaseFileName;
extern uint64_t const kTalkDatabaseSchemaVersion;

@interface TalkAccount : RLMObject
@property NSString *accountId;
@property NSString *server;
@property NSString *user;
@property NSString *userId;
@property NSString *userDisplayName;
@property NSString *phone;
@property BOOL pushNotificationSubscribed;
@property NSData *pushNotificationPublicKey;
@property NSString *deviceIdentifier;
@property NSString *deviceSignature;
@property NSString *userPublicKey;
@property NSInteger unreadBadgeNumber;
@property BOOL unreadNotification;
@property NSInteger lastContactSync;
@property BOOL active;
@end

@interface ServerCapabilities : RLMObject
@property NSString *accountId;
@property NSString *name;
@property NSString *slogan;
@property NSString *url;
@property NSString *logo;
@property NSString *color;
@property NSString *colorElement;
@property NSString *colorElementBright;
@property NSString *colorElementDark;
@property NSString *colorText;
@property NSString *background;
@property BOOL backgroundDefault;
@property BOOL backgroundPlain;
@property NSString *version;
@property NSInteger versionMajor;
@property NSInteger versionMinor;
@property NSInteger versionMicro;
@property NSString *edition;
@property BOOL userStatus;
@property NSString *webDAVRoot;
@property BOOL extendedSupport;
@property RLMArray<RLMString> *talkCapabilities;
@property NSInteger chatMaxLength;
@property BOOL canCreate;
@property BOOL attachmentsAllowed;
@property NSString *attachmentsFolder;
@end

@interface NCDatabaseManager : NSObject

+ (instancetype)sharedInstance;

- (NSInteger)numberOfAccounts;
- (TalkAccount *)activeAccount;
- (NSArray *)inactiveAccounts;
- (TalkAccount *)talkAccountForAccountId:(NSString *)accountId;
- (void)setActiveAccountWithAccountId:(NSString *)accountId;
- (NSString *)accountIdForUser:(NSString *)user inServer:(NSString *)server;
- (void)createAccountForUser:(NSString *)user inServer:(NSString *)server;
- (void)removeAccountWithAccountId:(NSString *)accountId;
- (void)increaseUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (void)decreaseUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (void)resetUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (NSInteger)numberOfUnreadNotifications;
- (NSInteger)numberOfInactiveAccountsWithUnreadNotifications;
- (void)removeUnreadNotificationForInactiveAccounts;

- (ServerCapabilities *)serverCapabilitiesForAccountId:(NSString *)accountId;
- (void)setServerCapabilities:(NSDictionary *)serverCapabilities forAccountId:(NSString *)accountId;

@end

NS_ASSUME_NONNULL_END
