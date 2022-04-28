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

#import "PlaceholderView.h"

#import "NCAppBranding.h"

@interface PlaceholderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation PlaceholderView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"PlaceholderView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

- (instancetype)initForTableViewStyle:(UITableViewStyle)style
{
    self = [self init];
    
    if (self && style == UITableViewStyleGrouped) {
        self.contentView.backgroundColor = [UIColor groupTableViewBackgroundColor];
        self.placeholderView.backgroundColor = [UIColor groupTableViewBackgroundColor];
    }
    
    return self;
}

- (void)setImage:(UIImage *)image
{
    UIImage *placeholderImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.placeholderImage setImage:placeholderImage];
    [self.placeholderImage setTintColor:[NCAppBranding placeholderColor]];
}

@end
