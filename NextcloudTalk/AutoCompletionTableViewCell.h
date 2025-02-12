/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "SystemMessageTableViewCell.h"

static CGFloat kAutoCompletionCellHeight        = 50.0;

static NSString *AutoCompletionCellIdentifier   = @"AutoCompletionCellIdentifier";

@class AvatarButton;

@interface AutoCompletionTableViewCell : UITableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) AvatarButton *avatarButton;
@property (nonatomic, strong) UIImageView *userStatusImageView;

- (void)setUserStatus:(NSString *)userStatus;

@end
