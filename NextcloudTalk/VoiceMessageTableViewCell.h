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

static CGFloat kVoiceMessageCellMinimumHeight        = 50.0;
static CGFloat kVoiceMessageCellPlayerHeight         = 44.0;

static NSString *VoiceMessageCellIdentifier          = @"VoiceMessageCellIdentifier";
static NSString *GroupedVoiceMessageCellIdentifier   = @"GroupedVoiceMessageCellIdentifier";

@protocol VoiceMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToPlayAudioFile:(NCMessageFileParameter *)fileParameter;
- (void)cellWantsToPauseAudioFile:(NCMessageFileParameter *)fileParameter;
- (void)cellWantsToChangeProgress:(CGFloat)progress fromAudioFile:(NCMessageFileParameter *)fileParameter;

@end

@interface VoiceMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<VoiceMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UIView *fileStatusView;
@property (nonatomic, strong) NCMessageFileParameter *fileParameter;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vGroupedConstraints;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;
- (void)setPlayerProgress:(CGFloat)progress isPlaying:(BOOL)playing maximumValue:(CGFloat)maxValue;
- (void)resetPlayer;

@end
