/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "MessageBodyTextView.h"
#import "NCChatMessage.h"

static CGFloat kChatCellAvatarHeight        = 30.0;
static CGFloat kSystemMessageCellMinimumHeight  = 30.0;

static NSString *SystemMessageCellIdentifier            = @"SystemMessageCellIdentifier";

@protocol SystemMessageTableViewCellDelegate <NSObject>

- (void)cellWantsToCollapseMessagesWithMessage:(NCChatMessage *)message;

@end

@interface SystemMessageTableViewCell : UITableViewCell

@property (nonatomic, weak) id<SystemMessageTableViewCellDelegate> delegate;

@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NCChatMessage *message;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIButton *collapseButton;

- (void)setupForMessage:(NCChatMessage *)message;

@end
