//
//  ReplyMessageView.h
//  VideoCalls
//
//  Created by Ivan Sein on 21.11.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SLKTypingIndicatorProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class NCChatMessage;
@class QuotedMessageView;

@interface ReplyMessageView : UIView <SLKTypingIndicatorProtocol>

@property (nonatomic, strong) NCChatMessage *message;
@property (nonatomic, strong) QuotedMessageView *quotedMessageView;

- (void)presentReplyViewWithMessage:(NCChatMessage *)message;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
