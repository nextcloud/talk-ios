/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import "NCRoom.h"

@class ChatViewController;

@interface RoomInfoTableViewController : UITableViewController

@property (nonatomic, assign) BOOL hideDestructiveActions;

- (instancetype)initForRoom:(NCRoom *)room;
- (instancetype)initForRoom:(NCRoom *)room fromChatViewController:(ChatViewController *)chatViewController;

@end
