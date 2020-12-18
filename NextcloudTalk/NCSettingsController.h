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

#import "ARDSettingsModel.h"
#import "UICKeyChainStore.h"


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

extern NSInteger const kDefaultChatMaxLength;
extern NSString * const kMinimumRequiredTalkCapability;

typedef void (^UpdatedProfileCompletionBlock)(NSError *error);
typedef void (^LogoutCompletionBlock)(NSError *error);
typedef void (^GetCapabilitiesCompletionBlock)(NSError *error);
typedef void (^GetSignalingConfigCompletionBlock)(NSError *error);

extern NSString * const NCTalkNotInstalledNotification;
extern NSString * const NCOutdatedTalkVersionNotification;
extern NSString * const NCServerCapabilitiesUpdatedNotification;
extern NSString * const NCUserProfileImageUpdatedNotification;

typedef enum NCPreferredFileSorting {
    NCAlphabeticalSorting = 1,
    NCModificationDateSorting
} NCPreferredFileSorting;

typedef enum NCPasscodeType {
    NCPasscodeTypeSimple = 1,
    NCPasscodeTypeStrong
} NCPasscodeType;

@class NCExternalSignalingController;

@interface NCSettingsController : NSObject

@property (nonatomic, copy) NSString *ncServer;
@property (nonatomic, copy) NSString *ncUser;
@property (nonatomic, copy) NSString *ncUserId;
@property (nonatomic, copy) NSString *ncUserDisplayName;
@property (nonatomic, copy) NSString *ncToken;
@property (nonatomic, copy) NSString *ncPushToken;
@property (nonatomic, copy) NSString *ncNormalPushToken;
@property (nonatomic, copy) NSString *ncPushKitToken;
@property (nonatomic, copy) NSString *pushNotificationSubscribed;
@property (nonatomic, copy) NSData *ncPNPublicKey;
@property (nonatomic, copy) NSData *ncPNPrivateKey;
@property (nonatomic, copy) NSString *ncDeviceIdentifier;
@property (nonatomic, copy) NSString *ncDeviceSignature;
@property (nonatomic, copy) NSString *ncUserPublicKey;
@property (nonatomic, copy) NSString *defaultBrowser;
@property (nonatomic, copy) NSMutableArray *supportedBrowsers;
@property (nonatomic, copy) NSString *lockScreenPasscode;
@property (nonatomic, assign) NCPasscodeType lockScreenPasscodeType;
@property (nonatomic, copy) ARDSettingsModel *videoSettingsModel;
@property (nonatomic, copy) NSMutableDictionary *signalingConfigutations; // accountId -> signalingConfigutation
@property (nonatomic, copy) NSMutableDictionary *externalSignalingControllers; // accountId -> externalSignalingController

+ (instancetype)sharedInstance;
- (void)addNewAccountForUser:(NSString *)user withToken:(NSString *)token inServer:(NSString *)server;
- (void)setActiveAccountWithAccountId:(NSString *)accountId;
- (NSString *)tokenForAccountId:(NSString *)accountId;
- (NSData *)pushNotificationPrivateKeyForAccountId:(NSString *)accountId;
- (void)cleanUserAndServerStoredValues;
- (NSString *)pushTokenSHA512;
- (NSString *)combinedPushToken;
- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey;
- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block;
- (void)logoutWithCompletionBlock:(LogoutCompletionBlock)block;
- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block;
- (void)setSignalingConfigurationForAccountId:(NSString *)accountId;
- (NCExternalSignalingController *)externalSignalingControllerForAccountId:(NSString *)accountId;
- (void)subscribeForPushNotificationsForAccountId:(NSString *)accountId;
- (BOOL)serverHasTalkCapability:(NSString *)capability;
- (NSInteger)chatMaxLengthConfigCapability;
- (BOOL)canCreateGroupAndPublicRooms;
- (NCPreferredFileSorting)getPreferredFileSorting;
- (void)setPreferredFileSorting:(NCPreferredFileSorting)sorting;
- (BOOL)isContactSyncEnabled;
- (void)setContactSync:(BOOL)enabled;

@end
