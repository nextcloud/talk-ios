/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ShareViewController;
@class NCChatMessage;
@protocol ShareViewControllerDelegate <NSObject>

- (void)shareViewControllerDidCancel:(ShareViewController *)viewController;

@end

@interface ShareViewController : UITableViewController

@property (weak, nonatomic) id<ShareViewControllerDelegate> delegate;

@property (strong, nonatomic) UIViewController *chatViewController;
@property (strong, nonatomic) NSString *forwardMessage;
@property (strong, nonatomic) NCChatMessage *forwardObjectShareMessage;
@property (assign, nonatomic) BOOL forwarding;

- (id)initToForwardMessage:(NSString *)message fromChatViewController:(UIViewController *)chatViewController;
- (id)initToForwardObjectShareMessage:(NCChatMessage *)objectShareMessage fromChatViewController:(UIViewController *)chatViewController;

@end

NS_ASSUME_NONNULL_END
