/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCChatTitleView.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCUserStatus.h"

#import "NextcloudTalk-Swift.h"

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
    self.avatarimage.backgroundColor = [UIColor systemGray3Color];

    self.titleTextView.textContainer.lineFragmentPadding = 0;
    self.titleTextView.textContainerInset = UIEdgeInsetsZero;

    self.titleFont = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.subtitleFont = [UIFont systemFontOfSize:13];

    self.showSubtitle = YES;

    if (@available(iOS 26.0, *)) {
        self.userStatusBackgroundColor = [UIColor clearColor];
        self.titleTextColor = [UIColor labelColor];
    } else {
        self.userStatusBackgroundColor = [NCAppBranding themeColor];
        self.titleTextColor = [NCAppBranding themeTextColor];
    }

    // Set empty title on init to prevent showing a placeholder on iPhones in landscape
    [self setTitle:@"" withSubtitle:nil];

    // Use a LongPressGestureRecognizer here to get a "TouchDown" event
    self.longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlGestureRecognizer:)];
    self.longPressGestureRecognizer.minimumPressDuration = 0.0;
    [self.contentView addGestureRecognizer:self.longPressGestureRecognizer];
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
    [self.avatarimage setAvatarFor:room];

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

- (void)updateForThread:(NCThread *)thread
{
    // Set thread image
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:thread.accountId];
    [self.avatarimage setThreadAvatarForThread:thread];

    // Set thread title and number of replies
    NSString *repliesString = [NSString localizedStringWithFormat:NSLocalizedString(@"%ld replies", @"Replies in a thread"), (long)thread.numReplies];
    [self setTitle:thread.title withSubtitle:repliesString];
}

- (void)setStatusImageForUserStatus:(NSString *)userStatus
{
    UIImage *statusImage = nil;
    if ([userStatus isEqualToString:@"online"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getOnlineSFIcon] ofSize:CGSizeMake(10, 10) centerImage:NO];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getAwaySFIcon] ofSize:CGSizeMake(10, 10) centerImage:NO];
    } else if ([userStatus isEqualToString:@"busy"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getBusySFIcon] ofSize:CGSizeMake(10, 10) centerImage:NO];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getDoNotDisturbSFIcon] ofSize:CGSizeMake(10, 10) centerImage:NO];
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
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:subtitle];
        NSMutableAttributedString *attributedSubtitle = [SwiftMarkdownObjCBridge parseMarkdownWithMarkdownString:attributedString];
        NSRange rangeSubtitle = NSMakeRange(0, [attributedSubtitle length]);
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
