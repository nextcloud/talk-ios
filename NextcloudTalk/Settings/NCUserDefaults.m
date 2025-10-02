//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCUserDefaults.h"

#import "NCKeyChainController.h"

@implementation NCUserDefaults

NSString * const kNCPreferredCameraFlashMode    = @"ncPreferredCameraFlashMode";
NSString * const kNCBackgroundBlurEnabled       = @"ncBackgroundBlurEnabled";
NSString * const kNCIncludeCallsInRecents       = @"ncIncludeCallsInRecents";

+ (void)setPreferredCameraFlashMode:(NSInteger)flashMode
{
    [[NSUserDefaults standardUserDefaults] setObject:@(flashMode) forKey:kNCPreferredCameraFlashMode];
}

+ (NSInteger)preferredCameraFlashMode
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCPreferredCameraFlashMode] integerValue];
}

+ (void)setBackgroundBlurEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setObject:@(enabled) forKey:kNCBackgroundBlurEnabled];
}

+ (BOOL)backgroundBlurEnabled
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCBackgroundBlurEnabled] boolValue];
}

+ (void)setIncludeCallsInRecentsEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setObject:@(enabled) forKey:kNCIncludeCallsInRecents];
}

+ (BOOL)includeCallsInRecents
{
    id includeCallsInRecentsObject = [[NSUserDefaults standardUserDefaults] objectForKey:kNCIncludeCallsInRecents];
    if (includeCallsInRecentsObject == nil) {
        [self setIncludeCallsInRecentsEnabled:YES];
        return YES;
    }

    return [includeCallsInRecentsObject boolValue];
}

@end
