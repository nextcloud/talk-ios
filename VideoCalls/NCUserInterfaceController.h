//
//  NCUserInterfaceController.h
//  VideoCalls
//
//  Created by Ivan Sein on 28.02.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CallViewController.h"

@interface NCUserInterfaceController : NSObject

@property (nonatomic, strong) UITabBarController *mainTabBarController;

+ (instancetype)sharedInstance;
- (void)presentCallsViewController;
- (void)presentContactsViewController;
- (void)presentSettingsViewController;
- (void)presentLoginViewController;
- (void)presentAuthenticationViewController;
- (void)presentAlertViewController:(UIAlertController *)alertViewController;
- (void)presentCallViewController:(CallViewController *)callViewController;

@end
