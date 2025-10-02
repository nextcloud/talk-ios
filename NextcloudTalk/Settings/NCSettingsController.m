/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCSettingsController.h"

@import NextcloudKit;

#import <openssl/rsa.h>
#import <openssl/pem.h>
#import <openssl/bio.h>
#import <openssl/bn.h>
#import <openssl/sha.h>
#import <openssl/err.h>

#import "JDStatusBarNotification.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCExternalSignalingController.h"
#import "NCKeyChainController.h"
#import "NCRoomsManager.h"
#import "NCUserInterfaceController.h"
#import "NCUserDefaults.h"
#import "NCChatFileController.h"
#import "NotificationCenterNotifications.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCSettingsControllerDidChangeActiveAccountNotification = @"NCSettingsControllerDidChangeActiveAccountNotification";

@interface NCPushNotificationKeyPair : NSObject

@property (nonatomic, copy) NSData *publicKey;
@property (nonatomic, copy) NSData *privateKey;

@end

@implementation NCPushNotificationKeyPair

@end


@implementation NCSettingsController

NSString * const kUserProfileUserId             = @"id";
NSString * const kUserProfileDisplayName        = @"displayname";
NSString * const kUserProfileDisplayNameScope   = @"displaynameScope";
NSString * const kUserProfileEmail              = @"email";
NSString * const kUserProfileEmailScope         = @"emailScope";
NSString * const kUserProfilePhone              = @"phone";
NSString * const kUserProfilePhoneScope         = @"phoneScope";
NSString * const kUserProfileAddress            = @"address";
NSString * const kUserProfileAddressScope       = @"addressScope";
NSString * const kUserProfileWebsite            = @"website";
NSString * const kUserProfileWebsiteScope       = @"websiteScope";
NSString * const kUserProfileTwitter            = @"twitter";
NSString * const kUserProfileTwitterScope       = @"twitterScope";
NSString * const kUserProfileAvatarScope        = @"avatarScope";

NSString * const kUserProfileScopePrivate       = @"v2-private";
NSString * const kUserProfileScopeLocal         = @"v2-local";
NSString * const kUserProfileScopeFederated     = @"v2-federated";
NSString * const kUserProfileScopePublished     = @"v2-published";

NSString * const kPreferredFileSorting          = @"preferredFileSorting";
NSString * const kContactSyncEnabled            = @"contactSyncEnabled";

NSString * const kDidReceiveCallsFromOldAccount = @"receivedCallsFromOldAccount";

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
        _signalingConfigurations = [NSMutableDictionary new];
        _externalSignalingControllers = [NSMutableDictionary new];

        [self configureDatabase];
        [self checkStoredDataInKechain];
        [self resetPerAppLaunchSettings];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tokenRevokedResponseReceived:) name:NCTokenRevokedResponseReceivedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(upgradeRequiredResponseReceived:) name:NCUpgradeRequiredResponseReceivedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(talkConfigurationHasChanged:) name:NCTalkConfigurationHashChangedNotification object:nil];
    }
    return self;
}

#pragma mark - Database

- (void)configureDatabase
{
    // Init database
    [NCDatabaseManager sharedInstance];
}

- (void)checkStoredDataInKechain
{
    // Removed data stored in the Keychain if there are no accounts configured
    // This step should be always done before the possible account migration
    if ([[NCDatabaseManager sharedInstance] numberOfAccounts] == 0) {
        NSLog(@"Removing all data stored in Keychain");
        [[NCKeyChainController sharedInstance] removeAllItems];
    }
}

- (void)resetPerAppLaunchSettings
{
    // Reset "threadsLastCheckTimestamp" on every app fresh launch
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    for (TalkAccount *account in [TalkAccount allObjects]) {
        account.threadsLastCheckTimestamp = 0;
    }
    [realm commitWriteTransaction];
}

#pragma mark - User accounts

- (void)addNewAccountForUser:(NSString *)user withToken:(NSString *)token inServer:(NSString *)server
{
    NSString *accountId = [[NCDatabaseManager sharedInstance] accountIdForUser:user inServer:server];
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
    if (!account) {
        [[NCDatabaseManager sharedInstance] createAccountForUser:user inServer:server];
        [[NCDatabaseManager sharedInstance] setActiveAccountWithAccountId:accountId];
        [[NCKeyChainController sharedInstance] setToken:token forAccountId:accountId];
        TalkAccount *talkAccount = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
        [[NCAPIController sharedInstance] createAPISessionManagerForAccount:talkAccount];
        [self subscribeForPushNotificationsForAccountId:accountId withCompletionBlock:nil];
        [self createAccountsFile];
    } else {
        [self setActiveAccountWithAccountId:accountId];
        [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Account already added", nil) dismissAfterDelay:4.0f includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
    }
}

- (void)setActiveAccountWithAccountId:(NSString *)accountId
{
    [[NCUserInterfaceController sharedInstance] presentConversationsList];
    [[NCDatabaseManager sharedInstance] setActiveAccountWithAccountId:accountId];
    [[NCDatabaseManager sharedInstance] resetUnreadBadgeNumberForAccountId:accountId];
    [[NCNotificationController sharedInstance] removeAllNotificationsForAccountId:accountId];
    [[NCConnectionController shared] checkAppState];

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:accountId forKey:@"accountId"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCSettingsControllerDidChangeActiveAccountNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)createAccountsFile
{
    if (!useAppsGroup) {
        return;
    }

    // Create accounts data
    NSURL *appsGroupFolderURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:appsGroupIdentifier];
    NSMutableArray *accounts = [NSMutableArray new];
    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        UIImage *accountImage = [[NCAPIController sharedInstance] userProfileImageForAccount:account withStyle:UIUserInterfaceStyleLight];
        if (accountImage) {
            accountImage = [NCUtils roundedImageFromImage:accountImage];
        }
        DataAccounts *accountData = [[DataAccounts alloc] initWithUrl:account.server user:account.user name:account.userDisplayName image:accountImage];
        [accounts addObject:accountData];
    }

    NKShareAccounts *shareAccounts = [[NKShareAccounts alloc] init];
    NSError *error = [shareAccounts putShareAccountsAt:appsGroupFolderURL app:@"nextcloudtalk" dataAccounts:accounts];
    NSLog(@"Created accounts file. Error: %@", error);
}

#pragma mark - Notifications

- (void)tokenRevokedResponseReceived:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    // Always remove the account, whether the token has been revoked or marked for remote wipe
    [self logoutAccountWithAccountId:accountId withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCUserInterfaceController sharedInstance] presentConversationsList];
            [[NCUserInterfaceController sharedInstance] presentLoggedOutInvalidCredentialsAlert];
            [[NCConnectionController shared] checkAppState];

            // If the token was marked for remote wipe, confirm the wipe
            [[NCAPIController sharedInstance] checkWipeStatusForAccount:account withCompletionBlock:^(BOOL wipe, NSError *error) {
                if (wipe) {
                    [[NCAPIController sharedInstance] confirmWipeForAccount:account withCompletionBlock:nil];
                }
            }];
        }
    }];
}

- (void)upgradeRequiredResponseReceived:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    if (!_updateAlertController || ![_updateAlertControllerAccountId isEqualToString:accountId]) {
        [self createUpdateAlertContollerForAccountId:accountId];
    }

    [[NCUserInterfaceController sharedInstance] presentAlertIfNotPresentedAlready:_updateAlertController];

}

- (void)createUpdateAlertContollerForAccountId:(NSString *)accountId
{
    NSString *appStoreURLString = @"itms-apps://itunes.apple.com/app/id";
    BOOL canOpenAppStore = [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:appStoreURLString]];

    NSString *messageNotification = NSLocalizedString(@"The app is too old and no longer supported by this server.", nil);
    NSString *messageAction = canOpenAppStore ? NSLocalizedString(@"Please update.", nil) : NSLocalizedString(@"Please contact your system administrator.", nil);
    NSString *message = [NSString stringWithFormat:@"%@ %@", messageNotification, messageAction];

    _updateAlertController = [UIAlertController
                              alertControllerWithTitle:NSLocalizedString(@"App is outdated", nil)
                              message:message
                              preferredStyle:UIAlertControllerStyleAlert];

    _updateAlertControllerAccountId = accountId;

    if (canOpenAppStore) {
        UIAlertAction* updateButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"Update", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction * _Nonnull action) {

            [[NCAPIController sharedInstance] getAppStoreAppIdWithCompletionBlock:^(NSString *appId, NSError *error) {
                if (appId.length > 0) {
                    NSURL *appStoreURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", appStoreURLString, appId]];
                    [[UIApplication sharedApplication] openURL:appStoreURL options:@{} completionHandler:nil];
                }

                self->_updateAlertControllerAccountId = nil;
            }];
        }];

        [_updateAlertController addAction:updateButton];
    }

    NSArray *inactiveAccounts = [[NCDatabaseManager sharedInstance] inactiveAccounts];
    if (inactiveAccounts.count > 0) {
        UIAlertAction* switchAccountButton = [UIAlertAction
                                              actionWithTitle:NSLocalizedString(@"Switch account", nil)
                                              style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {

            [self switchToAnyInactiveAccount];
            self->_updateAlertControllerAccountId = nil;
        }];

        [_updateAlertController addAction:switchAccountButton];
    }

    UIAlertAction* logoutButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"Log out", nil)
                                   style:UIAlertActionStyleDestructive
                                   handler:^(UIAlertAction * _Nonnull action) {

        [[NCUserInterfaceController sharedInstance] logOutAccountWithAccountId:accountId];
        self->_updateAlertControllerAccountId = nil;
    }];

    [_updateAlertController addAction:logoutButton];
}

- (void)talkConfigurationHasChanged:(NSNotification *)notification
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSString *configurationHash = [notification.userInfo objectForKey:@"configurationHash"];
    
    if (!accountId || !configurationHash || ![activeAccount.accountId isEqualToString:accountId]) {
        return;
    }
    
    [self getCapabilitiesForAccountId:accountId withCompletionBlock:^(NSError *error) {
        if (error) {
            return;
        }

        BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateSignalingConfiguration" expirationHandler:nil];

        [self updateSignalingConfigurationForAccountId:accountId withCompletionBlock:^(NCExternalSignalingController * _Nullable signalingServer, NSError *error) {
            if (!error) {
                [[NCDatabaseManager sharedInstance] updateTalkConfigurationHashForAccountId:accountId withHash:configurationHash];
            }

            [bgTask stopBackgroundTask];
        }];
    }];
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
    // Migration from global setting to per-account setting
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:kContactSyncEnabled] boolValue]) {
        // If global setting was enabled then we enable contact sync for all accounts
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm beginWriteTransaction];
        for (TalkAccount *account in [TalkAccount allObjects]) {
            account.hasContactSyncEnabled = YES;
        }
        [realm commitWriteTransaction];
        // Remove global setting
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kContactSyncEnabled];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return YES;
    }
    
    return [[NCDatabaseManager sharedInstance] activeAccount].hasContactSyncEnabled;
}

- (void)setContactSync:(BOOL)enabled
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    TalkAccount *account = [TalkAccount objectsWhere:(@"active = true")].firstObject;
    account.hasContactSyncEnabled = enabled;
    [realm commitWriteTransaction];
}

- (BOOL)didReceiveCallsFromOldAccount
{
    BOOL didReceiveCallsFromOldAccount = [[[NSUserDefaults standardUserDefaults] objectForKey:kDidReceiveCallsFromOldAccount] boolValue];

    return didReceiveCallsFromOldAccount;
}

- (void)setDidReceiveCallsFromOldAccount:(BOOL)receivedOldCalls
{
    [[NSUserDefaults standardUserDefaults] setObject:@(receivedOldCalls) forKey:kDidReceiveCallsFromOldAccount];
}

#pragma mark - User Profile

- (void)getUserProfileForAccountId:(NSString *)accountId withCompletionBlock:(UpdatedProfileCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    if (!account) {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
        block(error);

        return;
    }

    [[NCAPIController sharedInstance] getUserProfileForAccount:account withCompletionBlock:^(NSDictionary *userProfile, NSError *error) {
        if (!error) {
            id emailObject = [userProfile objectForKey:kUserProfileEmail];
            NSString *email = emailObject;
            if (!emailObject || [emailObject isEqual:[NSNull null]]) {
                email = @"";
            }
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCSetUserProfile" expirationHandler:nil];
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                TalkAccount *managedActiveAccount = [TalkAccount objectsWithPredicate:query].firstObject;

                if (!managedActiveAccount) {
                    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
                    block(error);

                    return;
                }

                managedActiveAccount.userId = [userProfile objectForKey:kUserProfileUserId];
                // "display-name" is returned by /cloud/user endpoint
                // change to kUserProfileDisplayName ("displayName") when using /cloud/users/{userId} endpoint
                managedActiveAccount.userDisplayName = [userProfile objectForKey:@"display-name"];
                managedActiveAccount.userDisplayNameScope = [userProfile objectForKey:kUserProfileDisplayNameScope];
                managedActiveAccount.phone = [userProfile objectForKey:kUserProfilePhone];
                managedActiveAccount.phoneScope = [userProfile objectForKey:kUserProfilePhoneScope];
                managedActiveAccount.email = email;
                managedActiveAccount.emailScope = [userProfile objectForKey:kUserProfileEmailScope];
                managedActiveAccount.address = [userProfile objectForKey:kUserProfileAddress];
                managedActiveAccount.addressScope = [userProfile objectForKey:kUserProfileAddressScope];
                managedActiveAccount.website = [userProfile objectForKey:kUserProfileWebsite];
                managedActiveAccount.websiteScope = [userProfile objectForKey:kUserProfileWebsiteScope];
                managedActiveAccount.twitter = [userProfile objectForKey:kUserProfileTwitter];
                managedActiveAccount.twitterScope = [userProfile objectForKey:kUserProfileTwitterScope];
                managedActiveAccount.avatarScope = [userProfile objectForKey:kUserProfileAvatarScope];

                TalkAccount *unmanagedUpdatedAccount = [[TalkAccount alloc] initWithValue:managedActiveAccount];
                [[NCAPIController sharedInstance] saveProfileImageForAccount:unmanagedUpdatedAccount];

                block(nil);
            }];
            [bgTask stopBackgroundTask];
        } else {
            NSLog(@"Error while getting the user profile");
            block(error);
        }
    }];
}

- (void)getUserGroupsAndTeamsForAccountId:(NSString *)accountId
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    if (!account) {
        return;
    }

    [[NCAPIController sharedInstance] getUserGroupsForAccount:account completionBlock:^(NSArray * _Nullable groupIds, NSError * _Nullable error) {
        if (!error) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCSetUserGroups" expirationHandler:nil];
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                TalkAccount *managedActiveAccount = [TalkAccount objectsWithPredicate:query].firstObject;

                if (!managedActiveAccount) {
                    return;
                }

                managedActiveAccount.groupIds = groupIds;
            }];
            [bgTask stopBackgroundTask];
        } else {
            NSLog(@"Error while getting user's groups");
        }
    }];

    [[NCAPIController sharedInstance] getUserTeamsForAccount:account completionBlock:^(NSArray * _Nullable teamIds, NSError * _Nullable error) {
        if (!error) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCSetUserTeams" expirationHandler:nil];
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                TalkAccount *managedActiveAccount = [TalkAccount objectsWithPredicate:query].firstObject;

                if (!managedActiveAccount) {
                    return;
                }

                managedActiveAccount.teamIds = teamIds;
            }];
            [bgTask stopBackgroundTask];
        } else {
            NSLog(@"Error while getting user' teams");
        }
    }];
}

- (void)logoutAccountWithAccountId:(NSString *)accountId withCompletionBlock:(LogoutCompletionBlock)block
{
    TalkAccount *removingAccount = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    if (!removingAccount) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(error);
        }
        return;
    }

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
    [[NCAPIController sharedInstance] removeProfileImageForAccount:removingAccount];
    [[NCAPIController sharedInstance] removeAPISessionManagerForAccount:removingAccount];
    [[NCDatabaseManager sharedInstance] removeAccountWithAccountId:removingAccount.accountId];
    [[[NCChatFileController alloc] init] deleteDownloadDirectoryForAccount:removingAccount];
    [[[NCRoomsManager sharedInstance] chatViewController] leaveChat];
    [self createAccountsFile];
    
    // Activate any of the inactive accounts
    [self switchToAnyInactiveAccount];

    if (block) block(nil);
}

- (void)switchToAnyInactiveAccount
{
    NSArray *inactiveAccounts = [[NCDatabaseManager sharedInstance] inactiveAccounts];
    if (inactiveAccounts.count > 0) {
        TalkAccount *inactiveAccount = [inactiveAccounts objectAtIndex:0];
        [self setActiveAccountWithAccountId:inactiveAccount.accountId];
    }
}

#pragma mark - Signaling Configuration

- (void)updateSignalingConfigurationForAccountId:(NSString *)accountId withCompletionBlock:(UpdateSignalingConfigCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    if (!account) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(nil, error);
        }

        return;
    }

    [[NCAPIController sharedInstance] getSignalingSettingsFor:account forRoom:nil completionBlock:^(SignalingSettings * _Nullable settings, NSError * _Nullable error) {
        if (!error) {
            if (settings && account && account.accountId) {
                NCExternalSignalingController *extSignalingController = [self setSignalingConfigurationForAccountId:account.accountId withSettings:settings];

                if (block) {
                    block(extSignalingController, nil);
                }
            } else {
                NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];

                if (block) {
                    block(nil, error);
                }
            }
        } else {
            NSLog(@"Error while getting signaling configuration");
            if (block) {
                block(nil, error);
            }
        }
    }];
}

- (NCExternalSignalingController * _Nullable)setSignalingConfigurationForAccountId:(NSString *)accountId withSettings:(SignalingSettings * _Nonnull)signalingSettings
{
    [self->_signalingConfigurations setObject:signalingSettings forKey:accountId];

    if (signalingSettings.server && signalingSettings.server.length > 0 && signalingSettings.ticket && signalingSettings.ticket.length > 0) {
        BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCSetSignalingConfiguration" expirationHandler:nil];
        NCExternalSignalingController *extSignalingController = [self->_externalSignalingControllers objectForKey:accountId];

        if (extSignalingController) {
            [extSignalingController disconnect];
        }

        TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
        extSignalingController = [[NCExternalSignalingController alloc] initWithAccount:account server:signalingSettings.server andTicket:signalingSettings.ticket];
        [self->_externalSignalingControllers setObject:extSignalingController forKey:accountId];

        [bgTask stopBackgroundTask];

        return extSignalingController;
    }

    return nil;
}

- (void)ensureSignalingConfigurationForAccountId:(NSString *)accountId withSettings:(SignalingSettings *)settings withCompletionBlock:(EnsureSignalingConfigCompletionBlock)block
{
    SignalingSettings *currentSignalingSettings = [_signalingConfigurations objectForKey:accountId];

    if (currentSignalingSettings) {
        block([self->_externalSignalingControllers objectForKey:accountId]);
    } else {
        [NCUtils log:@"Ensure signaling configuration -> Setting configuration"];

        if (settings) {
            // In case settings are provided, we use these provided settings
            NCExternalSignalingController *extSignalingController = [self setSignalingConfigurationForAccountId:accountId withSettings:settings];
            block(extSignalingController);
        } else {
            // There were no settings provided for that call, we have to update the settings
            [self updateSignalingConfigurationForAccountId:accountId withCompletionBlock:^(NCExternalSignalingController * _Nullable signalingServer, NSError *error) {
                block(signalingServer);
            }];
        }
    }
}

- (NCExternalSignalingController *)externalSignalingControllerForAccountId:(NSString *)accountId
{
    return [_externalSignalingControllers objectForKey:accountId];
}

- (void)connectDisconnectedExternalSignalingControllers
{
    for (NCExternalSignalingController *extSignalingController in self->_externalSignalingControllers.allValues) {
        if (extSignalingController.disconnected) {
            [extSignalingController connect];
        }
    }
}

- (void)disconnectAllExternalSignalingControllers
{
    for (NCExternalSignalingController *extSignalingController in self->_externalSignalingControllers.allValues) {
        [extSignalingController disconnect];
    }
}

#pragma mark - Server Capabilities

- (void)getCapabilitiesForAccountId:(NSString *)accountId withCompletionBlock:(GetCapabilitiesCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];

    if (!account) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(error);
        }

        return;
    }

    [[NCAPIController sharedInstance] getServerCapabilitiesForAccount:account withCompletionBlock:^(NSDictionary *serverCapabilities, NSError *error) {
        if (!error && [serverCapabilities isKindOfClass:[NSDictionary class]]) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateCapabilitiesTransaction" expirationHandler:nil];
            [[NCDatabaseManager sharedInstance] setServerCapabilities:serverCapabilities forAccountId:account.accountId];
            [self checkServerCapabilitiesForAccount:account];
            [bgTask stopBackgroundTask];

            [[NSNotificationCenter defaultCenter] postNotificationName:NCServerCapabilitiesUpdatedNotification
                                                                object:self
                                                              userInfo:nil];
            if (block) {
                block(nil);
            }
        } else {
            NSLog(@"Error while getting server capabilities");
            if (block) {
                block(error);
            }
        }
    }];
}

- (void)checkServerCapabilitiesForAccount:(TalkAccount *)account
{
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    if (serverCapabilities) {
        NSArray *talkFeatures = [serverCapabilities.talkCapabilities valueForKey:@"self"];
        if (!talkFeatures || [talkFeatures count] == 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCTalkNotInstalledNotification
                                                                object:self
                                                              userInfo:nil];
        } else if (![talkFeatures containsObject:kMinimumRequiredTalkCapability]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCOutdatedTalkVersionNotification
                                                                object:self
                                                              userInfo:nil];
        }
    }
}

- (BOOL)canCreateGroupAndPublicRooms
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        return serverCapabilities.canCreate;
    }
    return YES;
}

- (BOOL)isGuestsAppEnabled
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        return serverCapabilities.guestsAppEnabled;
    }
    return NO;
}

- (BOOL)isReferenceApiSupported
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        return serverCapabilities.referenceApiSupported;
    }
    return NO;
}

- (BOOL)isRecordingEnabled
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRecordingV1]) {
        return serverCapabilities.recordingEnabled;
    }
    return NO;
}

#pragma mark - Push Notifications

- (void)subscribeForPushNotificationsForAccountId:(NSString *)accountId withCompletionBlock:(SubscribeForPushNotificationsCompletionBlock)block;
{
#if !TARGET_IPHONE_SIMULATOR
    NCPushNotificationKeyPair *keyPair = nil;
    NSData *pushNotificationPublicKey = [[NCKeyChainController sharedInstance] pushNotificationPublicKeyForAccountId:accountId];
    NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:accountId];
    
    if (pushNotificationPublicKey && pushNotificationPrivateKey) {
        keyPair = [[NCPushNotificationKeyPair alloc] init];
        keyPair.publicKey = pushNotificationPublicKey;
        keyPair.privateKey = pushNotificationPrivateKey;
    } else {
        keyPair = [self generatePushNotificationsKeyPairForAccountId:accountId];
    }
    
    if (!keyPair) {
        [NCUtils log:@"Error while subscribing: Unable to generate push notifications key pair."];

        if (block) {
            block(NO);
        }

        return;
    }

    NSString *pushToken = [[NCKeyChainController sharedInstance] combinedPushToken];

    if (!pushToken) {
        [NCUtils log:@"Error while subscribing: Push token is not available."];

        if (block) {
            block(NO);
        }

        return;
    }

    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"PushProxySubscription" expirationHandler:nil];

    [[NCAPIController sharedInstance] subscribeAccount:[[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId] withPublicKey:keyPair.publicKey toNextcloudServerWithCompletionBlock:^(NSDictionary *responseDict, NSError *error) {
        if (!error) {
            [NCUtils log:@"Subscribed to NC server successfully."];

            NSString *publicKey = [responseDict objectForKey:@"publicKey"];
            NSString *deviceIdentifier = [responseDict objectForKey:@"deviceIdentifier"];
            NSString *signature = [responseDict objectForKey:@"signature"];

            if (!publicKey || !deviceIdentifier || !signature) {
                [NCUtils log:@"Something went wrong subscribing to NC server. Aborting subscribe to Push Notification server."];

                if (block) {
                    block(NO);
                }

                [bgTask stopBackgroundTask];
                return;
            }

            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm beginWriteTransaction];
            NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
            TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
            managedAccount.userPublicKey = publicKey;
            managedAccount.deviceIdentifier = deviceIdentifier;
            managedAccount.deviceSignature = signature;
            [realm commitWriteTransaction];

            [[NCAPIController sharedInstance] subscribeAccount:[[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId] toPushServerWithCompletionBlock:^(NSError *error) {
                if (!error) {
                    RLMRealm *realm = [RLMRealm defaultRealm];
                    [realm beginWriteTransaction];
                    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
                    TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
                    managedAccount.lastPushSubscription = [[NSDate date] timeIntervalSince1970];
                    [realm commitWriteTransaction];
                    [[NCKeyChainController sharedInstance] setPushNotificationPublicKey:keyPair.publicKey forAccountId:accountId];
                    [[NCKeyChainController sharedInstance] setPushNotificationPrivateKey:keyPair.privateKey forAccountId:accountId];
                    [NCUtils log:@"Subscribed to Push Notification server successfully."];

                    if (block) {
                        block(YES);
                    }

                    [bgTask stopBackgroundTask];
                } else {
                    [NCUtils log:[NSString stringWithFormat:@"Error while subscribing to Push Notification server. Error: %@", error.description]];
                    [NCUtils log:[NSString stringWithFormat:@"Push notification, public key: %@", publicKey]];
                    [NCUtils log:[NSString stringWithFormat:@"Push notification, device signature: %@", signature]];
                    [NCUtils log:[NSString stringWithFormat:@"Push notification, device identifier: %@", deviceIdentifier]];
                    [[NCKeyChainController sharedInstance] logCombinedPushToken];

                    if (block) {
                        block(NO);
                    }

                    [bgTask stopBackgroundTask];
                }
            }];
        } else {
            [NCUtils log:[NSString stringWithFormat:@"Error while subscribing to NC server. Error: %@", error.description]];

            if (block) {
                block(NO);
            }

            [bgTask stopBackgroundTask];
        }
    }];
#else
    if (block) {
        block(YES);
    }
#endif
}

- (NCPushNotificationKeyPair *)generatePushNotificationsKeyPairForAccountId:(NSString *)accountId
{
    EVP_PKEY *pkey = [self generateRSAKey];
    if (!pkey) {
        return nil;
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
    NSLog(@"Push Notifications Key Pair generated: \n%@", [[NSString alloc] initWithData:pnPublicKey encoding:NSUTF8StringEncoding]);
    
    // PrivateKey
    BIO *privateKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PKCS8PrivateKey(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL);
    
    len = BIO_pending(privateKeyBIO);
    keyBytes = malloc(len);
    
    BIO_read(privateKeyBIO, keyBytes, len);
    NSData *pnPrivateKey = [NSData dataWithBytes:keyBytes length:len];
    EVP_PKEY_free(pkey);
    
    NCPushNotificationKeyPair *keyPair = [[NCPushNotificationKeyPair alloc] init];
    keyPair.publicKey = pnPublicKey;
    keyPair.privateKey = pnPrivateKey;
    
    return keyPair;
}

- (EVP_PKEY *)generateRSAKey
{
    EVP_PKEY *pkey = EVP_PKEY_new();
    if (!pkey) {
        return NULL;
    }
    
    BIGNUM *bigNumber = BN_new();
    int exponent = RSA_F4;
    RSA *rsa = RSA_new();
    
    if (BN_set_word(bigNumber, exponent) == 0) {
        pkey = NULL;
        goto cleanup;
    }
    
    if (RSA_generate_key_ex(rsa, 2048, bigNumber, NULL) == 0) {
        pkey = NULL;
        goto cleanup;
    }
    
    if (!EVP_PKEY_set1_RSA(pkey, rsa)) {
        pkey = NULL;
        goto cleanup;
    }
    
cleanup:
    RSA_free(rsa);
    BN_free(bigNumber);
    
    return pkey;
}

@end
