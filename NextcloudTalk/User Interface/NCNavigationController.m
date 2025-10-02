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

    [NCAppBranding styleViewController:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    if (@available(iOS 26, *)) {
        return UIStatusBarStyleDefault;
    }

    return [NCAppBranding statusBarStyleForThemeColor];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    // This allows to overwrite the pop gesture recognizer with another gesture recognizer
    // (e.g. long press gesture to record voice message when interface is in RTL)
    return YES;
}


@end
