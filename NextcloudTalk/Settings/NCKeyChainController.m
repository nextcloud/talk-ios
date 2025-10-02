/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCKeyChainController.h"

#import <CommonCrypto/CommonDigest.h>

#import "NCAppBranding.h"
#import "NextcloudTalk-Swift.h"

@import UICKeyChainStore;

@implementation NCKeyChainController

NSString * const kNCTokenKey                    = @"ncToken";
NSString * const kNCNormalPushTokenKey          = @"ncNormalPushToken";
NSString * const kNCPushKitTokenKey             = @"ncPushKitToken";
NSString * const kNCPNPublicKey                 = @"ncPNPublicKey";
NSString * const kNCPNPrivateKey                = @"ncPNPrivateKey";

+ (NCKeyChainController *)sharedInstance
{
    static dispatch_once_t once;
    static NCKeyChainController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _keychain = [UICKeyChainStore keyChainStoreWithService:bundleIdentifier accessGroup:groupIdentifier];
    }
    return self;
}

- (void)setToken:(NSString *)token forAccountId:(NSString *)accountId
{
    [_keychain setString:token forKey:[NSString stringWithFormat:@"%@-%@", kNCTokenKey, accountId]];
}

- (NSString *)tokenForAccountId:(NSString *)accountId
{
    return [_keychain stringForKey:[NSString stringWithFormat:@"%@-%@", kNCTokenKey, accountId]];
}

- (void)setPushNotificationPublicKey:(NSData *)privateKey forAccountId:(NSString *)accountId
{
    [_keychain setData:privateKey forKey:[NSString stringWithFormat:@"%@-%@", kNCPNPublicKey, accountId]];
}

- (NSData *)pushNotificationPublicKeyForAccountId:(NSString *)accountId
{
    return [_keychain dataForKey:[NSString stringWithFormat:@"%@-%@", kNCPNPublicKey, accountId]];
}

- (void)setPushNotificationPrivateKey:(NSData *)privateKey forAccountId:(NSString *)accountId
{
    [_keychain setData:privateKey forKey:[NSString stringWithFormat:@"%@-%@", kNCPNPrivateKey, accountId]];
}

- (NSData *)pushNotificationPrivateKeyForAccountId:(NSString *)accountId
{
    return [_keychain dataForKey:[NSString stringWithFormat:@"%@-%@", kNCPNPrivateKey, accountId]];
}

- (NSString *)pushTokenSHA512
{
    NSString *token = [self combinedPushToken];

    if (!token) {
        return nil;
    }

    return [self createSHA512:token];
}

- (void)logCombinedPushToken
{
    NSString *normalPushToken = [_keychain stringForKey:kNCNormalPushTokenKey];
    NSString *pushKitToken = [_keychain stringForKey:kNCPushKitTokenKey];

    if (normalPushToken && [normalPushToken length] >= 10) {
        [NCUtils log:[NSString stringWithFormat:@"Push notification, normal push token: %@... length %ld", [normalPushToken substringToIndex:10], [normalPushToken length]]];
    } else {
        [NCUtils log:@"Push notification, normal push token length < 10"];
    }

    if (pushKitToken && [pushKitToken length] >= 10) {
        [NCUtils log:[NSString stringWithFormat:@"Push notification, pushKit token: %@... length %ld", [pushKitToken substringToIndex:10], [pushKitToken length]]];
    } else {
        [NCUtils log:@"Push notification, pushKit token length < 10"];
    }
}

- (NSString *)combinedPushToken
{
    NSString *normalPushToken = [_keychain stringForKey:kNCNormalPushTokenKey];
    NSString *pushKitToken = [_keychain stringForKey:kNCPushKitTokenKey];

    if (!normalPushToken || !pushKitToken) {
        return nil;
    }

    if ([NCUtils isiOSAppOnMac]) {
        // As CallKit is not supported on MacOS, we only supply the
        // normal push token, to generate local notifications for calls
        return normalPushToken;
    }

    return [NSString stringWithFormat:@"%@ %@", normalPushToken, pushKitToken];
}

- (void)removeAllItems
{
    [UICKeyChainStore removeAllItemsForService:bundleIdentifier accessGroup:groupIdentifier];
}

#pragma mark - Utils

- (NSString *)createSHA512:(NSString *)string
{
    const char *cstr = [string cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSData dataWithBytes:cstr length:string.length];
    uint8_t digest[CC_SHA512_DIGEST_LENGTH];
    CC_SHA512(data.bytes, (unsigned int)data.length, digest);
    NSMutableString* output = [NSMutableString  stringWithCapacity:CC_SHA512_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_SHA512_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return output;
}

@end
