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

#import "HeaderWithButton.h"

@interface HeaderWithButton ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation HeaderWithButton

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"HeaderWithButton" owner:self options:nil];

        _label.textColor = [UIColor secondaryLabelColor];
        
        [self addSubview:self.contentView];
        
        if ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:_label.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft) {
            _label.textAlignment = NSTextAlignmentRight;
            _button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        } else {
            _label.textAlignment = NSTextAlignmentLeft;
            _button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        }
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
