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
#import "TalkAccount.h"
#import "ServerCapabilities.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTalkDatabaseFolder;
extern NSString *const kTalkDatabaseFileName;
extern uint64_t const kTalkDatabaseSchemaVersion;

extern NSString * const kCapabilitySystemMessages;
extern NSString * const kCapabilityNotificationLevels;
extern NSString * const kCapabilityInviteGroupsAndMails;
extern NSString * const kCapabilityLockedOneToOneRooms;
extern NSString * const kCapabilityWebinaryLobby;
extern NSString * const kCapabilityChatReadMarker;
extern NSString * const kCapabilityStartCallFlag;
extern NSString * const kCapabilityCirclesSupport;
extern NSString * const kCapabilityChatReferenceId;
extern NSString * const kCapabilityPhonebookSearch;
extern NSString * const kCapabilityChatReadStatus;
extern NSString * const kCapabilityListableRooms;
extern NSString * const kCapabilityDeleteMessages;
extern NSString * const kCapabilityCallFlags;
extern NSString * const kCapabilityRoomDescription;
extern NSString * const kCapabilityTempUserAvatarAPI;
extern NSString * const kCapabilityLocationSharing;
extern NSString * const kCapabilityConversationV4;
extern NSString * const kCapabilitySIPSupport;
extern NSString * const kCapabilityVoiceMessage;
extern NSString * const kCapabilitySignalingV3;
extern NSString * const kCapabilityClearHistory;
extern NSString * const kCapabilityDirectMentionFlag;
extern NSString * const kCapabilityNotificationCalls;
extern NSString * const kCapabilityConversationPermissions;
extern NSString * const kCapabilityChatUnread;
extern NSString * const kCapabilityReactions;
extern NSString * const kCapabilityRichObjectListMedia;
extern NSString * const kCapabilityRichObjectDelete;

extern NSString * const kMinimumRequiredTalkCapability;

@interface NCDatabaseManager : NSObject

+ (instancetype)sharedInstance;

- (NSInteger)numberOfAccounts;
- (TalkAccount *)activeAccount;
- (NSArray *)allAccounts;
- (NSArray *)inactiveAccounts;
- (TalkAccount *)talkAccountForAccountId:(NSString *)accountId;
- (TalkAccount *)talkAccountForUserId:(NSString *)userId inServer:(NSString *)server;
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
- (BOOL)serverHasTalkCapability:(NSString *)capability;
- (BOOL)serverHasTalkCapability:(NSString *)capability forAccountId:(NSString *)accountId;

@end

NS_ASSUME_NONNULL_END
