/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "ChatTableViewCell.h"
#import "MessageBodyTextView.h"
#import "NCChatMessage.h"

static CGFloat kSystemMessageCellMinimumHeight  = 30.0;

static NSString *SystemMessageCellIdentifier            = @"SystemMessageCellIdentifier";

@protocol SystemMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToCollapseMessagesWithMessage:(NCChatMessage *)message;

@end

@interface SystemMessageTableViewCell : ChatTableViewCell

@property (nonatomic, weak) id<SystemMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIButton *collapseButton;

- (void)setupForMessage:(NCChatMessage *)message;

@end
