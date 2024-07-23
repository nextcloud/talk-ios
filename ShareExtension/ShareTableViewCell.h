/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@class AvatarImageView;

extern NSString *const kShareCellIdentifier;
extern NSString *const kShareTableCellNibName;

extern CGFloat const kShareTableCellHeight;

@interface ShareTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet AvatarImageView *avatarImageView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@end
