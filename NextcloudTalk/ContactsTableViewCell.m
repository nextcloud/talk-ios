/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ContactsTableViewCell.h"
#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

NSString *const kContactCellIdentifier = @"ContactCellIdentifier";
NSString *const kContactsTableCellNibName = @"ContactsTableViewCell";

CGFloat const kContactsTableCellHeight = 72.0f;
CGFloat const kContactsTableCellTitleFontSize = 17.0f;

@implementation ContactsTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.contactImage.layer.cornerRadius = 24.0;
    self.contactImage.layer.masksToBounds = YES;
    self.contactImage.backgroundColor = [NCAppBranding placeholderColor];
    self.contactImage.contentMode = UIViewContentModeScaleToFill;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.contactImage cancelCurrentRequest];
    self.contactImage.image = nil;
    
    self.userStatusImageView.image = nil;
    self.userStatusImageView.backgroundColor = [UIColor clearColor];
    
    self.userStatusMessageLabel.text = @"";
    self.userStatusMessageLabel.hidden = YES;
    
    self.labelTitle.text = @"";
    self.labelTitle.textColor = [UIColor labelColor];
    
    self.labelTitle.font = [UIFont systemFontOfSize:kContactsTableCellTitleFontSize weight:UIFontWeightRegular];
}

- (void)setUserStatus:(NSString *)userStatus
{
    UIImage *statusImage = nil;
    if ([userStatus isEqualToString:@"online"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getOnlineSFIcon] ofSize:CGSizeMake(16, 16) centerImage:NO];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getAwaySFIcon] ofSize:CGSizeMake(16, 16) centerImage:NO];
    } else if ([userStatus isEqualToString:@"busy"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getBusySFIcon] ofSize:CGSizeMake(16, 16) centerImage:NO];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [NCUtils renderAspectImageWithImage:[NCUserStatus getDoNotDisturbSFIcon] ofSize:CGSizeMake(16, 16) centerImage:NO];
    }

    if (statusImage) {
        [self setUserStatusIconWithImage:statusImage];
    }
}

- (void)setUserStatusIconWithImage:(UIImage *)image
{
    [_userStatusImageView setImage:image];
    _userStatusImageView.contentMode = UIViewContentModeCenter;
    _userStatusImageView.layer.cornerRadius = 10;
    _userStatusImageView.clipsToBounds = YES;

    // When a background color is set directly to the cell it seems that there is no background configuration.
    _userStatusImageView.backgroundColor = (self.backgroundColor) ? self.backgroundColor : [[self backgroundConfiguration] backgroundColor];
}

- (void)setUserStatusMessage:(NSString *)userStatusMessage withIcon:(NSString *)userStatusIcon
{
    if (userStatusMessage && ![userStatusMessage isEqualToString:@""]) {
        self.userStatusMessageLabel.text = userStatusMessage;
        if (userStatusIcon && ![userStatusIcon isEqualToString:@""]) {
            self.userStatusMessageLabel.text = [NSString stringWithFormat:@"%@ %@", userStatusIcon, userStatusMessage];
        }
        self.userStatusMessageLabel.hidden = NO;
    } else {
        self.userStatusMessageLabel.hidden = YES;
    }
}

@end
