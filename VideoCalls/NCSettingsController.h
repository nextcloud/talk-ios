//
//  NCSettingsController.h
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "UICKeyChainStore.h"


extern NSString * const kNCServerKey;
extern NSString * const kNCUserKey;
extern NSString * const kNCUserIdKey;
extern NSString * const kNCUserDisplayNameKey;
extern NSString * const kNCTokenKey;
extern NSString * const kNCPushTokenKey;
extern NSString * const kNCPushServer;
extern NSString * const kNCPNPublicKey;
extern NSString * const kNCPNPrivateKey;
extern NSString * const kNCDeviceIdentifier;
extern NSString * const kNCDeviceSignature;
extern NSString * const kNCUserPublicKey;

typedef void (^UpdatedProfileCompletionBlock)(NSError *error);
typedef void (^GetCapabilitiesCompletionBlock)(NSError *error);

extern NSString * const NCServerCapabilitiesReceivedNotification;


@interface NCSettingsController : NSObject

@property (nonatomic, copy) NSString *ncServer;
@property (nonatomic, copy) NSString *ncUser;
@property (nonatomic, copy) NSString *ncUserId;
@property (nonatomic, copy) NSString *ncUserDisplayName;
@property (nonatomic, copy) NSString *ncToken;
@property (nonatomic, copy) NSString *ncPushToken;
@property (nonatomic, copy) NSData *ncPNPublicKey;
@property (nonatomic, copy) NSData *ncPNPrivateKey;
@property (nonatomic, copy) NSString *ncDeviceIdentifier;
@property (nonatomic, copy) NSString *ncDeviceSignature;
@property (nonatomic, copy) NSString *ncUserPublicKey;
@property (nonatomic, copy) NSDictionary *ncTalkCapabilities;

+ (instancetype)sharedInstance;
- (void)cleanUserAndServerStoredValues;
- (BOOL)generatePushNotificationsKeyPair;
- (NSString *)pushTokenSHA512;
- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey;
- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block;
- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;

@end
