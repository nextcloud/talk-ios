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
#import "NCMessageFileParameter.h"
#import "NCChatMessage.h"

static CGFloat kFileMessageCellMinimumHeight                = 50.0;
static CGFloat kFileMessageCellFileMaxPreviewHeight         = 120.0;
static CGFloat kFileMessageCellFileMaxPreviewWidth          = 230.0;
static CGFloat kFileMessageCellMediaFilePreviewHeight       = 230.0;
static CGFloat kFileMessageCellMediaFileMaxPreviewWidth     = 230.0;
static CGFloat kFileMessageCellFilePreviewCornerRadius      = 4.0;
static CGFloat kFileMessageCellVideoPlayIconSize            = 48.0;

static NSString *FileMessageCellIdentifier          = @"FileMessageCellIdentifier";
static NSString *GroupedFileMessageCellIdentifier   = @"GroupedFileMessageCellIdentifier";

@interface FilePreviewImageView : UIImageView
@end

@class FileMessageTableViewCell;

@protocol FileMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToDownloadFile:(NCMessageFileParameter *)fileParameter;
- (void)cellHasDownloadedImagePreviewWithHeight:(CGFloat)height forMessage:(NCChatMessage *)message;

@end

@interface FileMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<FileMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) FilePreviewImageView *previewImageView;
@property (nonatomic, strong) UIImageView *playIconImageView;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UIView *fileStatusView;
@property (nonatomic, strong) UIStackView *statusStackView;
@property (nonatomic, strong) NCMessageFileParameter *fileParameter;

@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vPreviewSize;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *hPreviewSize;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vGroupedPreviewSize;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *hGroupedPreviewSize;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;

@end
