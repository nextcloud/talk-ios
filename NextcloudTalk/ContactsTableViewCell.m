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

#import "ContactsTableViewCell.h"

#import "UIImageView+AFNetworking.h"

#import "NCAppBranding.h"

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
    self.contactImage.contentMode = UIViewContentModeCenter;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.contactImage cancelImageDownloadTask];
    self.contactImage.image = nil;
    self.contactImage.contentMode = UIViewContentModeCenter;
    
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
        statusImage = [UIImage imageNamed:@"user-status-online"];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [UIImage imageNamed:@"user-status-away"];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [UIImage imageNamed:@"user-status-dnd"];
    }
    
    if (statusImage) {
        [_userStatusImageView setImage:statusImage];
        _userStatusImageView.contentMode = UIViewContentModeCenter;
        _userStatusImageView.layer.cornerRadius = 10;
        _userStatusImageView.clipsToBounds = YES;

        // When a background color is set directly to the cell it seems that there is no background configuration.
        _userStatusImageView.backgroundColor = (self.backgroundColor) ? self.backgroundColor : [[self backgroundConfiguration] backgroundColor];
    }
}

- (void)setUserStatusMessage:(NSString *)userStatusMessage withIcon:(NSString*)userStatusIcon
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
