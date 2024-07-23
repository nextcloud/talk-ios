/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <PushKit/PushKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, PKPushRegistryDelegate>
{
    PKPushRegistry *pushRegistry;
    NSString *normalPushToken;
    NSString *pushKitToken;
}
@property (strong, nonatomic) UIWindow *window;
@property (assign, nonatomic) BOOL shouldLockInterfaceOrientation;
@property (assign, nonatomic) UIInterfaceOrientation lockedInterfaceOrientation;

- (void)keepExternalSignalingConnectionAliveTemporarily;

@end

