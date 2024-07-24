/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GradientView : UIView

@property (nonatomic, strong, readonly) CAGradientLayer *layer;

@end

@interface AvatarBackgroundImageView : UIImageView

@property (nonatomic, strong)  GradientView *gradientView;

@end

NS_ASSUME_NONNULL_END
