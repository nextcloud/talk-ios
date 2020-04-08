//
//  FileMessageTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 29.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ChatTableViewCell.h"
#import "MessageBodyTextView.h"

static CGFloat kFileMessageCellMinimumHeight        = 50.0;
static CGFloat kFileMessageCellAvatarHeight         = 30.0;
static CGFloat kFileMessageCellFilePreviewHeight    = 120.0;

static NSString *FileMessageCellIdentifier          = @"FileMessageCellIdentifier";
static NSString *GroupedFileMessageCellIdentifier   = @"GroupedFileMessageCellIdentifier";

@interface FilePreviewImageView : UIImageView
@end

@interface FileMessageTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) FilePreviewImageView *previewImageView;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSString *fileLink;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) UIView *statusView;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setDeliveryState:(ChatMessageDeliveryState)state;

@end
