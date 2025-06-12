/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ShareTableViewCell.h"

#import "AFNetworking.h"
#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

NSString *const kShareCellIdentifier = @"ShareCellIdentifier";
NSString *const kShareTableCellNibName = @"ShareTableViewCell";

CGFloat const kShareTableCellHeight = 56.0f;

@implementation ShareTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.avatarImageView.layer.cornerRadius = 18.0;
    self.avatarImageView.layer.masksToBounds = YES;
    self.avatarImageView.backgroundColor = [NCAppBranding placeholderColor];
    self.avatarImageView.contentMode = UIViewContentModeCenter;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.avatarImageView cancelCurrentRequest];
    self.avatarImageView.image = nil;

    self.titleLabel.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
