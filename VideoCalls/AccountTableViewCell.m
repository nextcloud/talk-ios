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

#import "AccountTableViewCell.h"

NSString *const kAccountCellIdentifier          = @"AccountCellIdentifier";
NSString *const kAccountTableViewCellNibName    = @"AccountTableViewCell";

@implementation AccountTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.accountImageView.layer.cornerRadius = 15.0;
    self.accountImageView.layer.masksToBounds = YES;
    self.separatorInset = UIEdgeInsetsMake(0, 54, 0, 0);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.accountImageView.image = nil;
    self.accountNameLabel.text = @"";
    self.accountServerLabel.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
