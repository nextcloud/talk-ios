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

    self.image.layer.cornerRadius = self.image.bounds.size.width / 2;
    self.image.clipsToBounds = YES;
    self.image.backgroundColor = [NCAppBranding avatarPlaceholderColor];

    [self.title setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];

    [self.subtitle setTextColor:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.7]];
    [self.subtitle setHidden:YES];
}

- (void)setupForRoom:(NCRoom *)room
{
    [self.title setTitle:room.displayName forState:UIControlStateNormal];

    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOne:
        {
            // Request user avatar to the server and set it if exist
            [self.image setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name
                                                                                                  withStyle:self.traitCollection.userInterfaceStyle
                                                                                                    andSize:96
                                                                                               usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                    placeholderImage:nil success:nil failure:nil];
        }
            break;
        case kNCRoomTypeGroup:
            [self.image setImage:[UIImage imageNamed:@"group-15"]];
            [self.image setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypePublic:
            [self.image setImage:[UIImage imageNamed:@"public-15"]];
            [self.image setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypeChangelog:
            [self.image setImage:[UIImage imageNamed:@"changelog"]];
            break;
        default:
            break;
    }

    // Set objectType image
    if ([room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [self.image setImage:[UIImage imageNamed:@"file-conv-15"]];
        [self.image setContentMode:UIViewContentModeCenter];
    } else if ([room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [self.image setImage:[UIImage imageNamed:@"pass-conv-15"]];
        [self.image setContentMode:UIViewContentModeCenter];
    }

    /*
     Disabled, until https://github.com/nextcloud/spreed/issues/8411 is fixed

        // User status
        [self setUserStatus:room.status];

        // User status message
        [self setUserStatusMessage:room.statusMessage withIcon:room.statusIcon];

        if (!room.statusMessage || [room.statusMessage isEqualToString:@""]) {
            if ([room.status isEqualToString:kUserStatusDND]) {
                [self setUserStatusMessage:NSLocalizedString(@"Do not disturb", nil) withIcon:nil];
            } else if ([room.status isEqualToString:kUserStatusAway]) {
                [self setUserStatusMessage:NSLocalizedString(@"Away", nil) withIcon:nil];
            }
        }
    */


    // Show description in group conversations
    if (room.type != kNCRoomTypeOneToOne && ![room.roomDescription isEqualToString:@""]) {
        [self setUserStatusMessage:room.roomDescription withIcon:nil];
    }
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
