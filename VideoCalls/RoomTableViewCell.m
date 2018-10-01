//
//  RoomTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomTableViewCell.h"
#import "UIImageView+AFNetworking.h"

#define kTitleOriginY       14
#define kTitleOnlyOriginY   25

NSString *const kRoomCellIdentifier = @"RoomCellIdentifier";
NSString *const kRoomTableCellNibName = @"RoomTableViewCell";

@implementation RoomTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.roomImage.layer.cornerRadius = 24.0;
    self.roomImage.layer.masksToBounds = YES;
    self.favoriteImage.contentMode = UIViewContentModeCenter;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.roomImage cancelImageDownloadTask];
    
    self.roomImage.image = nil;
    self.favoriteImage.image = nil;
    self.subtitleLabel.text = @"";
    self.dateLabel.text = @"";

    for (UIView *subview in [self.unreadMessagesView subviews]) {
        [subview removeFromSuperview];
    }
}

- (void)setTitleOnly:(BOOL)titleOnly
{
    _titleOnly = titleOnly;
    
    CGRect frame = self.titleLabel.frame;
    frame.origin.y = _titleOnly ? kTitleOnlyOriginY : kTitleOriginY;
    self.titleLabel.frame = frame;
}

@end
