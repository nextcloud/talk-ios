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

#import "ResultMultiSelectionTableViewController.h"

#import "UIImageView+AFNetworking.h"

#import "NCUser.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "PlaceholderView.h"

@interface ResultMultiSelectionTableViewController ()
{
    PlaceholderView *_contactsBackgroundView;
}
@end

@implementation ResultMultiSelectionTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Contacts placeholder view
    _contactsBackgroundView = [[PlaceholderView alloc] init];
    [_contactsBackgroundView setImage:[UIImage imageNamed:@"contacts-placeholder"]];
    [_contactsBackgroundView.placeholderTextView setText:NSLocalizedString(@"No results found", nil)];
    [self showSearchingUI];
    self.tableView.backgroundView = _contactsBackgroundView;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)showSearchingUI
{
    [self setContacts:nil withIndexes:nil];
    [_contactsBackgroundView.placeholderView setHidden:YES];
    [_contactsBackgroundView.loadingView startAnimating];
    [_contactsBackgroundView.loadingView setHidden:NO];
}

- (void)hideSearchingUI
{
    [_contactsBackgroundView.loadingView stopAnimating];
    [_contactsBackgroundView.loadingView setHidden:YES];
}

- (void)setContacts:(NSMutableDictionary *)contacts withIndexes:(NSArray *)indexes
{
    _contacts = contacts;
    _indexes = indexes;
    [self.tableView reloadData];
}

- (void)setSearchResultContacts:(NSMutableDictionary *)contacts withIndexes:(NSArray *)indexes
{
    [self hideSearchingUI];
    [_contactsBackgroundView.placeholderView setHidden:(contacts.count > 0)];
    [self setContacts:contacts withIndexes:indexes];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _indexes.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *index = [_indexes objectAtIndex:section];
    NSArray *contacts = [_contacts objectForKey:index];
    return contacts.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kContactsTableCellHeight;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [_indexes objectAtIndex:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *index = [_indexes objectAtIndex:indexPath.section];
    NSArray *contacts = [_contacts objectForKey:index];
    NCUser *contact = [contacts objectAtIndex:indexPath.row];
    ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
    }
    
    cell.labelTitle.text = contact.name;
    
    if ([contact.source isEqualToString:kParticipantTypeUser]) {
        [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:contact.userId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                 placeholderImage:nil success:nil failure:nil];
        [cell.contactImage setContentMode:UIViewContentModeScaleToFill];
    } else if ([contact.source isEqualToString:kParticipantTypeEmail]) {
        [cell.contactImage setImage:[UIImage imageNamed:@"mail"]];
    } else {
        [cell.contactImage setImage:[UIImage imageNamed:@"group"]];
    }
    
    cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-unchecked"]];
    for (NCUser *user in _selectedParticipants) {
        if ([user.userId isEqualToString:contact.userId] && [user.source isEqualToString:contact.source]) {
            cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-checked"]];
        }
    }
    
    return cell;
}

@end
