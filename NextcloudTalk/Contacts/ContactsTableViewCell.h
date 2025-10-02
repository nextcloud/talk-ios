/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@class AvatarImageView;

extern NSString *const kContactCellIdentifier;
extern NSString *const kContactsTableCellNibName;

extern CGFloat const kContactsTableCellHeight;
extern CGFloat const kContactsTableCellTitleFontSize;

@interface ContactsTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet AvatarImageView *contactImage;
@property(nonatomic, weak) IBOutlet UILabel *labelTitle;
@property (weak, nonatomic) IBOutlet UIImageView *userStatusImageView;
@property (weak, nonatomic) IBOutlet UILabel *userStatusMessageLabel;

- (void)setUserStatus:(NSString *)userStatus;
- (void)setUserStatusMessage:(NSString * _Nullable)userStatusMessage withIcon:(NSString * _Nullable)userStatusIcon;
- (void)setUserStatusIconWithImage:(UIImage * _Nullable)image;

@end
