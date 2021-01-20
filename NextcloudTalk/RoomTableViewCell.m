/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "RoomTableViewCell.h"
#import "RoundedNumberView.h"
#import "UIImageView+AFNetworking.h"
#import "NCAppBranding.h"

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
    self.roomImage.backgroundColor = [NCAppBranding placeholderColor];
    self.roomImage.contentMode = UIViewContentModeCenter;
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
    self.roomImage.contentMode = UIViewContentModeCenter;
    self.favoriteImage.image = nil;
    self.subtitleLabel.text = @"";
    self.dateLabel.text = @"";
    
    self.userStatusImageView.image = nil;
    self.userStatusImageView.backgroundColor = [UIColor clearColor];
    
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

- (void)setUserStatus:(NSString *)userStatus
{
    UIImage *statusImage = nil;
    if ([userStatus isEqualToString:@"online"]) {
        statusImage = [UIImage imageNamed:@"user-status-online"];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [UIImage imageNamed:@"user-status-away"];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [UIImage imageNamed:@"user-status-dnd"];
    }
    
    if (statusImage) {
        [_userStatusImageView setImage:statusImage];
        _userStatusImageView.contentMode = UIViewContentModeCenter;
        _userStatusImageView.layer.cornerRadius = 10;
        _userStatusImageView.clipsToBounds = YES;
        _userStatusImageView.backgroundColor = self.backgroundColor;
    }
}

@end
