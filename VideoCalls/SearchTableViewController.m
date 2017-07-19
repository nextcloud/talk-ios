//
//  SearchTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 18.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "SearchTableViewController.h"

#import "NCUser.h"

@interface SearchTableViewController ()

@end

@implementation SearchTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _filteredContacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCUser *contact = [_filteredContacts objectAtIndex:indexPath.row];
    ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
    }
    
    cell.labelTitle.text = contact.name;
    
    return cell;
}

@end
