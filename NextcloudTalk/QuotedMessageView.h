/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@class AvatarImageView;

NS_ASSUME_NONNULL_BEGIN

@interface QuotedMessageView : UIView

@property (nonatomic, strong) UILabel *actorLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, assign) BOOL highlighted;
@property (nonatomic, strong) AvatarImageView *avatarView;

@end

NS_ASSUME_NONNULL_END
