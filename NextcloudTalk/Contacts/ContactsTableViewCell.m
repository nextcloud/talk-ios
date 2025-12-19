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

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.avatarView prepareForReuse];

    self.userStatusMessageLabel.text = @"";
    self.userStatusMessageLabel.hidden = YES;
    
    self.labelTitle.text = @"";
    self.labelTitle.textColor = [UIColor labelColor];
    
    self.labelTitle.font = [UIFont systemFontOfSize:kContactsTableCellTitleFontSize weight:UIFontWeightRegular];
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
