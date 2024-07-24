/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCMessageParameter.h"

NS_ASSUME_NONNULL_BEGIN

@interface NCDeckCardParameter : NCMessageParameter

@property (nonatomic, strong) NSString *stackName;
@property (nonatomic, strong) NSString *boardName;

@end

NS_ASSUME_NONNULL_END
