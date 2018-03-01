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
#import "NCSettingsController.h"

@interface NCUserInterfaceController () <LoginViewControllerDelegate, AuthenticationViewControllerDelegate, CallViewControllerDelegate>
{
    LoginViewController *_loginViewController;
    AuthenticationViewController *_authViewController;
    CallViewController *_callViewController;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityHasChanged:) name:NCNetworkReachabilityHasChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)presentCallsViewController
{
    [self.mainTabBarController setSelectedIndex:0];
}

- (void)presentContactsViewController
{
    [self.mainTabBarController setSelectedIndex:1];
}

- (void)presentSettingsViewController
{
    [self.mainTabBarController setSelectedIndex:2];
}

- (void)presentLoginViewController
{
    _loginViewController = [[LoginViewController alloc] init];
    _loginViewController.delegate = self;
    [self.mainTabBarController presentViewController:_loginViewController animated:YES completion:nil];
}

- (void)presentAuthenticationViewController
{
    _authViewController = [[AuthenticationViewController alloc] init];
    _authViewController.delegate = self;
    _authViewController.serverUrl = [NCSettingsController sharedInstance].ncServer;
    [self.mainTabBarController presentViewController:_authViewController animated:YES completion:nil];
}

- (void)presentAlertViewController:(UIAlertController *)alertViewController
{
    [self.mainTabBarController presentViewController:alertViewController animated:YES completion:nil];
}

- (void)presentCallViewController:(CallViewController *)callViewController
{
    _callViewController = callViewController;
    _callViewController.delegate = self;
    [self.mainTabBarController presentViewController:_callViewController animated:YES completion:nil];
}

#pragma mark - Notifications

- (void)networkReachabilityHasChanged:(NSNotification *)notification
{
    AFNetworkReachabilityStatus status = [[notification.userInfo objectForKey:kNCNetworkReachabilityKey] intValue];
    NSLog(@"Network Status:%ld", (long)status);
}

#pragma mark - LoginViewControllerDelegate

- (void)loginViewControllerDidFinish:(LoginViewController *)viewController
{
    if (viewController == _loginViewController && self.mainTabBarController.presentedViewController == _loginViewController) {
        [self.mainTabBarController dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - AuthenticationViewControllerDelegate

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController
{
    if (viewController == _authViewController && self.mainTabBarController.presentedViewController == _authViewController) {
        [self.mainTabBarController dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - CallViewControllerDelegate

- (void)callViewControllerDidFinish:(CallViewController *)viewController {
    if (![viewController isBeingDismissed]) {
        [viewController dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
