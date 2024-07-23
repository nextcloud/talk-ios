/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCNavigationController.h"

#import "NCAppBranding.h"

@interface NCNavigationController () <UIGestureRecognizerDelegate>

@end

@implementation NCNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.interactivePopGestureRecognizer.delegate = self;
    
    [self.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.navigationBar.translucent = NO;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [NCAppBranding themeColor];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return [NCAppBranding statusBarStyleForThemeColor];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    // This allows to overwrite the pop gesture recognizer with another gesture recognizer
    // (e.g. long press gesture to record voice message when interface is in RTL)
    return YES;
}


@end
