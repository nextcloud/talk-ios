/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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

    self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
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
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _titleLabel;
}

- (void)setUserStatus:(NSString *)userStatus
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
        [_userStatusImageView setImage:statusImage];
        _userStatusImageView.contentMode = UIViewContentModeCenter;
        _userStatusImageView.layer.cornerRadius = 6;
        _userStatusImageView.clipsToBounds = YES;

        // When a background color is set directly to the cell it seems that there is no background configuration.
        // In this class, even when no background color is set, the background configuration is nil.
        _userStatusImageView.backgroundColor = (self.backgroundColor) ? self.backgroundColor : [[self backgroundConfiguration] backgroundColor];
    }
}

@end
