/**
 * @copyright Copyright (c) 2020 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
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

#import "BarButtonItemWithActivity.h"

#import "NCAppBranding.h"

@interface BarButtonItemWithActivity ()

@end

@implementation BarButtonItemWithActivity

- (instancetype)init {
    return [super init];
}

- (instancetype)initWithWidth:(CGFloat)buttonWidth withImage:(UIImage *)buttonImage {
    self = [self init];
    
    if (self) {
        UIColor *themeTextColor = [NCAppBranding themeTextColor];
        
        // Use UIButton as CustomView in UIBarButtonItem to have a fixed-size item
        self.innerButton = [[UIButton alloc] init];

        [self.innerButton setImage:buttonImage forState:UIControlStateNormal];
        self.innerButton.tintColor = themeTextColor;
        self.innerButton.frame = CGRectMake(0, 0, buttonWidth, buttonWidth);
        self.innerButton.tintColor = themeTextColor;
        
        // Make sure the size of UIBarButtonItem stays the same when displaying the ActivityIndicator
        self.activityIndicator = [[UIActivityIndicatorView alloc] init];
        self.activityIndicator.color = themeTextColor;
        self.activityIndicator.frame = CGRectMake(0, 0, buttonWidth, buttonWidth);
        
        [self setCustomView:self.innerButton];
    }
    
    return self;
}

- (void)showActivityIndicator
{
    [self.activityIndicator startAnimating];
    [self setCustomView:self.activityIndicator];
}

- (void)hideActivityIndicator
{
    [self setCustomView:self.innerButton];
    [self.activityIndicator stopAnimating];
    
}

@end
