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
