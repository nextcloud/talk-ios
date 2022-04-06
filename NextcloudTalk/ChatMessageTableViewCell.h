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
#import "NCChatMessage.h"
#import "MessageBodyTextView.h"

static CGFloat kChatMessageCellMinimumHeight    = 50.0;

static NSString *ChatMessageCellIdentifier      = @"ChatMessageCellIdentifier";
static NSString *ReplyMessageCellIdentifier     = @"ReplyMessageCellIdentifier";
static NSString *AutoCompletionCellIdentifier   = @"AutoCompletionCellIdentifier";

@class QuotedMessageView;

@class ChatMessageTableViewCell;

@protocol ChatMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToScrollToMessage:(NCChatMessage *)message;

@end

@interface ChatMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<ChatMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) QuotedMessageView *quotedMessageView;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UIImageView *userStatusImageView;

+ (CGFloat)defaultFontSize;
- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setBotAvatar;
- (void)setChangelogAvatar;
- (void)setUserStatus:(NSString *)userStatus;

@end
