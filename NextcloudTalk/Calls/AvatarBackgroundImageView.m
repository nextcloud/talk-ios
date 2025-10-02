/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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
