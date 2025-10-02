/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCPushNotificationsUtils : NSObject

+ (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey;

@end

NS_ASSUME_NONNULL_END
