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

#import "UIImageView+AFNetworking.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCUserStatus.h"

@interface NCChatTitleView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@property (strong, nonatomic) UIFont *titleFont;
@property (strong, nonatomic) UIFont *subtitleFont;

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

    self.avatarimage.layer.cornerRadius = self.avatarimage.bounds.size.width / 2;
    self.avatarimage.clipsToBounds = YES;
    self.avatarimage.backgroundColor = [NCAppBranding avatarPlaceholderColor];

    [self.titleButton setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];

    self.titleFont = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.subtitleFont = [UIFont systemFontOfSize:13];

    self.showSubtitle = YES;

    // Set empty title on init to prevent showing a placeholder on iPhones in landscape
    [self setTitle:@"" withSubtitle:nil];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.avatarimage.layer.cornerRadius = self.avatarimage.bounds.size.width / 2;
}

- (void)updateForRoom:(NCRoom *)room
{
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOne:
        {
            // Request user avatar to the server and set it if exist
            [self.avatarimage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name
                                                                                                        withStyle:self.traitCollection.userInterfaceStyle
                                                                                                          andSize:96
                                                                                                     usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                    placeholderImage:nil success:nil failure:nil];
        }
            break;
        case kNCRoomTypeGroup:
            [self.avatarimage setImage:[UIImage imageNamed:@"group-15"]];
            [self.avatarimage setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypePublic:
            [self.avatarimage setImage:[UIImage imageNamed:@"public-15"]];
            [self.avatarimage setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypeChangelog:
            [self.avatarimage setImage:[UIImage imageNamed:@"changelog"]];
            break;
        default:
            break;
    }

    // Set objectType image
    if ([room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [self.userStatusImage setImage:[UIImage imageNamed:@"file-conv-15"]];
        [self.userStatusImage setContentMode:UIViewContentModeCenter];
    } else if ([room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [self.userStatusImage setImage:[UIImage imageNamed:@"pass-conv-15"]];
        [self.userStatusImage setContentMode:UIViewContentModeCenter];
    }

    NSString *subtitle = nil;

    /*
     Disabled, until https://github.com/nextcloud/spreed/issues/8411 is fixed

        // User status
        [self setStatusImageForUserStatus:room.status];

        // User status message
        if (!room.statusMessage || [room.statusMessage isEqualToString:@""]) {
            // We don't have a dedicated statusMessage -> check the room status itself

            if ([room.status isEqualToString:kUserStatusDND]) {
                subtitle = NSLocalizedString(@"Do not disturb", nil);
            } else if ([room.status isEqualToString:kUserStatusAway]) {
                subtitle = NSLocalizedString(@"Away", nil);
            }
        } else if (room.statusMessage && ![room.statusMessage isEqualToString:@""]) {
            // A dedicated statusMessage was set -> use it

            if (room.statusIcon && ![room.statusIcon isEqualToString:@""]) {
                subtitle = [NSString stringWithFormat:@"%@ %@", room.statusIcon, room.statusMessage];
            } else {
                subtitle = room.statusMessage;
            }
        }
     */

    // Show description in group conversations
    if (room.type != kNCRoomTypeOneToOne && ![room.roomDescription isEqualToString:@""]) {
        subtitle = room.roomDescription;
    }

    [self setTitle:room.displayName withSubtitle:subtitle];
}

- (void)setStatusImageForUserStatus:(NSString *)userStatus
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

- (void)setTitle:(NSString *)title withSubtitle:(NSString *)subtitle
{
    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title];
    NSRange rangeTitle = NSMakeRange(0, [title length]);
    [attributedTitle addAttribute:NSFontAttributeName value:self.titleFont range:rangeTitle];

    if (self.showSubtitle && subtitle != nil) {
        NSMutableAttributedString *attributedSubtitle = [[NSMutableAttributedString alloc] initWithString:subtitle];
        NSRange rangeSubtitle = NSMakeRange(0, [subtitle length]);
        [attributedSubtitle addAttribute:NSFontAttributeName value:self.subtitleFont range:rangeSubtitle];

        [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [attributedTitle appendAttributedString:attributedSubtitle];

        [self.titleButton.titleLabel setNumberOfLines:2];
    } else {
        [self.titleButton.titleLabel setNumberOfLines:1];
    }

    [self.titleButton setAttributedTitle:attributedTitle forState:UIControlStateNormal];
}

@end
