/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "DRCellSlideGestureRecognizer.h"
#import "NCChatMessage.h"

static CGFloat kChatCellStatusViewHeight    = 20.0;
static CGFloat kChatCellDateLabelWidth      = 40.0;
static CGFloat kChatCellAvatarHeight        = 30.0;

typedef NS_ENUM(NSInteger, ChatMessageDeliveryState) {
    ChatMessageDeliveryStateSent = 0,
    ChatMessageDeliveryStateRead,
    ChatMessageDeliveryStateSending,
    ChatMessageDeliveryStateDeleting,
    ChatMessageDeliveryStateFailed
};

@protocol ChatTableViewCellDelegate <NSObject>

- (void)cellDidSelectedReaction:(NCChatReaction *)reaction forMessage:(NCChatMessage *)message;
- (void)cellWantsToReplyToMessage:(NCChatMessage *)message;

@end

@interface ChatTableViewCell : UITableViewCell

@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NCChatMessage *message;

- (UIMenu *)getDeferredUserMenuForMessage:(NCChatMessage *)message;
- (void)addReplyGestureWithActionBlock:(DRCellSlideActionBlock)block;

@end
