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
#import "ChatTableViewCell.h"
#import "MessageBodyTextView.h"

static CGFloat kFileMessageCellMinimumHeight        = 50.0;
static CGFloat kFileMessageCellAvatarHeight         = 30.0;
static CGFloat kFileMessageCellFilePreviewHeight    = 120.0;

static NSString *FileMessageCellIdentifier          = @"FileMessageCellIdentifier";
static NSString *GroupedFileMessageCellIdentifier   = @"GroupedFileMessageCellIdentifier";

@interface FilePreviewImageView : UIImageView
@end

@interface FileMessageTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) FilePreviewImageView *previewImageView;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSString *fileLink;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) UIView *statusView;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setDeliveryState:(ChatMessageDeliveryState)state;

@end
