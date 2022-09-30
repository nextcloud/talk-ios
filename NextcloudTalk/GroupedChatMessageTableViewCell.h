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

#import "NextcloudTalk-Swift.h"

#import "ChatTableViewCell.h"
#import "NCChatMessage.h"
#import "MessageBodyTextView.h"

static CGFloat kGroupedChatMessageCellMinimumHeight = 30.0;
static NSString *GroupedChatMessageCellIdentifier = @"GroupedChatMessageCellIdentifier";

@interface GroupedChatMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<ChatTableViewCellDelegate> delegate;

@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vConstraint;
@property (nonatomic, strong) ReferenceView *referenceView;

+ (CGFloat)defaultFontSize;
- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;

@end
