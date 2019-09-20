//
//  NCSettingsController.m
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCSettingsController.h"

#import <openssl/rsa.h>
#import <openssl/pem.h>
#import <openssl/bio.h>
#import <openssl/bn.h>
#import <openssl/sha.h>
#import <openssl/err.h>
#import <CommonCrypto/CommonDigest.h>
#import "NCAPIController.h"
#import "NCExternalSignalingController.h"

@interface NCSettingsController ()
{
    UICKeyChainStore *_keychain;
}

@end

@implementation NCSettingsController

NSString * const kNCServerKey           = @"ncServer";
NSString * const kNCUserKey             = @"ncUser";
NSString * const kNCUserIdKey           = @"ncUserId";
NSString * const kNCUserDisplayNameKey  = @"ncUserDisplayName";
NSString * const kNCTokenKey            = @"ncToken";
NSString * const kNCPushTokenKey        = @"ncPushToken";
NSString * const kNCPushKitTokenKey     = @"ncPushKitToken";
NSString * const kNCPushSubscribedKey   = @"ncPushSubscribed";
NSString * const kNCPushServer          = @"https://push-notifications.nextcloud.com";
NSString * const kNCPNPublicKey         = @"ncPNPublicKey";
NSString * const kNCPNPrivateKey        = @"ncPNPrivateKey";
NSString * const kNCDeviceIdentifier    = @"ncDeviceIdentifier";
NSString * const kNCDeviceSignature     = @"ncDeviceSignature";
NSString * const kNCUserPublicKey       = @"ncUserPublicKey";
NSString * const kNCUserDefaultBrowser  = @"ncUserDefaultBrowser";

NSString * const kCapabilityChatV2              = @"chat-v2";
NSString * const kCapabilityFavorites           = @"favorites";
NSString * const kCapabilityLastRoomActivity    = @"last-room-activity";
NSString * const kCapabilityNoPing              = @"no-ping";
NSString * const kCapabilitySystemMessages      = @"system-messages";
NSString * const kCapabilityMentionFlag         = @"mention-flag";
NSString * const kCapabilityNotificationLevels  = @"notification-levels";
NSString * const kCapabilityLockedOneToOneRooms = @"locked-one-to-one-rooms";
NSString * const kCapabilityWebinaryLobby       = @"webinary-lobby";
NSString * const kCapabilityChatReadMarker      = @"chat-read-marker";
NSString * const kCapabilityStartCallFlag       = @"start-call-flag";

NSInteger const kDefaultChatMaxLength           = 1000;

NSString * const kPreferredFileSorting  = @"preferredFileSorting";

NSString * const NCServerCapabilitiesReceivedNotification = @"NCServerCapabilitiesReceivedNotification";

+ (NCSettingsController *)sharedInstance
{
    static dispatch_once_t once;
    static NCSettingsController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _videoSettingsModel = [[ARDSettingsModel alloc] init];
        _keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                   accessGroup:@"group.com.nextcloud.Talk"];
        [self readValuesFromKeyChain];
    }
    return self;
}

#pragma mark - User defaults

- (NCPreferredFileSorting)getPreferredFileSorting
{
    NCPreferredFileSorting sorting = (NCPreferredFileSorting)[[[NSUserDefaults standardUserDefaults] objectForKey:kPreferredFileSorting] integerValue];
    if (!sorting) {
        sorting = NCModificationDateSorting;
        [[NSUserDefaults standardUserDefaults] setObject:@(sorting) forKey:kPreferredFileSorting];
    }
    return sorting;
}

- (void)setPreferredFileSorting:(NCPreferredFileSorting)sorting
{
    [[NSUserDefaults standardUserDefaults] setObject:@(sorting) forKey:kPreferredFileSorting];
}

#pragma mark - KeyChain

- (void)readValuesFromKeyChain
{
    _ncServer = [_keychain stringForKey:kNCServerKey];
    _ncUser = [_keychain stringForKey:kNCUserKey];
    _ncUserId = [_keychain stringForKey:kNCUserIdKey];
    _ncUserDisplayName = [_keychain stringForKey:kNCUserDisplayNameKey];
    _ncToken = [_keychain stringForKey:kNCTokenKey];
    _ncPushToken = [_keychain stringForKey:kNCPushTokenKey];
    _ncPushKitToken = [_keychain stringForKey:kNCPushKitTokenKey];
    _pushNotificationSubscribed = [_keychain stringForKey:kNCPushSubscribedKey];
    _ncPNPublicKey = [_keychain dataForKey:kNCPNPublicKey];
    _ncPNPrivateKey = [_keychain dataForKey:kNCPNPrivateKey];
    _ncDeviceIdentifier = [_keychain stringForKey:kNCDeviceIdentifier];
    _ncDeviceSignature = [_keychain stringForKey:kNCDeviceSignature];
    _ncUserPublicKey = [_keychain stringForKey:kNCUserPublicKey];
    _defaultBrowser = [_keychain stringForKey:kNCUserDefaultBrowser];
}

- (void)cleanUserAndServerStoredValues
{
    _ncServer = nil;
    _ncUser = nil;
    _ncUserDisplayName = nil;
    _ncToken = nil;
    _ncPNPublicKey = nil;
    _ncPNPrivateKey = nil;
    _ncUserPublicKey = nil;
    _ncDeviceIdentifier = nil;
    _ncDeviceSignature = nil;
    _defaultBrowser = @"Safari";
    _pushNotificationSubscribed = nil;
    // Also remove values that are not stored in the keychain
    _ncTalkCapabilities = nil;
    _ncSignalingConfiguration = nil;
    
    [_keychain removeItemForKey:kNCServerKey];
    [_keychain removeItemForKey:kNCUserKey];
    [_keychain removeItemForKey:kNCUserDisplayNameKey];
    [_keychain removeItemForKey:kNCTokenKey];
    [_keychain removeItemForKey:kNCPushSubscribedKey];
    [_keychain removeItemForKey:kNCPNPublicKey];
    [_keychain removeItemForKey:kNCPNPrivateKey];
    [_keychain removeItemForKey:kNCDeviceIdentifier];
    [_keychain removeItemForKey:kNCDeviceSignature];
    [_keychain removeItemForKey:kNCUserPublicKey];
    [_keychain removeItemForKey:kNCUserDefaultBrowser];
    
#warning TODO - Restore NCAPIController in a diferent way
    [[NCAPIController sharedInstance] setAuthHeaderWithUser:NULL andToken:NULL];
}

#pragma mark - User Profile

- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block
{
    [[NCAPIController sharedInstance] getUserProfileWithCompletionBlock:^(NSDictionary *userProfile, NSError *error) {
        if (!error) {
            NSString *userDisplayName = [userProfile objectForKey:@"display-name"];
            _ncUserDisplayName = userDisplayName;
            [_keychain setString:userDisplayName forKey:kNCUserDisplayNameKey];
            NSString *userId = [userProfile objectForKey:@"id"];
            _ncUserId = userId;
            [_keychain setString:userId forKey:kNCUserIdKey];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting the user profile");
            if (block) block(error);
        }
    }];
}

- (void)logoutWithCompletionBlock:(LogoutCompletionBlock)block
{
    if ([[NCSettingsController sharedInstance] ncDeviceIdentifier]) {
        [[NCAPIController sharedInstance] unsubscribeToNextcloudServer:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from NC server!!!");
            } else {
                NSLog(@"Error while unsubscribing from NC server.");
            }
        }];
        [[NCAPIController sharedInstance] unsubscribeToPushServer:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from Push Notification server!!!");
            } else {
                NSLog(@"Error while unsubscribing from Push Notification server.");
            }
        }];
    }
    [[NCExternalSignalingController sharedInstance] disconnect];
    [[NCSettingsController sharedInstance] cleanUserAndServerStoredValues];
    if (block) block(nil);
}


- (void)setDefaultBrowser:(NSString *)defaultBrowser
{
    _defaultBrowser = defaultBrowser;
    [_keychain setString:defaultBrowser forKey:kNCUserDefaultBrowser];
}

#pragma mark - Signaling Configuration

- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block
{
    [[NCAPIController sharedInstance] getSignalingSettingsWithCompletionBlock:^(NSDictionary *settings, NSError *error) {
        if (!error) {
            _ncSignalingConfiguration = [[settings objectForKey:@"ocs"] objectForKey:@"data"];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting signaling configuration");
            if (block) block(error);
        }
    }];
}

// SetSignalingConfiguration should be called just once
- (void)setSignalingConfiguration
{
    NSString *externalSignalingServer = nil;
    id server = [_ncSignalingConfiguration objectForKey:@"server"];
    if ([server isKindOfClass:[NSString class]]) {
        externalSignalingServer = server;
    }
    NSString *externalSignalingTicket = [_ncSignalingConfiguration objectForKey:@"ticket"];
    if (externalSignalingServer && externalSignalingTicket) {
        [[NCExternalSignalingController sharedInstance] setServer:externalSignalingServer andTicket:externalSignalingTicket];
    }
}

#pragma mark - Server Capabilities

- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
{
    [[NCAPIController sharedInstance] getServerCapabilitiesWithCompletionBlock:^(NSDictionary *serverCapabilities, NSError *error) {
        if (!error) {
            NSDictionary *talkCapabilities = [[serverCapabilities objectForKey:@"capabilities"] objectForKey:@"spreed"];
            _ncTalkCapabilities = talkCapabilities ? talkCapabilities : @{};
            [[NSNotificationCenter defaultCenter] postNotificationName:NCServerCapabilitiesReceivedNotification
                                                                object:self
                                                              userInfo:nil];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting server capabilities");
            if (block) block(error);
        }
    }];
}

- (BOOL)serverUsesRequiredTalkVersion
{
    if (_ncTalkCapabilities) {
        NSArray *talkFeatures = [_ncTalkCapabilities objectForKey:@"features"];
        if ([talkFeatures containsObject:kCapabilityChatV2]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)serverHasTalkCapability:(NSString *)capability
{
    if (_ncTalkCapabilities) {
        NSArray *talkFeatures = [_ncTalkCapabilities objectForKey:@"features"];
        if ([talkFeatures containsObject:capability]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)chatMaxLengthConfigCapability
{
    if (_ncTalkCapabilities) {
        NSDictionary *talkConfiguration = [_ncTalkCapabilities objectForKey:@"config"];
        NSInteger chatMaxLength = [[[talkConfiguration objectForKey:@"chat"] objectForKey:@"max-length"] integerValue];
        return chatMaxLength > 0 ? chatMaxLength : kDefaultChatMaxLength;
    }
    return kDefaultChatMaxLength;
}

#pragma mark - Push Notifications

- (void)subscribeForPushNotifications
{
#if !TARGET_IPHONE_SIMULATOR
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                                accessGroup:@"group.com.nextcloud.Talk"];
    
    if ([self generatePushNotificationsKeyPair]) {
        [[NCAPIController sharedInstance] subscribeToNextcloudServer:^(NSDictionary *responseDict, NSError *error) {
            if (!error) {
                NSLog(@"Subscribed to NC server successfully.");
                
                NSString *publicKey = [responseDict objectForKey:@"publicKey"];
                NSString *deviceIdentifier = [responseDict objectForKey:@"deviceIdentifier"];
                NSString *signature = [responseDict objectForKey:@"signature"];
                
                [NCSettingsController sharedInstance].ncUserPublicKey = publicKey;
                [NCSettingsController sharedInstance].ncDeviceIdentifier = deviceIdentifier;
                [NCSettingsController sharedInstance].ncDeviceSignature = signature;
                
                [keychain setString:publicKey forKey:kNCUserPublicKey];
                [keychain setString:deviceIdentifier forKey:kNCDeviceIdentifier];
                [keychain setString:signature forKey:kNCDeviceSignature];
                
                [[NCAPIController sharedInstance] subscribeToPushServer:^(NSError *error) {
                    if (!error) {
                        NSString *subscribedValue = @"subscribed";
                        [NCSettingsController sharedInstance].pushNotificationSubscribed = subscribedValue;
                        [keychain setString:subscribedValue forKey:kNCPushSubscribedKey];
                        NSLog(@"Subscribed to Push Notification server successfully.");
                    } else {
                        NSLog(@"Error while subscribing to Push Notification server.");
                    }
                }];
            } else {
                NSLog(@"Error while subscribing to NC server.");
            }
        }];
    }
#endif
}

- (BOOL)generatePushNotificationsKeyPair
{
    EVP_PKEY *pkey;
    NSError *keyError;
    pkey = [self generateRSAKey:&keyError];
    if (keyError) {
        return NO;
    }
    
    // Extract publicKey, privateKey
    int len;
    char *keyBytes;
    
    // PublicKey
    BIO *publicKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PUBKEY(publicKeyBIO, pkey);
    
    len = BIO_pending(publicKeyBIO);
    keyBytes  = malloc(len);
    
    BIO_read(publicKeyBIO, keyBytes, len);
    _ncPNPublicKey = [NSData dataWithBytes:keyBytes length:len];
    [_keychain setData:_ncPNPublicKey forKey:kNCPNPublicKey];
    NSLog(@"Push Notifications Key Pair generated: \n%@", [[NSString alloc] initWithData:_ncPNPublicKey encoding:NSUTF8StringEncoding]);
    
    // PrivateKey
    BIO *privateKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PKCS8PrivateKey(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL);
    
    len = BIO_pending(privateKeyBIO);
    keyBytes = malloc(len);
    
    BIO_read(privateKeyBIO, keyBytes, len);
    _ncPNPrivateKey = [NSData dataWithBytes:keyBytes length:len];
    [_keychain setData:_ncPNPrivateKey forKey:kNCPNPrivateKey];
    
    EVP_PKEY_free(pkey);
    
    return YES;
}

- (EVP_PKEY *)generateRSAKey:(NSError **)error
{
    EVP_PKEY *pkey = EVP_PKEY_new();
    if (!pkey) {
        return NULL;
    }
    
    BIGNUM *bigNumber = BN_new();
    int exponent = RSA_F4;
    RSA *rsa = RSA_new();
    
    if (BN_set_word(bigNumber, exponent) < 0) {
        goto cleanup;
    }
    
    if (RSA_generate_key_ex(rsa, 2048, bigNumber, NULL) < 0) {
        goto cleanup;
    }
    
    if (!EVP_PKEY_set1_RSA(pkey, rsa)) {
        goto cleanup;
    }
    
cleanup:
    RSA_free(rsa);
    BN_free(bigNumber);
    
    return pkey;
}

- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey
{
    NSString *privateKeyString = [[NSString alloc] initWithData:privateKey encoding:NSUTF8StringEncoding];
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:message options:0];
    char *privKey = (char *)[privateKeyString UTF8String];
    
    // Get Device Private Key from PEM
    BIO *bio = BIO_new(BIO_s_mem());
    BIO_write(bio, privKey, (int)strlen(privKey));
    
    EVP_PKEY* pkey = 0;
    PEM_read_bio_PrivateKey(bio, &pkey, 0, 0);
    
    RSA* rsa = EVP_PKEY_get1_RSA(pkey);
    
    // Decrypt the message
    unsigned char *decrypted = (unsigned char *) malloc(4096);
    
    int decrypted_length = RSA_private_decrypt((int)[decodedData length], [decodedData bytes], decrypted, rsa, RSA_PKCS1_PADDING);
    if(decrypted_length == -1) {
        char buffer[500];
        ERR_error_string(ERR_get_error(), buffer);
        NSLog(@"%@",[NSString stringWithUTF8String:buffer]);
        return nil;
    }
    
    NSString *decryptString = [[NSString alloc] initWithBytes:decrypted length:decrypted_length encoding:NSUTF8StringEncoding];
    
    if (decrypted)
        free(decrypted);
    free(bio);
    free(rsa);
    
    return decryptString;
}

- (NSString *)pushTokenSHA512
{
    return [self createSHA512:_ncPushKitToken];
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
