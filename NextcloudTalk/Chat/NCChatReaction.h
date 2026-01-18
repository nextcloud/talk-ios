/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import "NCTypes.h"

@interface NCChatReaction : NSObject

@property (nonatomic, strong) NSString *reaction;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) BOOL userReacted;
@property (nonatomic, assign) NCChatReactionState state;

+ (instancetype)initWithReaction:(NSString *)reaction andCount:(NSInteger)count;

@end

