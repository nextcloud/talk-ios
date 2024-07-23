/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@interface PlaceholderView : UIView

- (instancetype)initForTableViewStyle:(UITableViewStyle)style;

@property (weak, nonatomic) IBOutlet UIView *placeholderView;
@property (weak, nonatomic) IBOutlet UIImageView *placeholderImage;
@property (weak, nonatomic) IBOutlet UITextView *placeholderTextView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

- (void)setImage:(UIImage *)image;

@end
