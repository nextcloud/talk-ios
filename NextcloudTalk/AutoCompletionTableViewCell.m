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

#import "AutoCompletionTableViewCell.h"

#import "SLKUIConstants.h"

#import "NextcloudTalk-Swift.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"

@implementation AutoCompletionTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [NCAppBranding backgroundColor];
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    _avatarButton = [[AvatarButton alloc] initWithFrame:CGRectMake(0, 0, kChatCellAvatarHeight, kChatCellAvatarHeight)];
    _avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarButton.backgroundColor = [NCAppBranding placeholderColor];
    _avatarButton.layer.cornerRadius = kChatCellAvatarHeight/2.0;
    _avatarButton.layer.masksToBounds = YES;
    _avatarButton.showsMenuAsPrimaryAction = YES;
    _avatarButton.imageView.contentMode = UIViewContentModeScaleToFill;

    [self.contentView addSubview:_avatarButton];

    _userStatusImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];
    _userStatusImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _userStatusImageView.userInteractionEnabled = NO;
    [self.contentView addSubview:_userStatusImageView];
    
    [self.contentView addSubview:self.titleLabel];

    NSDictionary *views = @{
        @"avatarButton": self.avatarButton,
        @"userStatusImageView": self.userStatusImageView,
        @"titleLabel": self.titleLabel
    };

    NSDictionary *metrics = @{
        @"avatarSize": @(kChatCellAvatarHeight),
        @"right": @10
    };

    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarButton(avatarSize)]-right-[titleLabel]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[titleLabel]|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-32-[userStatusImageView(12)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-32-[userStatusImageView(12)]-(>=0)-|" options:0 metrics:metrics views:views]];
    self.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.titleLabel.textColor = [UIColor labelColor];

    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarButton(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [AutoCompletionTableViewCell defaultFontSize];

    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.titleLabel.text = @"";

    [self.avatarButton cancelCurrentRequest];
    [self.avatarButton setImage:nil forState:UIControlStateNormal];
    
    self.userStatusImageView.image = nil;
    self.userStatusImageView.backgroundColor = [UIColor clearColor];
}

#pragma mark - Getters

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.userInteractionEnabled = NO;
        _titleLabel.numberOfLines = 1;
        _titleLabel.font = [UIFont systemFontOfSize:[AutoCompletionTableViewCell defaultFontSize]];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _titleLabel;
}

- (void)setUserStatus:(NSString *)userStatus
{
    UIImage *statusImage = nil;
    if ([userStatus isEqualToString:@"online"]) {
        statusImage = [UIImage imageNamed:@"user-status-online-10"];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [UIImage imageNamed:@"user-status-away-10"];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [UIImage imageNamed:@"user-status-dnd-10"];
    }
    
    if (statusImage) {
        [_userStatusImageView setImage:statusImage];
        _userStatusImageView.contentMode = UIViewContentModeCenter;
        _userStatusImageView.layer.cornerRadius = 6;
        _userStatusImageView.clipsToBounds = YES;

        // When a background color is set directly to the cell it seems that there is no background configuration.
        // In this class, even when no background color is set, the background configuration is nil.
        _userStatusImageView.backgroundColor = (self.backgroundColor) ? self.backgroundColor : [[self backgroundConfiguration] backgroundColor];
    }
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
//    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
//    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}


@end
