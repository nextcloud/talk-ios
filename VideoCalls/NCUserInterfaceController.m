//
//  NCUserInterfaceController.m
//  VideoCalls
//
//  Created by Ivan Sein on 28.02.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCUserInterfaceController.h"

#import "AuthenticationViewController.h"
#import "LoginViewController.h"
#import "NCSettingsController.h"

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
    LoginViewController *loginVC = [[LoginViewController alloc] init];
    [self.mainTabBarController presentViewController:loginVC animated:YES completion:nil];
}

- (void)presentAuthenticationViewController
{
    AuthenticationViewController *authVC = [[AuthenticationViewController alloc] init];
    authVC.serverUrl = [NCSettingsController sharedInstance].ncServer;
    [self.mainTabBarController presentViewController:authVC animated:YES completion:nil];
}

- (void)presentAlertViewController:(UIAlertController *)alertViewController
{
    [self.mainTabBarController presentViewController:alertViewController animated:YES completion:nil];
}

- (void)presentCallViewController:(CallViewController *)callViewController
{
    [self.mainTabBarController presentViewController:callViewController animated:YES completion:nil];
}

@end
