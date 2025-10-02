/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NCChatReactionState) {
    NCChatReactionStateSet = 0,
    NCChatReactionStateAdding,
    NCChatReactionStateRemoving,
    NCChatReactionStateAdded,
    NCChatReactionStateRemoved
};

@interface NCChatReaction : NSObject

@property (nonatomic, strong) NSString *reaction;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) BOOL userReacted;
@property (nonatomic, assign) NCChatReactionState state;

+ (instancetype)initWithReaction:(NSString *)reaction andCount:(NSInteger)count;

@end

