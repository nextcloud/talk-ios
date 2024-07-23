/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCMessageParameter.h"

NS_ASSUME_NONNULL_BEGIN

@interface NCMessageLocationParameter : NCMessageParameter

@property (nonatomic, strong) NSString *latitude;
@property (nonatomic, strong) NSString *longitude;

@end

NS_ASSUME_NONNULL_END
