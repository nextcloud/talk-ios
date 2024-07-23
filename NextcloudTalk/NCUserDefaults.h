//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCUserDefaults : NSObject

+ (void)setPreferredCameraFlashMode:(NSInteger)flashMode;
+ (NSInteger)preferredCameraFlashMode;
+ (void)setBackgroundBlurEnabled:(BOOL)enabled;
+ (BOOL)backgroundBlurEnabled;
+ (void)setIncludeCallsInRecentsEnabled:(BOOL)enabled;
+ (BOOL)includeCallsInRecents;

@end

NS_ASSUME_NONNULL_END
