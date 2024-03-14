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

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRoomDescriptionCellIdentifier;
extern NSString *const kRoomDescriptionTableCellNibName;

@class RoomDescriptionTableViewCell;

@protocol RoomDescriptionTableViewCellDelegate <NSObject>
@optional
- (void)roomDescriptionCellTextViewDidChange:(RoomDescriptionTableViewCell *)cell;
- (void)roomDescriptionCellDidConfirmChanges:(RoomDescriptionTableViewCell *)cell;
- (void)roomDescriptionCellDidExceedLimit:(RoomDescriptionTableViewCell *)cell;
- (void)roomDescriptionCellDidEndEditing:(RoomDescriptionTableViewCell *)cell;
@end

@interface RoomDescriptionTableViewCell : UITableViewCell

@property (nonatomic, weak) id<RoomDescriptionTableViewCellDelegate> delegate;
@property (nonatomic, assign) NSInteger characterLimit;
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

NS_ASSUME_NONNULL_END
