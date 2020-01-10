//
//  NCSettingsController.h
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ARDSettingsModel.h"
#import "UICKeyChainStore.h"


extern NSString * const kNCServerKey;
extern NSString * const kNCUserKey;
extern NSString * const kNCUserIdKey;
extern NSString * const kNCUserDisplayNameKey;
extern NSString * const kNCTokenKey;
extern NSString * const kNCPushTokenKey;
extern NSString * const kNCPushKitTokenKey;
extern NSString * const kNCPushSubscribedKey;
extern NSString * const kNCPushServer;
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
extern NSString * const kCapabilityLockedOneToOneRooms;
extern NSString * const kCapabilityWebinaryLobby;
extern NSString * const kCapabilityChatReadMarker;
extern NSString * const kCapabilityStartCallFlag;

extern NSInteger const kDefaultChatMaxLength;
extern NSString * const kMinimumRequiredTalkCapability;

typedef void (^UpdatedProfileCompletionBlock)(NSError *error);
typedef void (^LogoutCompletionBlock)(NSError *error);
typedef void (^GetCapabilitiesCompletionBlock)(NSError *error);
typedef void (^GetSignalingConfigCompletionBlock)(NSError *error);

extern NSString * const NCTalkNotInstalledNotification;
extern NSString * const NCOutdatedTalkVersionNotification;
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
- (void)setToken:(NSString *)token forAccount:(NSString *)account;
- (void)addNewAccountForUser:(NSString *)user withToken:(NSString *)token inServer:(NSString *)server;
- (void)setAccountActive:(NSString *)account;
- (NSString *)tokenForAccount:(NSString *)account;
- (void)setPushNotificationPrivateKey:(NSData *)privateKey forAccount:(NSString *)account;
- (NSData *)pushNotificationPrivateKeyForAccount:(NSString *)account;
- (void)cleanUserAndServerStoredValues;
- (NSString *)pushTokenSHA512;
- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey;
- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block;
- (void)logoutWithCompletionBlock:(LogoutCompletionBlock)block;
- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block;
- (void)setSignalingConfigurationForAccount:(NSString *)accountId;
- (NCExternalSignalingController *)externalSignalingControllerForAccount:(NSString *)accountId;
- (void)subscribeForPushNotificationsForAccount:(NSString *)account;
- (BOOL)serverHasTalkCapability:(NSString *)capability;
- (NSInteger)chatMaxLengthConfigCapability;
- (NCPreferredFileSorting)getPreferredFileSorting;
- (void)setPreferredFileSorting:(NCPreferredFileSorting)sorting;

@end
