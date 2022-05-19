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

extern NSString * const kUserProfileDisplayName;
extern NSString * const kUserProfileDisplayNameScope;
extern NSString * const kUserProfileEmail;
extern NSString * const kUserProfileEmailScope;
extern NSString * const kUserProfilePhone;
extern NSString * const kUserProfilePhoneScope;
extern NSString * const kUserProfileAddress;
extern NSString * const kUserProfileAddressScope;
extern NSString * const kUserProfileWebsite;
extern NSString * const kUserProfileWebsiteScope;
extern NSString * const kUserProfileTwitter;
extern NSString * const kUserProfileTwitterScope;
extern NSString * const kUserProfileAvatarScope;

extern NSString * const kUserProfileScopePrivate;
extern NSString * const kUserProfileScopeLocal;
extern NSString * const kUserProfileScopeFederated;
extern NSString * const kUserProfileScopePublished;

extern NSInteger const kDefaultChatMaxLength;

typedef void (^UpdatedProfileCompletionBlock)(NSError *error);
typedef void (^LogoutCompletionBlock)(NSError *error);
typedef void (^GetCapabilitiesCompletionBlock)(NSError *error);
typedef void (^GetSignalingConfigCompletionBlock)(NSError *error);

typedef enum NCPreferredFileSorting {
    NCAlphabeticalSorting = 1,
    NCModificationDateSorting
} NCPreferredFileSorting;

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
@property (nonatomic, copy) NSMutableArray *supportedBrowsers;
@property (nonatomic, copy) ARDSettingsModel *videoSettingsModel;
@property (nonatomic, copy) NSMutableDictionary *signalingConfigutations; // accountId -> signalingConfigutation
@property (nonatomic, copy) NSMutableDictionary *externalSignalingControllers; // accountId -> externalSignalingController

+ (instancetype)sharedInstance;
- (void)addNewAccountForUser:(NSString *)user withToken:(NSString *)token inServer:(NSString *)server;
- (void)setActiveAccountWithAccountId:(NSString *)accountId;
- (void)cleanUserAndServerStoredValues;
- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block;
- (void)logoutAccountWithAccountId:(NSString *)accountId withCompletionBlock:(LogoutCompletionBlock)block;
- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block;
- (void)setSignalingConfigurationForAccountId:(NSString *)accountId;
- (NCExternalSignalingController *)externalSignalingControllerForAccountId:(NSString *)accountId;
- (void)subscribeForPushNotificationsForAccountId:(NSString *)accountId;
- (NSInteger)chatMaxLengthConfigCapability;
- (BOOL)canCreateGroupAndPublicRooms;
- (BOOL)callsEnabledCapability;
- (NCPreferredFileSorting)getPreferredFileSorting;
- (void)setPreferredFileSorting:(NCPreferredFileSorting)sorting;
- (BOOL)isContactSyncEnabled;
- (void)setContactSync:(BOOL)enabled;

@end
