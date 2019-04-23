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

extern NSString * const kCapabilityChatV2;
extern NSString * const kCapabilityFavorites;
extern NSString * const kCapabilityLastRoomActivity;
extern NSString * const kCapabilityNoPing;
extern NSString * const kCapabilitySystemMessages;
extern NSString * const kCapabilityMentionFlag;
extern NSString * const kCapabilityNotificationLevels;
extern NSString * const kCapabilityLockedOneToOneRooms;

typedef void (^UpdatedProfileCompletionBlock)(NSError *error);
typedef void (^LogoutCompletionBlock)(NSError *error);
typedef void (^GetCapabilitiesCompletionBlock)(NSError *error);
typedef void (^GetSignalingConfigCompletionBlock)(NSError *error);

extern NSString * const NCServerCapabilitiesReceivedNotification;

typedef enum NCPreferredFileSorting {
    NCAlphabeticalSorting = 1,
    NCModificationDateSorting
} NCPreferredFileSorting;


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
@property (nonatomic, copy) NSDictionary *ncTalkCapabilities;
@property (nonatomic, copy) NSString *defaultBrowser;
@property (nonatomic, copy) NSMutableArray *supportedBrowsers;
@property (nonatomic, copy) NSDictionary *ncSignalingConfiguration;
@property (nonatomic, copy) ARDSettingsModel *videoSettingsModel;

+ (instancetype)sharedInstance;
- (void)cleanUserAndServerStoredValues;
- (BOOL)generatePushNotificationsKeyPair;
- (NSString *)pushTokenSHA512;
- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey;
- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block;
- (void)logoutWithCompletionBlock:(LogoutCompletionBlock)block;
- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block;
- (void)setSignalingConfiguration;
- (void)subscribeForPushNotifications;
- (BOOL)serverUsesRequiredTalkVersion;
- (BOOL)serverHasTalkCapability:(NSString *)capability;
- (NCPreferredFileSorting)getPreferredFileSorting;
- (void)setPreferredFileSorting:(NCPreferredFileSorting)sorting;

@end
