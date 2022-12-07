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

#import "ShareTableViewCell.h"

#import "AFNetworking.h"
#import "AFImageDownloader.h"
#import "NCAppBranding.h"
#import "NCAvatarSessionManager.h"
#import "UIImageView+AFNetworking.h"

NSString *const kShareCellIdentifier = @"ShareCellIdentifier";
NSString *const kShareTableCellNibName = @"ShareTableViewCell";

CGFloat const kShareTableCellHeight = 56.0f;

@implementation ShareAvatarImageView : UIImageView
@end

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
    [self.avatarImageView cancelImageDownloadTask];
    self.avatarImageView.image = nil;
    self.avatarImageView.contentMode = UIViewContentModeCenter;
    
    self.avatarImageView.image = nil;
    self.titleLabel.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
