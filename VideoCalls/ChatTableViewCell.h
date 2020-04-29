//
//  ChatTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 04.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

static CGFloat kChatCellStatusViewHeight     = 20.0;

typedef enum ChatMessageDeliveryState {
    ChatMessageDeliveryStateSent = 0,
    ChatMessageDeliveryStateSending,
    ChatMessageDeliveryStateFailed
} ChatMessageDeliveryState;

@interface ChatTableViewCell : UITableViewCell

@property (nonatomic, assign) NSInteger messageId;

@end
