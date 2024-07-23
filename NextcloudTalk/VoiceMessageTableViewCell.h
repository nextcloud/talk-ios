/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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

@class AvatarButton;
@class ReactionsView;
@protocol ReactionsViewDelegate;

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
@property (nonatomic, strong) AvatarButton *avatarButton;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UIView *fileStatusView;
@property (nonatomic, strong) NCMessageFileParameter *fileParameter;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vGroupedConstraints;

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;
- (void)setPlayerProgress:(CGFloat)progress isPlaying:(BOOL)playing maximumValue:(CGFloat)maxValue;
- (void)resetPlayer;

@end
