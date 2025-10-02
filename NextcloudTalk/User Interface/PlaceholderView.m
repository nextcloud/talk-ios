/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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
    
    if (self && (style == UITableViewStyleGrouped || style == UITableViewStyleInsetGrouped )) {
        self.contentView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.placeholderView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    
    return self;
}

- (void)setImage:(UIImage *)image
{
    UIImage *placeholderImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.placeholderImage setImage:placeholderImage];
    [self.placeholderImage setContentMode:UIViewContentModeScaleAspectFit];
    [self.placeholderImage setTintColor:[NCAppBranding placeholderColor]];
}

@end
