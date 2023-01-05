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

#import "NCChatTitleView.h"

#import "NCAppBranding.h"

@interface NCChatTitleView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation NCChatTitleView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [self commonInit];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        [self commonInit];
    }

    return self;
}

- (void)commonInit
{
    [[NSBundle mainBundle] loadNibNamed:@"NCChatTitleView" owner:self options:nil];

    [self addSubview:self.contentView];
    self.contentView.frame = self.bounds;

    self.image.layer.cornerRadius = 15.0f;
    self.image.clipsToBounds = YES;
    self.image.backgroundColor = [NCAppBranding avatarPlaceholderColor];

    self.title.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.title.titleLabel.minimumScaleFactor = 0.85;
    [self.title setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];

    [self.subtitle setTextColor:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.7]];
    [self.subtitle setHidden:YES];
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
        [_userStatusImage setImage:statusImage];
        _userStatusImage.contentMode = UIViewContentModeCenter;
        _userStatusImage.layer.cornerRadius = 6;
        _userStatusImage.clipsToBounds = YES;
        _userStatusImage.backgroundColor = [NCAppBranding themeColor];
    }
}

- (void)setUserStatusMessage:(NSString *)userStatusMessage withIcon:(NSString*)userStatusIcon
{
    if (userStatusMessage && ![userStatusMessage isEqualToString:@""]) {
        self.subtitle.text = userStatusMessage;
        if (userStatusIcon && ![userStatusIcon isEqualToString:@""]) {
            self.subtitle.text = [NSString stringWithFormat:@"%@ %@", userStatusIcon, userStatusMessage];
        }
        self.subtitle.hidden = NO;
    } else {
        self.subtitle.hidden = YES;
    }
}

@end
