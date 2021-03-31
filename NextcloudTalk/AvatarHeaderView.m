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

#import "AvatarHeaderView.h"

@interface AvatarHeaderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation AvatarHeaderView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"AvatarHeaderView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.editButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.editButton.titleLabel.minimumScaleFactor = 0.9f;
        self.editButton.titleLabel.numberOfLines = 1;
        self.editButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
