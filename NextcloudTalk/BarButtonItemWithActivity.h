/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@interface BarButtonItemWithActivity : UIBarButtonItem

@property (nonatomic, strong) UIButton * _Nonnull innerButton;
@property (nonatomic, strong) UIActivityIndicatorView * _Nonnull activityIndicator;

- (nonnull instancetype)initWithWidth:(CGFloat)buttonWidth withImage:(UIImage * _Nullable)buttonImage;
- (void)showActivityIndicator;
- (void)hideActivityIndicator;

@end

