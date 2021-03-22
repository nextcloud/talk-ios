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

#import "NCSettingsController.h"

#import <openssl/rsa.h>
#import <openssl/pem.h>
#import <openssl/bio.h>
#import <openssl/bn.h>
#import <openssl/sha.h>
#import <openssl/err.h>
#import <CommonCrypto/CommonDigest.h>
#import "OpenInFirefoxControllerObjC.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCExternalSignalingController.h"
#import "NCUserInterfaceController.h"
#import "JDStatusBarNotification.h"
#import "NCChatFileController.h"

@interface NCSettingsController ()
{
    UICKeyChainStore *_keychain;
    NSString *_defaultBrowser;
    NSString *_lockScreenPasscode;
    NCPasscodeType _lockScreenPasscodeType;
}

@end

@implementation NCSettingsController

NSString * const kNCServerKey                   = @"ncServer";
NSString * const kNCUserKey                     = @"ncUser";
NSString * const kNCUserIdKey                   = @"ncUserId";
NSString * const kNCUserDisplayNameKey          = @"ncUserDisplayName";
NSString * const kNCTokenKey                    = @"ncToken";
NSString * const kNCPushTokenKey                = @"ncPushToken";
NSString * const kNCNormalPushTokenKey          = @"ncNormalPushToken";
NSString * const kNCPushKitTokenKey             = @"ncPushKitToken";
NSString * const kNCPushSubscribedKey           = @"ncPushSubscribed";
NSString * const kNCPNPublicKey                 = @"ncPNPublicKey";
NSString * const kNCPNPrivateKey                = @"ncPNPrivateKey";
NSString * const kNCDeviceIdentifier            = @"ncDeviceIdentifier";
NSString * const kNCDeviceSignature             = @"ncDeviceSignature";
NSString * const kNCUserPublicKey               = @"ncUserPublicKey";
NSString * const kNCUserDefaultBrowser          = @"ncUserDefaultBrowser";
NSString * const kNCLockScreenPasscode          = @"ncLockScreenPasscode";
NSString * const kNCLockScreenPasscodeType      = @"ncLockScreenPasscodeType";

NSString * const kCapabilitySystemMessages          = @"system-messages";
NSString * const kCapabilityNotificationLevels      = @"notification-levels";
NSString * const kCapabilityInviteGroupsAndMails    = @"invite-groups-and-mails";
NSString * const kCapabilityLockedOneToOneRooms     = @"locked-one-to-one-rooms";
NSString * const kCapabilityWebinaryLobby           = @"webinary-lobby";
NSString * const kCapabilityChatReadMarker          = @"chat-read-marker";
NSString * const kCapabilityStartCallFlag           = @"start-call-flag";
NSString * const kCapabilityCirclesSupport          = @"circles-support";
NSString * const kCapabilityChatReferenceId         = @"chat-reference-id";
NSString * const kCapabilityPhonebookSearch         = @"phonebook-search";
NSString * const kCapabilityChatReadStatus          = @"chat-read-status";
NSString * const kCapabilityDeleteMessages          = @"delete-messages";
NSString * const kCapabilityCallFlags               = @"conversation-call-flags";
NSString * const kCapabilityTempUserAvatarAPI       = @"temp-user-avatar-api";

NSString * const kUserProfileUserId         = @"id";
NSString * const kUserProfileDisplayName    = @"displayname";
NSString * const kUserProfileEmail          = @"email";
NSString * const kUserProfilePhone          = @"phone";
NSString * const kUserProfileAddress        = @"address";
NSString * const kUserProfileWebsite        = @"website";
NSString * const kUserProfileTwitter        = @"twitter";

NSInteger const kDefaultChatMaxLength           = 1000;
NSString * const kMinimumRequiredTalkCapability = kCapabilitySystemMessages; // Talk 4.0 is the minimum required version

NSString * const kPreferredFileSorting  = @"preferredFileSorting";
NSString * const kContactSyncEnabled  = @"contactSyncEnabled";

NSString * const NCTalkNotInstalledNotification = @"NCTalkNotInstalledNotification";
NSString * const NCOutdatedTalkVersionNotification = @"NCOutdatedTalkVersionNotification";
NSString * const NCServerCapabilitiesUpdatedNotification = @"NCServerCapabilitiesUpdatedNotification";
NSString * const NCUserProfileImageUpdatedNotification = @"NCUserProfileImageUpdatedNotification";

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
        _keychain = [UICKeyChainStore keyChainStoreWithService:bundleIdentifier accessGroup:groupIdentifier];
        _signalingConfigutations = [NSMutableDictionary new];
        _externalSignalingControllers = [NSMutableDictionary new];
        
        [self readValuesFromKeyChain];
        [self configureDatabase];
        [self checkStoredDataInKechain];
        [self configureAppSettings];
    }
    return self;
}

#pragma mark - Database

- (void)configureDatabase
{
    // Init database
    [NCDatabaseManager sharedInstance];
    
    // Check possible account migration to database
    if (_ncUser && _ncServer) {
        NSLog(@"Migrating user to the database");
        TalkAccount *account =  [[TalkAccount alloc] init];
        account.accountId = [NSString stringWithFormat:@"%@@%@", _ncUser, _ncServer];
        account.server = _ncServer;
        account.user = _ncUser;
        account.pushNotificationSubscribed = _pushNotificationSubscribed;
        account.pushNotificationPublicKey = _ncPNPublicKey;
        account.pushNotificationPublicKey = _ncPNPublicKey;
        account.deviceIdentifier = _ncDeviceIdentifier;
        account.deviceSignature = _ncDeviceSignature;
        account.userPublicKey = _ncUserPublicKey;
        account.active = YES;
        
        [self setToken:_ncToken forAccountId:account.accountId];
        [self setPushNotificationPrivateKey:_ncPNPrivateKey forAccountId:account.accountId];
        
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm transactionWithBlock:^{
            [realm addObject:account];
        }];
        
        [self cleanUserAndServerStoredValues];
    }
}

- (void)checkStoredDataInKechain
{
    // Removed data stored in the Keychain if there are no accounts configured
    // This step should be always done before the possible account migration
    if ([[NCDatabaseManager sharedInstance] numberOfAccounts] == 0) {
        NSLog(@"Removing all data stored in Keychain");
        [self cleanUserAndServerStoredValues];
        [UICKeyChainStore removeAllItemsForService:bundleIdentifier accessGroup:groupIdentifier];
    }
}

#pragma mark - User accounts

- (void)addNewAccountForUser:(NSString *)user withToken:(NSString *)token inServer:(NSString *)server
{
    NSString *accountId = [[NCDatabaseManager sharedInstance] accountIdForUser:user inServer:server];
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
    if (!account) {
        [[NCDatabaseManager sharedInstance] createAccountForUser:user inServer:server];
        [[NCDatabaseManager sharedInstance] setActiveAccountWithAccountId:accountId];
        [self setToken:token forAccountId:accountId];
        TalkAccount *talkAccount = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
        [[NCAPIController sharedInstance] createAPISessionManagerForAccount:talkAccount];
        [self subscribeForPushNotificationsForAccountId:accountId];
    } else {
        [self setActiveAccountWithAccountId:accountId];
        [JDStatusBarNotification showWithStatus:@"Account already added" dismissAfter:4.0f styleName:JDStatusBarStyleSuccess];
    }
}

- (void)setActiveAccountWithAccountId:(NSString *)accountId
{
    [[NCUserInterfaceController sharedInstance] presentConversationsList];
    [[NCDatabaseManager sharedInstance] setActiveAccountWithAccountId:accountId];
    [[NCDatabaseManager sharedInstance] resetUnreadBadgeNumberForAccountId:accountId];
    [[NCNotificationController sharedInstance] removeAllNotificationsForAccountId:accountId];
    [[NCConnectionController sharedInstance] checkAppState];
}

- (void)setToken:(NSString *)token forAccountId:(NSString *)accountId
{
    [_keychain setString:token forKey:[NSString stringWithFormat:@"%@-%@", kNCTokenKey, accountId]];
}

- (NSString *)tokenForAccountId:(NSString *)accountId
{
    return [_keychain stringForKey:[NSString stringWithFormat:@"%@-%@", kNCTokenKey, accountId]];
}

- (void)setPushNotificationPrivateKey:(NSData *)privateKey forAccountId:(NSString *)accountId
{
    [_keychain setData:privateKey forKey:[NSString stringWithFormat:@"%@-%@", kNCPNPrivateKey, accountId]];
}

- (NSData *)pushNotificationPrivateKeyForAccountId:(NSString *)accountId
{
    return [_keychain dataForKey:[NSString stringWithFormat:@"%@-%@", kNCPNPrivateKey, accountId]];
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

- (BOOL)isContactSyncEnabled
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kContactSyncEnabled] boolValue];
}

- (void)setContactSync:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setObject:@(enabled) forKey:kContactSyncEnabled];
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
    _ncNormalPushToken = [_keychain stringForKey:kNCNormalPushTokenKey];
    _ncPushKitToken = [_keychain stringForKey:kNCPushKitTokenKey];
    _pushNotificationSubscribed = [_keychain stringForKey:kNCPushSubscribedKey];
    _ncPNPublicKey = [_keychain dataForKey:kNCPNPublicKey];
    _ncPNPrivateKey = [_keychain dataForKey:kNCPNPrivateKey];
    _ncDeviceIdentifier = [_keychain stringForKey:kNCDeviceIdentifier];
    _ncDeviceSignature = [_keychain stringForKey:kNCDeviceSignature];
    _ncUserPublicKey = [_keychain stringForKey:kNCUserPublicKey];
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
    _pushNotificationSubscribed = nil;
    
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
}

#pragma mark - User Profile

- (void)getUserProfileWithCompletionBlock:(UpdatedProfileCompletionBlock)block
{
    [[NCAPIController sharedInstance] getUserProfileForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *userProfile, NSError *error) {
        if (!error) {
            NSString *userDisplayName = [userProfile objectForKey:kUserProfileDisplayName];
            NSString *userId = [userProfile objectForKey:kUserProfileUserId];
            NSString *phone = [userProfile objectForKey:kUserProfilePhone];
            id emailObject = [userProfile objectForKey:kUserProfileEmail];
            NSString *email = emailObject;
            if (!emailObject || [emailObject isEqual:[NSNull null]]) {
                email = @"";
            }
            NSString *address = [userProfile objectForKey:kUserProfileAddress];
            NSString *website = [userProfile objectForKey:kUserProfileWebsite];
            NSString *twitter = [userProfile objectForKey:kUserProfileTwitter];
            RLMRealm *realm = [RLMRealm defaultRealm];
            TalkAccount *managedActiveAccount = [TalkAccount objectsWhere:(@"active = true")].firstObject;
            [realm beginWriteTransaction];
            managedActiveAccount.userDisplayName = userDisplayName;
            managedActiveAccount.userId = userId;
            managedActiveAccount.phone = phone;
            managedActiveAccount.email = email;
            managedActiveAccount.address = address;
            managedActiveAccount.website = website;
            managedActiveAccount.twitter = twitter;
            [realm commitWriteTransaction];
            [[NCAPIController sharedInstance] saveProfileImageForAccount:[[NCDatabaseManager sharedInstance] activeAccount]];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting the user profile");
            if (block) block(error);
        }
    }];
}

- (void)logoutWithCompletionBlock:(LogoutCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    // Make a copy of the active TalkAccount so it can be deleted/invalidated while removing account info.
    TalkAccount *removingAccount = [[TalkAccount alloc] initWithValue:activeAccount];
    if (removingAccount.deviceIdentifier) {
        [[NCAPIController sharedInstance] unsubscribeAccount:removingAccount fromNextcloudServerWithCompletionBlock:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from NC server!!!");
            } else {
                NSLog(@"Error while unsubscribing from NC server.");
            }
        }];
        [[NCAPIController sharedInstance] unsubscribeAccount:removingAccount fromPushServerWithCompletionBlock:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from Push Notification server!!!");
            } else {
                NSLog(@"Error while unsubscribing from Push Notification server.");
            }
        }];
    }
    NCExternalSignalingController *extSignalingController = [self externalSignalingControllerForAccountId:removingAccount.accountId];
    [extSignalingController disconnect];
    [[NCSettingsController sharedInstance] cleanUserAndServerStoredValues];
    [[NCAPIController sharedInstance] removeProfileImageForAccount:removingAccount];
    [[NCDatabaseManager sharedInstance] removeAccountWithAccountId:removingAccount.accountId];
    [[[NCChatFileController alloc] init] deleteDownloadDirectoryForAccount:removingAccount];
    
    // Activate any of the inactive accounts
    NSArray *inactiveAccounts = [[NCDatabaseManager sharedInstance] inactiveAccounts];
    if (inactiveAccounts.count > 0) {
        TalkAccount *inactiveAccount = [inactiveAccounts objectAtIndex:0];
        [self setActiveAccountWithAccountId:inactiveAccount.accountId];
    }
    
    if (block) block(nil);
}

#pragma mark - App settings

- (void)configureAppSettings
{
    [self configureDefaultBrowser];
    [self configureLockScreen];
}

#pragma mark - Default browser

- (void)configureDefaultBrowser
{
    // Check supported browsers
    NSMutableArray *supportedBrowsers = [[NSMutableArray alloc] initWithObjects:@"Safari", nil];
    if ([[OpenInFirefoxControllerObjC sharedInstance] isFirefoxInstalled]) {
        [supportedBrowsers addObject:@"Firefox"];
    }
    _supportedBrowsers = supportedBrowsers;
    // Check if default browser is valid
    if (![supportedBrowsers containsObject:self.defaultBrowser]) {
        self.defaultBrowser = @"Safari";
    }
}

- (void)setDefaultBrowser:(NSString *)defaultBrowser
{
    _defaultBrowser = defaultBrowser;
    [[NSUserDefaults standardUserDefaults] setObject:defaultBrowser forKey:kNCUserDefaultBrowser];
}

- (NSString *)defaultBrowser
{
    NSString *browser = [[NSUserDefaults standardUserDefaults] objectForKey:kNCUserDefaultBrowser];
    if (!browser) {
        browser = @"Safari";
        // Legacy
        NSString *oldDefaultBrowser = [_keychain stringForKey:kNCUserDefaultBrowser];
        if (oldDefaultBrowser) {
            browser = oldDefaultBrowser;
        }
        [[NSUserDefaults standardUserDefaults] setObject:browser forKey:kNCUserDefaultBrowser];
    }
    return browser;
}

#pragma mark - Lock screen

- (void)configureLockScreen
{
    _lockScreenPasscode = [_keychain stringForKey:kNCLockScreenPasscode];
}

- (void)setLockScreenPasscode:(NSString *)lockScreenPasscode
{
    _lockScreenPasscode = lockScreenPasscode;
    [_keychain setString:lockScreenPasscode forKey:kNCLockScreenPasscode];
}

- (NCPasscodeType)lockScreenPasscodeType
{
    NCPasscodeType passcodeType = (NCPasscodeType)[[[NSUserDefaults standardUserDefaults] objectForKey:kNCLockScreenPasscodeType] integerValue];
    if (!passcodeType) {
        passcodeType = NCPasscodeTypeSimple;
        [[NSUserDefaults standardUserDefaults] setObject:@(passcodeType) forKey:kNCLockScreenPasscodeType];
    }
    return passcodeType;
}

- (void)setLockScreenPasscodeType:(NCPasscodeType)lockScreenPasscodeType
{
    _lockScreenPasscodeType = lockScreenPasscodeType;
    [[NSUserDefaults standardUserDefaults] setObject:@(lockScreenPasscodeType) forKey:kNCLockScreenPasscodeType];
}

#pragma mark - Signaling Configuration

- (void)getSignalingConfigurationWithCompletionBlock:(GetSignalingConfigCompletionBlock)block
{
    [[NCAPIController sharedInstance] getSignalingSettingsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *settings, NSError *error) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        if (!error) {
            NSDictionary *signalingConfiguration = [[settings objectForKey:@"ocs"] objectForKey:@"data"];
            [self->_signalingConfigutations setObject:signalingConfiguration forKey:activeAccount.accountId];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting signaling configuration");
            if (block) block(error);
        }
    }];
}

// SetSignalingConfiguration should be called just once
- (void)setSignalingConfigurationForAccountId:(NSString *)accountId
{
    NSDictionary *signalingConfiguration = [_signalingConfigutations objectForKey:accountId];
    NSString *externalSignalingServer = nil;
    id server = [signalingConfiguration objectForKey:@"server"];
    if ([server isKindOfClass:[NSString class]] && ![server isEqualToString:@""]) {
        externalSignalingServer = server;
    }
    NSString *externalSignalingTicket = [signalingConfiguration objectForKey:@"ticket"];
    if (externalSignalingServer && externalSignalingTicket) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NCExternalSignalingController *extSignalingController = [self->_externalSignalingControllers objectForKey:accountId];
            if (!extSignalingController) {
                TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
                extSignalingController = [[NCExternalSignalingController alloc] initWithAccount:account server:externalSignalingServer andTicket:externalSignalingTicket];
                [self->_externalSignalingControllers setObject:extSignalingController forKey:accountId];
            }
        });
    }
}

- (NCExternalSignalingController *)externalSignalingControllerForAccountId:(NSString *)accountId
{
    return [_externalSignalingControllers objectForKey:accountId];
}

#pragma mark - Server Capabilities

- (void)getCapabilitiesWithCompletionBlock:(GetCapabilitiesCompletionBlock)block;
{
    [[NCAPIController sharedInstance] getServerCapabilitiesForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *serverCapabilities, NSError *error) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        if (!error && [serverCapabilities isKindOfClass:[NSDictionary class]]) {
            [[NCDatabaseManager sharedInstance] setServerCapabilities:serverCapabilities forAccountId:activeAccount.accountId];
            [self checkServerCapabilities];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCServerCapabilitiesUpdatedNotification
                                                                object:self
                                                              userInfo:nil];
            if (block) block(nil);
        } else {
            NSLog(@"Error while getting server capabilities");
            if (block) block(error);
        }
    }];
}

- (void)checkServerCapabilities
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        NSArray *talkFeatures = [serverCapabilities.talkCapabilities valueForKey:@"self"];
        if (!talkFeatures) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCTalkNotInstalledNotification
                                                                object:self
                                                              userInfo:nil];
        }
        if (![talkFeatures containsObject:kMinimumRequiredTalkCapability]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCOutdatedTalkVersionNotification
                                                                object:self
                                                              userInfo:nil];
        }
    }
}

- (BOOL)serverHasTalkCapability:(NSString *)capability
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    return [self serverHasTalkCapability:capability forAccountId:activeAccount.accountId];
}

- (BOOL)serverHasTalkCapability:(NSString *)capability forAccountId:(NSString *)accountId
{
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:accountId];
    if (serverCapabilities) {
        NSArray *talkFeatures = [serverCapabilities.talkCapabilities valueForKey:@"self"];
        if ([talkFeatures containsObject:capability]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)chatMaxLengthConfigCapability
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        NSInteger chatMaxLength = serverCapabilities.chatMaxLength;
        return chatMaxLength > 0 ? chatMaxLength : kDefaultChatMaxLength;
    }
    return kDefaultChatMaxLength;
}

- (BOOL)canCreateGroupAndPublicRooms
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        return serverCapabilities.canCreate;
    }
    return YES;
}

#pragma mark - Push Notifications

- (void)subscribeForPushNotificationsForAccountId:(NSString *)accountId
{
#if !TARGET_IPHONE_SIMULATOR
    if ([self generatePushNotificationsKeyPairForAccountId:accountId]) {
        [[NCAPIController sharedInstance] subscribeAccount:[[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId] toNextcloudServerWithCompletionBlock:^(NSDictionary *responseDict, NSError *error) {
            if (!error) {
                NSLog(@"Subscribed to NC server successfully.");
                
                NSString *publicKey = [responseDict objectForKey:@"publicKey"];
                NSString *deviceIdentifier = [responseDict objectForKey:@"deviceIdentifier"];
                NSString *signature = [responseDict objectForKey:@"signature"];
                
                RLMRealm *realm = [RLMRealm defaultRealm];
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
                TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
                [realm beginWriteTransaction];
                managedAccount.userPublicKey = publicKey;
                managedAccount.deviceIdentifier = deviceIdentifier;
                managedAccount.deviceSignature = signature;
                [realm commitWriteTransaction];
                
                [[NCAPIController sharedInstance] subscribeAccount:[[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId] toPushServerWithCompletionBlock:^(NSError *error) {
                    if (!error) {
                        RLMRealm *realm = [RLMRealm defaultRealm];
                        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
                        TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
                        [realm beginWriteTransaction];
                        managedAccount.pushNotificationSubscribed = YES;
                        [realm commitWriteTransaction];
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

- (BOOL)generatePushNotificationsKeyPairForAccountId:(NSString *)accountId
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
    NSData *pnPublicKey = [NSData dataWithBytes:keyBytes length:len];
    RLMRealm *realm = [RLMRealm defaultRealm];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    [realm beginWriteTransaction];
    managedAccount.pushNotificationPublicKey = pnPublicKey;
    [realm commitWriteTransaction];
    NSLog(@"Push Notifications Key Pair generated: \n%@", [[NSString alloc] initWithData:pnPublicKey encoding:NSUTF8StringEncoding]);
    
    // PrivateKey
    BIO *privateKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PKCS8PrivateKey(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL);
    
    len = BIO_pending(privateKeyBIO);
    keyBytes = malloc(len);
    
    BIO_read(privateKeyBIO, keyBytes, len);
    NSData *pnPrivateKey = [NSData dataWithBytes:keyBytes length:len];
    [self setPushNotificationPrivateKey:pnPrivateKey forAccountId:accountId];
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
    return [self createSHA512:[self combinedPushToken]];
}

- (NSString *)combinedPushToken
{
    return [NSString stringWithFormat:@"%@ %@", self.ncNormalPushToken, self.ncPushKitToken];
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
