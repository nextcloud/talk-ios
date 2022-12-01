/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <UIKit/UIKit.h>

extern NSString *const kRoomCellIdentifier;
extern NSString *const kRoomTableCellNibName;

extern CGFloat const kRoomTableCellHeight;

@interface RoomTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView *roomImage;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UILabel *subtitleLabel;
@property (nonatomic, weak) IBOutlet UIView *unreadMessagesView;
@property (nonatomic, weak) IBOutlet UILabel *dateLabel;
@property (weak, nonatomic) IBOutlet UIImageView *favoriteImage;
@property (weak, nonatomic) IBOutlet UIImageView *userStatusImageView;
@property (weak, nonatomic) IBOutlet UILabel *userStatusLabel;

@property (nonatomic, assign) BOOL titleOnly;
@property NSString *roomToken;

- (void)setUnreadMessages:(NSInteger)number mentioned:(BOOL)mentioned groupMentioned:(BOOL)groupMentioned;
- (void)setUserStatus:(NSString *)userStatus;
- (void)setUserStatusIcon:(NSString *)userStatusIcon;
@end
