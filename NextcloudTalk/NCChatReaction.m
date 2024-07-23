/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCChatReaction.h"

@implementation NCChatReaction

+ (instancetype)initWithReaction:(NSString *)reaction andCount:(NSInteger)count
{
    NCChatReaction *reactionObject = [[NCChatReaction alloc] init];
    reactionObject.reaction = reaction;
    reactionObject.count = count;
    return reactionObject;
}

@end
