//
//  ChatMessageTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ChatTableViewCell.h"

static CGFloat kChatMessageCellMinimumHeight    = 50.0;
static CGFloat kChatMessageCellAvatarHeight     = 30.0;

static NSString *ChatMessageCellIdentifier      = @"ChatMessageCellIdentifier";
static NSString *AutoCompletionCellIdentifier   = @"AutoCompletionCellIdentifier";

@interface ChatMessageTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UIImageView *avatarView;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;

@end
