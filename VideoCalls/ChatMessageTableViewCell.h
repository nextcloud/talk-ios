//
//  ChatMessageTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

static CGFloat kChatMessageCellMinimumHeight = 50.0;
static CGFloat kChatMessageCellAvatarHeight = 30.0;

static NSString *ChatMessageCellIdentifier = @"ChatMessageCellIdentifier";

@interface ChatMessageTableViewCell : UITableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UIImageView *avatarView;

@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic) BOOL usedForMessage;

+ (CGFloat)defaultFontSize;

@end
