/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "NCRoom.h"

@class AvatarImageView;
@class NCChatTitleView;
@class NCThread;

@protocol NCChatTitleViewDelegate <NSObject>

- (void)chatTitleViewTapped:(NCChatTitleView *)titleView;

@end

@interface NCChatTitleView : UIView

@property (nonatomic, weak) id<NCChatTitleViewDelegate> delegate;
@property (weak, nonatomic) IBOutlet UITextView *titleTextView;
@property (weak, nonatomic) IBOutlet AvatarImageView *avatarimage;
@property (weak, nonatomic) IBOutlet UIImageView *userStatusImage;
@property (assign, nonatomic) BOOL showSubtitle;
@property (strong, nonatomic) UIColor *titleTextColor;
@property (strong, nonatomic) UIColor *userStatusBackgroundColor;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPressGestureRecognizer;

- (void)updateForRoom:(NCRoom *)room;
- (void)updateForThread:(NCThread *)thread;

@end
