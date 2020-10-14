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

#import "AvatarBackgroundImageView.h"

@implementation GradientView

@dynamic layer;

+ (Class)layerClass {
    return [CAGradientLayer class];
}

@end

@implementation AvatarBackgroundImageView

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initGradientLayer];
    }
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initGradientLayer];
    }
    
    return self;
}

- (instancetype)initWithImage:(UIImage *)image
{
    self = [super initWithImage:image];
    if (self) {
        [self initGradientLayer];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initGradientLayer];
    }
    
    return self;
}

- (void)initGradientLayer
{
    _gradientView = [[GradientView alloc] initWithFrame:self.bounds];
    _gradientView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gradientView.layer.colors = @[(id)[[UIColor colorWithWhite:0 alpha:0.6] CGColor], (id)[[UIColor colorWithWhite:0 alpha:0.6] CGColor]];
    _gradientView.layer.locations = @[@0.0, @1.0];
    [self addSubview:_gradientView];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
//    _gradientLayer.frame = self.bounds;
}

@end
