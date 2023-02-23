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

    self.titleTextView.textContainer.lineFragmentPadding = 0;
    self.titleTextView.textContainerInset = UIEdgeInsetsZero;

    self.titleFont = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.subtitleFont = [UIFont systemFontOfSize:13];

    self.showSubtitle = YES;
    self.titleTextColor = [NCAppBranding themeTextColor];
    self.userStatusBackgroundColor = [NCAppBranding themeColor];

    // Set empty title on init to prevent showing a placeholder on iPhones in landscape
    [self setTitle:@"" withSubtitle:nil];

    // Use a LongPressGestureRecognizer here to get a "TouchDown" event
    UILongPressGestureRecognizer *longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlGestureRecognizer:)];
    longPressGestureRecognizer.minimumPressDuration = 0.0;
    [self.contentView addGestureRecognizer:longPressGestureRecognizer];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.avatarimage.layer.cornerRadius = self.avatarimage.bounds.size.width / 2;
    self.userStatusImage.layer.cornerRadius = self.userStatusImage.bounds.size.width / 2;
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
        case kNCRoomTypeFormerOneToOne:
            [self.avatarimage setImage:[UIImage imageNamed:@"user-15"]];
            [self.avatarimage setContentMode:UIViewContentModeCenter];
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
    
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySingleConvStatus]) {
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
    }

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
        _userStatusImage.clipsToBounds = YES;
        _userStatusImage.backgroundColor = _userStatusBackgroundColor;
    }
}

- (void)setTitle:(NSString *)title withSubtitle:(NSString *)subtitle
{
    if (!title) {
        return;
    }

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title];
    NSRange rangeTitle = NSMakeRange(0, [title length]);
    [attributedTitle addAttribute:NSFontAttributeName value:self.titleFont range:rangeTitle];
    [attributedTitle addAttribute:NSForegroundColorAttributeName value:self.titleTextColor range:rangeTitle];
    [attributedTitle addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:rangeTitle];

    if (self.showSubtitle && subtitle != nil) {
        NSMutableAttributedString *attributedSubtitle = [[NSMutableAttributedString alloc] initWithString:subtitle];
        NSRange rangeSubtitle = NSMakeRange(0, [subtitle length]);
        [attributedSubtitle addAttribute:NSFontAttributeName value:self.subtitleFont range:rangeSubtitle];
        [attributedSubtitle addAttribute:NSForegroundColorAttributeName value:self.titleTextColor range:rangeSubtitle];
        [attributedSubtitle addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:rangeSubtitle];

        [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [attributedTitle appendAttributedString:attributedSubtitle];

        [self.titleTextView.textContainer setMaximumNumberOfLines:2];
    } else {
        [self.titleTextView.textContainer setMaximumNumberOfLines:1];
    }

    [self.titleTextView setAttributedText:attributedTitle];
}

-(void)handlGestureRecognizer:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        // Simulate a pressed stated. Don't use self.alpha here as it will interfere with NavigationController transitions
        self.titleTextView.alpha = 0.7;
        self.avatarimage.alpha = 0.7;
        self.userStatusImage.alpha = 0.7;
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        // Call delegate & reset the pressed state -> use dispatch after to give the UI time to show the actual pressed state
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.titleTextView.alpha = 1.0;
            self.avatarimage.alpha = 1.0;
            self.userStatusImage.alpha = 1.0;
            
            [self.delegate chatTitleViewTapped:self];
        });

    }
}

@end
