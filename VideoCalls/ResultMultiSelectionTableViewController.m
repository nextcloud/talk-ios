//
//  ResultMultiSelectionTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 18.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "ResultMultiSelectionTableViewController.h"

#import "NCUser.h"
#import "NCAPIController.h"
#import "PlaceholderView.h"
#import "UIImageView+AFNetworking.h"

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
    [_contactsBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"contacts-placeholder"]];
    [_contactsBackgroundView.placeholderText setText:@"No results found."];
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
    
    [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:contact.userId andSize:96]
                             placeholderImage:nil success:nil failure:nil];
    cell.contactImage.layer.cornerRadius = 24.0;
    cell.contactImage.layer.masksToBounds = YES;
    
    cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-unchecked"]];
    for (NCUser *user in _selectedParticipants) {
        if ([user.userId isEqualToString:contact.userId]) {
            cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-checked"]];
        }
    }
    
    return cell;
}

@end
