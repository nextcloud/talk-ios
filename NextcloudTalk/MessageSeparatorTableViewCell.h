/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "ChatTableViewCell.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat kMessageSeparatorCellHeight          = 24.0;
static NSInteger kUnreadMessagesSeparatorIdentifier = -99;
static NSInteger kChatBlockSeparatorIdentifier      = -98;
static NSString *MessageSeparatorCellIdentifier     = @"MessageSeparatorCellIdentifier";

@interface MessageSeparatorTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *separatorLabel;

@end

NS_ASSUME_NONNULL_END
