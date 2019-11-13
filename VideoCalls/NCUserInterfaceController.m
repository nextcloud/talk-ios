//
//  NCUserInterfaceController.m
//  VideoCalls
//
//  Created by Ivan Sein on 28.02.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCUserInterfaceController.h"

#import "AFNetworking.h"
#import "AuthenticationViewController.h"
#import "LoginViewController.h"
#import "NCConnectionController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "JDStatusBarNotification.h"

@interface NCUserInterfaceController () <LoginViewControllerDelegate, AuthenticationViewControllerDelegate>
{
    LoginViewController *_loginViewController;
    AuthenticationViewController *_authViewController;
    NCPushNotification *_pendingPushNotification;
    NSMutableDictionary *_pendingCallKitCall;
    NSDictionary *_pendingLocalNotification;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCapabilitiesReceived:) name:NCServerCapabilitiesReceivedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)presentConversationsList
{
    [_mainNavigationController dismissViewControllerAnimated:NO completion:nil];
    [_mainNavigationController popToRootViewControllerAnimated:NO];
}

- (void)presentLoginViewController
{
    _loginViewController = [[LoginViewController alloc] init];
    _loginViewController.delegate = self;
    [_mainNavigationController presentViewController:_loginViewController animated:YES completion:nil];
}

- (void)presentAuthenticationViewController
{
    _authViewController = [[AuthenticationViewController alloc] init];
    _authViewController.delegate = self;
    _authViewController.serverUrl = [NCSettingsController sharedInstance].ncServer;
    [_mainNavigationController presentViewController:_authViewController animated:YES completion:nil];
}

- (void)presentOfflineWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:@"Disconnected"
                                 message:@"It seems that there is no Internet connection."
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    
    [_mainNavigationController presentViewController:alert animated:YES completion:nil];
}

- (void)presentTalkNotInstalledWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:@"Nextcloud Talk not installed"
                                 message:@"It seems that Nextcloud Talk is not installed in your server."
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
                                   [self logOutCurrentUser];
                               }];
    
    [alert addAction:okButton];
    
    [_mainNavigationController presentViewController:alert animated:YES completion:nil];
}

- (void)presentTalkOutdatedWarningAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:@"Nextcloud Talk version not supported"
                                 message:@"Please update your server with the latest Nextcloud Talk version available."
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
                                   [self logOutCurrentUser];
                               }];
    
    [alert addAction:okButton];
    
    [_mainNavigationController presentViewController:alert animated:YES completion:nil];
}

- (void)logOutCurrentUser
{
    [[NCSettingsController sharedInstance] logoutWithCompletionBlock:^(NSError *error) {
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
                                 message:@"Do you want to join this call?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *joinAudioButton = [UIAlertAction
                                      actionWithTitle:@"Join call (audio only)"
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction * _Nonnull action) {
                                          NSDictionary *userInfo = [NSDictionary dictionaryWithObject:pushNotification forKey:@"pushNotification"];
                                          [[NSNotificationCenter defaultCenter] postNotificationName:NCPushNotificationJoinAudioCallAcceptedNotification
                                                                                              object:self
                                                                                            userInfo:userInfo];
                                      }];
    
    UIAlertAction *joinVideoButton = [UIAlertAction
                                      actionWithTitle:@"Join call with video"
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction * _Nonnull action) {
                                          NSDictionary *userInfo = [NSDictionary dictionaryWithObject:pushNotification forKey:@"pushNotification"];
                                          [[NSNotificationCenter defaultCenter] postNotificationName:NCPushNotificationJoinVideoCallAcceptedNotification
                                                                                              object:self
                                                                                            userInfo:userInfo];
                                      }];
    
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:@"Cancel"
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    
    [joinAudioButton setValue:[[UIImage imageNamed:@"call-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [joinVideoButton setValue:[[UIImage imageNamed:@"videocall-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    
    [alert addAction:joinAudioButton];
    [alert addAction:joinVideoButton];
    [alert addAction:cancelButton];
    
    // Do not show join call dialog until we don't handle 'hangup current call'/'join new one' properly.
    if (![NCRoomsManager sharedInstance].callViewController) {
        [_mainNavigationController dismissViewControllerAnimated:NO completion:nil];
        [_mainNavigationController presentViewController:alert animated:YES completion:nil];
    } else {
        NSLog(@"Not showing join call dialog due to in a call.");
    }
}

- (void)presentAlertViewController:(UIAlertController *)alertViewController
{
    [_mainNavigationController presentViewController:alertViewController animated:YES completion:nil];
}

- (void)presentChatViewController:(NCChatViewController *)chatViewController
{
    [self presentConversationsList];
    [_mainNavigationController pushViewController:chatViewController animated:YES];
}

- (void)presentCallViewController:(CallViewController *)callViewController
{
    [_mainNavigationController dismissViewControllerAnimated:NO completion:nil];
    [_mainNavigationController presentViewController:callViewController animated:YES completion:nil];
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
        }
    }
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    switch (connectionState) {
        case kConnectionStateDisconnected:
            [JDStatusBarNotification showWithStatus:@"Network not available" dismissAfter:4.0f styleName:JDStatusBarStyleError];
            break;
            
        case kConnectionStateConnected:
            [JDStatusBarNotification showWithStatus:@"Network available" dismissAfter:4.0f styleName:JDStatusBarStyleSuccess];
            break;
            
        default:
            break;
    }
}

- (void)serverCapabilitiesReceived:(NSNotification *)notification
{
    // If the logged-in user is using an old NC Talk version or is not allowed to use Talk then logged the user out.
    if (![[NCSettingsController sharedInstance] serverUsesRequiredTalkVersion]) {
        if ([[[NCSettingsController sharedInstance] ncTalkCapabilities] count] == 0) {
            [self presentTalkNotInstalledWarningAlert];
        } else {
            [self presentTalkOutdatedWarningAlert];
        }
    }
}

#pragma mark - LoginViewControllerDelegate

- (void)loginViewControllerDidFinish:(LoginViewController *)viewController
{
    [_mainNavigationController dismissViewControllerAnimated:YES completion:^{
        [[NCConnectionController sharedInstance] checkAppState];
        // Get server capabilities again to check if user is allowed to use Nextcloud Talk
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:nil];
    }];
}

#pragma mark - AuthenticationViewControllerDelegate

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController
{
    [_mainNavigationController dismissViewControllerAnimated:YES completion:^{
        [[NCConnectionController sharedInstance] checkAppState];
        // Get server capabilities again to check if user is allowed to use Nextcloud Talk
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:nil];
    }];
}


@end
