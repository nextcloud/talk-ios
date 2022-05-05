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

#import "NCChatMessage.h"

static CGFloat kChatCellStatusViewHeight    = 20.0;
static CGFloat kChatCellDateLabelWidth      = 40.0;
static CGFloat kChatCellAvatarHeight        = 30.0;

typedef enum ChatMessageDeliveryState {
    ChatMessageDeliveryStateSent = 0,
    ChatMessageDeliveryStateRead,
    ChatMessageDeliveryStateSending,
    ChatMessageDeliveryStateDeleting,
    ChatMessageDeliveryStateFailed
} ChatMessageDeliveryState;

@protocol ChatTableViewCellDelegate <NSObject>

- (void)cellWantsToDisplayOptionsForMessageActor:(NCChatMessage *)message;
- (void)cellDidSelectedReaction:(NCChatReaction *)reaction forMessage:(NCChatMessage *)message;

@end

@interface ChatTableViewCell : UITableViewCell

@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NCChatMessage *message;

@end
