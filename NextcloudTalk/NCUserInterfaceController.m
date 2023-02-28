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

#import "NCUserInterfaceController.h"

#import "AFNetworking.h"
#import "JDStatusBarNotification.h"
#import "UIView+Toast.h"

#import "AuthenticationViewController.h"
#import "LoginViewController.h"
#import "NCAppBranding.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUtils.h"
#import "NotificationCenterNotifications.h"

#import "NextcloudTalk-Swift.h"

@interface NCUserInterfaceController () <LoginViewControllerDelegate, AuthenticationViewControllerDelegate>
{
    LoginViewController *_loginViewController;
    AuthenticationViewController *_authViewController;
    NCPushNotification *_pendingPushNotification;
    NSMutableDictionary *_pendingCallKitCall;
    NSDictionary *_pendingLocalNotification;
    NSURLComponents *_pendingURL;
    BOOL _waitingForServerCapabilities;
}

@end

@implementation NCUserInterfaceController

+ (NCUserInterfaceController *)sharedInstance
{
    static dispatch_once_t once;
    static NCUserInterfaceController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        [self configureToasts];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentTalkNotInstalledWarningAlert) name:NCTalkNotInstalledNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentTalkOutdatedWarningAlert) name:NCOutdatedTalkVersionNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentServerMaintenanceModeWarning:) name:NCServerMaintenanceModeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureToasts
{
    CSToastStyle *style = [[CSToastStyle alloc] initWithDefaultStyle];
    style.messageFont = [UIFont systemFontOfSize:15.0];
    style.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
    style.cornerRadius = 5.0;
    
    [CSToastManager setSharedStyle:style];
}


- (void)presentLoginViewController
{
    [self presentLoginViewControllerForServerURL:nil withUser:nil];
}

- (void)presentLoginViewControllerForServerURL:(NSString *)serverURL withUser:(NSString *)user
{
    if (forceDomain && domain) {
        _authViewController = [[AuthenticationViewController alloc] initWithServerUrl:domain];
        _authViewController.delegate = self;
        _authViewController.modalPresentationStyle = ([[NCDatabaseManager sharedInstance] numberOfAccounts] == 0) ? UIModalPresentationFullScreen : UIModalPresentationAutomatic;
        [_mainViewController presentViewController:_authViewController animated:YES completion:nil];
    } else {
        // Don't open a login if we're in a call
        if ([[NCRoomsManager sharedInstance] callViewController]) {
            return;
        }
        
        // Leave chat if we're currently in one
        if ([[NCRoomsManager sharedInstance] chatViewController]) {
            [self presentConversationsList];
        }
        
        if (!_loginViewController || [_mainViewController presentedViewController] != _loginViewController) {
            _loginViewController = [[LoginViewController alloc] init];
            _loginViewController.delegate = self;
            _loginViewController.modalPresentationStyle = ([[NCDatabaseManager sharedInstance] numberOfAccounts] == 0) ? UIModalPresentationFullScreen : UIModalPresentationAutomatic;
            
            [_mainViewController presentViewController:_loginViewController animated:YES completion:nil];
        }
        
        if (serverURL) {
            [_loginViewController startLoginProcessWithServerURL:serverURL withUser:user];
        }
    }
}

- (void)presentLoggedOutInvalidCredentialsAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Logged out", nil)
                                 message:NSLocalizedString(@"Credentials for this account were no longer valid", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];

    [_mainViewController presentViewController:alert animated:YES completion:nil];
}

- (void)presentOfflineWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Disconnected", nil)
                                 message:NSLocalizedString(@"It seems that there is no internet connection.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];

    [_mainViewController presentViewController:alert animated:YES completion:nil];
}

- (void)presentTalkNotInstalledWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%@ not installed", @"{app name} is not installed"), talkAppName]
                                 message:[NSString stringWithFormat:NSLocalizedString(@"It seems that %@ is not installed in your server.", @"It seems that {app name} is not installed in your server."), talkAppName]
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
                                   [self logOutCurrentUser];
                               }];
    
    [alert addAction:okButton];

    [_mainViewController presentViewController:alert animated:YES completion:nil];
}

- (void)presentTalkOutdatedWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%@ version not supported", @"{app name} version not supported"), talkAppName]
                                 message:[NSString stringWithFormat:NSLocalizedString(@"Please update your server with the latest %@ version available.", @"Please update your server with the latest {app name} version available."), talkAppName]
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
                                   [self logOutCurrentUser];
                               }];
    
    [alert addAction:okButton];

    [_mainViewController presentViewController:alert animated:YES completion:nil];
}

- (void)presentAccountNotConfiguredAlertForUser:(NSString *)user inServer:(NSString *)server
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Account not configured", nil)
                                 message:[NSString stringWithFormat:NSLocalizedString(@"There is no account for user %@ in server %@ configured in this app.", nil), user, server]
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];

    [_mainViewController presentViewController:alert animated:YES completion:nil];
}

- (void)presentServerMaintenanceModeWarning:(NSNotification *)notification
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    
    if (accountId && [activeAccount.accountId isEqualToString:accountId]) {
        [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Server is currently in maintenance mode", nil) dismissAfterDelay:4.0f includedStyle:JDStatusBarNotificationIncludedStyleError];
    }
}

- (void)logOutCurrentUser
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCSettingsController sharedInstance] logoutAccountWithAccountId:activeAccount.accountId withCompletionBlock:^(NSError *error) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
        [[NCConnectionController sharedInstance] checkAppState];
    }];
}

- (void)presentChatForLocalNotification:(NSDictionary *)userInfo
{
    if ([NCConnectionController sharedInstance].appState != kAppStateReady) {
        _waitingForServerCapabilities = YES;
        _pendingLocalNotification = userInfo;
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NCLocalNotificationJoinChatNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)presentChatForPushNotification:(NCPushNotification *)pushNotification
{
    if ([NCConnectionController sharedInstance].appState != kAppStateReady) {
        _waitingForServerCapabilities = YES;
        _pendingPushNotification = pushNotification;
        return;
    }
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:pushNotification forKey:@"pushNotification"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCPushNotificationJoinChatNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)presentAlertForPushNotification:(NCPushNotification *)pushNotification
{
    if ([NCConnectionController sharedInstance].appState != kAppStateReady) {
        _waitingForServerCapabilities = YES;
        _pendingPushNotification = pushNotification;
        return;
    }
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:[pushNotification bodyForRemoteAlerts]
                                 message:NSLocalizedString(@"Do you want to join this call?", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *joinAudioButton = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"Join call (audio only)", nil)
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction * _Nonnull action) {
                                          NSDictionary *userInfo = [NSDictionary dictionaryWithObject:pushNotification forKey:@"pushNotification"];
                                          [[NSNotificationCenter defaultCenter] postNotificationName:NCPushNotificationJoinAudioCallAcceptedNotification
                                                                                              object:self
                                                                                            userInfo:userInfo];
                                      }];
    
    UIAlertAction *joinVideoButton = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"Join call with video", nil)
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction * _Nonnull action) {
                                          NSDictionary *userInfo = [NSDictionary dictionaryWithObject:pushNotification forKey:@"pushNotification"];
                                          [[NSNotificationCenter defaultCenter] postNotificationName:NCPushNotificationJoinVideoCallAcceptedNotification
                                                                                              object:self
                                                                                            userInfo:userInfo];
                                      }];
    
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    
    [joinAudioButton setValue:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    [joinVideoButton setValue:[[UIImage imageNamed:@"video"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    [alert addAction:joinAudioButton];
    [alert addAction:joinVideoButton];
    [alert addAction:cancelButton];
    
    // Do not show join call dialog until we don't handle 'hangup current call'/'join new one' properly.
    if (![NCRoomsManager sharedInstance].callViewController) {
        [_mainViewController dismissViewControllerAnimated:NO completion:nil];
        [_mainViewController presentViewController:alert animated:YES completion:nil];
    } else {
        NSLog(@"Not showing join call dialog due to in a call.");
    }
}

- (void)presentAlertViewController:(UIAlertController *)alertViewController
{
    if (_mainViewController.presentedViewController != nil) {
        // When the callview is presented, we need to show the alert this way
        [_mainViewController.presentedViewController presentViewController:alertViewController animated:YES completion:nil];
    } else {
        [_mainViewController presentViewController:alertViewController animated:YES completion:nil];
    }
}

- (void)presentConversationsList
{
    [_mainViewController dismissViewControllerAnimated:YES completion:nil];

    [_mainViewController popSecondaryColumnToRootViewController];
    [_mainViewController showColumn:UISplitViewControllerColumnPrimary];
}

- (void)popToConversationsList
{
    [_mainViewController popSecondaryColumnToRootViewController];
    [_mainViewController showColumn:UISplitViewControllerColumnPrimary];
}

- (void)presentChatViewController:(NCChatViewController *)chatViewController
{
    [self presentConversationsList];
    [_mainViewController showDetailViewController:chatViewController sender:self];
    [_roomsTableViewController setSelectedRoomToken:chatViewController.room.token];
}

- (void)presentCallViewController:(CallViewController *)callViewController
{
    [_mainViewController dismissViewControllerAnimated:NO completion:nil];
    [_mainViewController presentViewController:callViewController animated:YES completion:nil];
}

- (void)presentCallKitCallInRoom:(NSString *)token withVideoEnabled:(BOOL)video
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:token forKey:@"roomToken"];
    [userInfo setValue:@(video) forKey:@"isVideoEnabled"];
    if ([NCConnectionController sharedInstance].appState != kAppStateReady) {
        _waitingForServerCapabilities = YES;
        _pendingCallKitCall = userInfo;
        return;
    }
    [self startCallKitCall:userInfo];
}

- (void)startCallKitCall:(NSMutableDictionary *)callDict
{
    NSString *roomToken = [callDict objectForKey:@"roomToken"];
    BOOL video = [[callDict objectForKey:@"isVideoEnabled"] boolValue];
    [[NCRoomsManager sharedInstance] joinCallWithCallToken:roomToken withVideo:video];
}

- (void)presentChatForURL:(NSURLComponents *)urlComponents
{
    if ([NCConnectionController sharedInstance].appState != kAppStateReady) {
        _waitingForServerCapabilities = YES;
        _pendingURL = urlComponents;
        return;
    }
    
    NSArray *queryItems = urlComponents.queryItems;
    NSString *server = [NCUtils valueForKey:@"server" fromQueryItems:queryItems];
    NSString *user = [NCUtils valueForKey:@"user" fromQueryItems:queryItems];
    NSString *withUser = [NCUtils valueForKey:@"withUser" fromQueryItems:queryItems];
    NSString *withRoomToken = [NCUtils valueForKey:@"withRoomToken" fromQueryItems:queryItems];
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForUserId:user inServer:server];
    
    if (!account) {
        [self presentAccountNotConfiguredAlertForUser:user inServer:server];
        return;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:account.accountId forKey:@"accountId"];
    if (withUser) {
        [userInfo setValue:withUser forKey:@"withUser"];
    } else if (withRoomToken) {
        [userInfo setValue:withRoomToken forKey:@"withRoomToken"];
    } else { return; }

    [[NSNotificationCenter defaultCenter] postNotificationName:NCURLWantsToOpenConversationNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)presentSettingsViewController
{
    [self presentConversationsList];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    NCNavigationController *settingsNC = [storyboard instantiateViewControllerWithIdentifier:@"settingsNC"];
    [self.mainViewController presentViewController:settingsNC animated:YES completion:nil];
}

#pragma mark - Notifications

- (void)appStateHasChanged:(NSNotification *)notification
{
    AppState appState = [[notification.userInfo objectForKey:@"appState"] intValue];
    if (appState == kAppStateReady && _waitingForServerCapabilities) {
        _waitingForServerCapabilities = NO;
        if (_pendingPushNotification) {
            if (_pendingPushNotification.type == NCPushNotificationTypeCall) {
                [self presentAlertForPushNotification:_pendingPushNotification];
            } else {
                [self presentChatForPushNotification:_pendingPushNotification];
            }
        } else if (_pendingCallKitCall) {
            [self startCallKitCall:_pendingCallKitCall];
        } else if (_pendingURL) {
            [self presentChatForURL:_pendingURL];
        }
    }
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    switch (connectionState) {
        case kConnectionStateDisconnected:
            [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Network not available", nil) dismissAfterDelay:4.0f includedStyle:JDStatusBarNotificationIncludedStyleError];
            break;
            
        case kConnectionStateConnected:
            [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Network available", nil) dismissAfterDelay:4.0f includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
            break;
            
        default:
            break;
    }
}

#pragma mark - LoginViewControllerDelegate

- (void)loginViewControllerDidFinish:(LoginViewController *)viewController
{
    [_mainViewController dismissViewControllerAnimated:YES completion:^{
        [[NCConnectionController sharedInstance] checkAppState];
        // Get server capabilities again to check if user is allowed to use Nextcloud Talk
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:nil];
    }];
}

#pragma mark - AuthenticationViewControllerDelegate

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController
{
    [_mainViewController dismissViewControllerAnimated:YES completion:^{
        [[NCConnectionController sharedInstance] checkAppState];
        // Get server capabilities again to check if user is allowed to use Nextcloud Talk
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:nil];
    }];
}

@end
