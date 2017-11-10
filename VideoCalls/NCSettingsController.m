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

#import "NCAPIController.h"

@implementation NCSettingsController

NSString * const kNCServerKey           = @"ncServer";
NSString * const kNCUserKey             = @"ncUser";
NSString * const kNCUserDisplayNameKey  = @"ncUserDisplayName";
NSString * const kNCTokenKey            = @"ncToken";
NSString * const kNCPushTokenKey        = @"ncPushToken";
NSString * const kNCPNPublicKey         = @"ncPNPublicKey";
NSString * const kNCPNPrivateKey        = @"ncPNPrivateKey";

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
        [self readValuesFromKeyChain];
    }
    return self;
}

- (void)readValuesFromKeyChain
{
    _ncServer = [UICKeyChainStore stringForKey:kNCServerKey];
    _ncUser = [UICKeyChainStore stringForKey:kNCUserKey];
    _ncUserDisplayName = [UICKeyChainStore stringForKey:kNCUserDisplayNameKey];
    _ncToken = [UICKeyChainStore stringForKey:kNCTokenKey];
    _ncPushToken = [UICKeyChainStore stringForKey:kNCPushTokenKey];
    _ncPNPublicKey = [UICKeyChainStore dataForKey:kNCPNPublicKey];
    _ncPNPrivateKey = [UICKeyChainStore dataForKey:kNCPNPrivateKey];
    
    if (!_ncPNPublicKey) {
        [self generatePushNotificationsKeyPair];
    }
}

- (void)cleanAllStoredValues
{
    _ncServer = nil;
    _ncUser = nil;
    _ncUserDisplayName = nil;
    _ncToken = nil;
    _ncPushToken = nil;
    _ncPNPublicKey = nil;
    _ncPNPrivateKey = nil;
    
    [UICKeyChainStore removeAllItems];
    
#warning TODO - Restore NCAPIController in a diferent way
    [[NCAPIController sharedInstance] setAuthHeaderWithUser:NULL andToken:NULL];
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
    [UICKeyChainStore setData:_ncPNPublicKey forKey:kNCPNPublicKey];
    NSLog(@"Push Notifications Key Pair generated: \n%@", [[NSString alloc] initWithData:_ncPNPublicKey encoding:NSUTF8StringEncoding]);
    
    // PrivateKey
    BIO *privateKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PKCS8PrivateKey(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL);
    
    len = BIO_pending(privateKeyBIO);
    keyBytes = malloc(len);
    
    BIO_read(privateKeyBIO, keyBytes, len);
    _ncPNPrivateKey = [NSData dataWithBytes:keyBytes length:len];
    [UICKeyChainStore setData:_ncPNPrivateKey forKey:kNCPNPrivateKey];
    
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

@end
