/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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
