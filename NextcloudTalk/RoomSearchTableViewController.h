/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NCRoom;
@class NCUser;
@class NKSearchEntry;

@interface RoomSearchTableViewController : UITableViewController

@property (nonatomic, strong) NSArray *rooms;
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSArray *listableRooms;
@property (nonatomic, strong) NSArray *messages;
@property (nonatomic, assign) BOOL searchingMessages;

- (NCRoom *)roomForIndexPath:(NSIndexPath *)indexPath;
- (NCUser *)userForIndexPath:(NSIndexPath *)indexPath;
- (NKSearchEntry *)messageForIndexPath:(NSIndexPath *)indexPath;
- (void)showSearchingFooterView;
- (void)clearSearchedResults;

@end

NS_ASSUME_NONNULL_END
