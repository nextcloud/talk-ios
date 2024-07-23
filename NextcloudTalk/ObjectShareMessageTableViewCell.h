/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import "ChatTableViewCell.h"
#import "NCChatMessage.h"

static CGFloat kObjectShareMessageCellMinimumHeight         = 50.0;
static CGFloat kObjectShareMessageCellObjectTypeImageSize   = 24.0;

static NSString *ObjectShareMessageCellIdentifier           = @"ObjectShareMessageCellIdentifier";
static NSString *GroupedObjectShareMessageCellIdentifier    = @"GroupedObjectShareMessageCellIdentifier";

@class AvatarButton;
@class ObjectShareMessageTableViewCell;
@class ReactionsView;
@protocol ReactionsViewDelegate;

@protocol ObjectShareMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToOpenPoll:(NCMessageParameter *)poll;

@end

@interface ObjectShareMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<ObjectShareMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *objectContainerView;
@property (nonatomic, strong) UIImageView *objectTypeImageView;
@property (nonatomic, strong) UITextView *objectTitle;
@property (nonatomic, strong) AvatarButton *avatarButton;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) NCMessageParameter *objectParameter;
@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vGroupedConstraints;

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;

@end
