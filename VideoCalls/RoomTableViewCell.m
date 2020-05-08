//
//  RoomTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomTableViewCell.h"
#import "RoundedNumberView.h"
#import "UIImageView+AFNetworking.h"

#define kTitleOriginY       12
#define kTitleOnlyOriginY   28

NSString *const kRoomCellIdentifier = @"RoomCellIdentifier";
NSString *const kRoomTableCellNibName = @"RoomTableViewCell";

CGFloat const kRoomTableCellHeight = 74.0f;

@interface RoomTableViewCell ()
{
    RoundedNumberView *_unreadMessagesBadge;
    NSInteger _unreadMessages;
    BOOL _metioned;
}
@end

@implementation RoomTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.roomImage.layer.cornerRadius = 24.0;
    self.roomImage.layer.masksToBounds = YES;
    self.favoriteImage.contentMode = UIViewContentModeCenter;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    if (!_unreadMessagesBadge) {
        _unreadMessagesBadge = [[RoundedNumberView alloc] init];
        _unreadMessagesBadge.important = _metioned;
        _unreadMessagesBadge.number = _unreadMessages;
        _unreadMessagesBadge.frame = CGRectMake(self.unreadMessagesView.frame.size.width - _unreadMessagesBadge.frame.size.width,
                                                _unreadMessagesBadge.frame.origin.y,
                                                _unreadMessagesBadge.frame.size.width, _unreadMessagesBadge.frame.size.height);
        
        [self.unreadMessagesView addSubview:_unreadMessagesBadge];
    }
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
    
    _unreadMessagesBadge = nil;
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

- (void)setUnreadMessages:(NSInteger)number mentioned:(BOOL)mentioned
{
    _unreadMessages = number;
    _metioned = mentioned;
    if (number > 0) {
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _unreadMessagesView.hidden = NO;
    } else {
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        _subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        _dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _unreadMessagesView.hidden = YES;
    }
}

@end
