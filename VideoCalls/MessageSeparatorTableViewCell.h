//
//  MessageSeparatorTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 05.09.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "ChatTableViewCell.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat kMessageSeparatorCellHeight          = 24.0;
static NSInteger kUnreadMessagesSeparatorIdentifier = -99;
static NSInteger kChatBlockSeparatorIdentifier      = -98;
static NSString *MessageSeparatorCellIdentifier     = @"MessageSeparatorCellIdentifier";

@interface MessageSeparatorTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *separatorLabel;

@end

NS_ASSUME_NONNULL_END
