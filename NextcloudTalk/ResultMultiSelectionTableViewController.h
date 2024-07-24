/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

#import "ContactsTableViewCell.h"

#import "NCRoom.h"

@interface ResultMultiSelectionTableViewController : UITableViewController

@property (nonatomic, strong) NSMutableDictionary *contacts;
@property (nonatomic, strong) NSArray *indexes;
@property (nonatomic, strong) NSMutableArray *selectedParticipants;
@property (nonatomic, strong) NCRoom *room;

- (void)setSearchResultContacts:(NSMutableDictionary *)contacts withIndexes:(NSArray *)indexes;
- (void)showSearchingUI;

@end
