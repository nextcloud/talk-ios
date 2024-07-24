/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import "SLKVisibleViewProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class NCChatMessage;
@class QuotedMessageView;

@interface ReplyMessageView : UIView <SLKVisibleViewProtocol>

@property (nonatomic, strong) NCChatMessage *message;
@property (nonatomic, strong) QuotedMessageView *quotedMessageView;
@property (nonatomic, strong) CALayer *topBorder;

- (void)presentReplyViewWithMessage:(NCChatMessage *)message withUserId:(NSString *)userId;
- (void)dismiss;
- (void)hideCloseButton;

@end

NS_ASSUME_NONNULL_END
