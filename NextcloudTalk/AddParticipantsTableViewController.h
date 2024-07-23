/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "NCRoom.h"
#import "NCUser.h"

@class AddParticipantsTableViewController;
@protocol AddParticipantsTableViewControllerDelegate <NSObject>
@optional
- (void)addParticipantsTableViewController:(AddParticipantsTableViewController *)viewController wantsToAdd:(NSArray<NCUser *> *)participants;
- (void)addParticipantsTableViewControllerDidFinish:(AddParticipantsTableViewController *)viewController;
@end

@interface AddParticipantsTableViewController : UITableViewController

@property (nonatomic, weak) id<AddParticipantsTableViewControllerDelegate> delegate;

- (instancetype)initForRoom:(NCRoom *)room;
- (instancetype)initWithParticipants:(NSArray<NCUser *> *)room;

@end
