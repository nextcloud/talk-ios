//
//  AddParticipantsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "AddParticipantsTableViewController.h"

#import "NCAPIController.h"
#import "SearchTableViewController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

@interface AddParticipantsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NCRoom *_room;
    NSMutableDictionary *_participants;
    NSArray *_indexes;
    NSArray *_alreadyAddedParticipants;
    UISearchController *_searchController;
    SearchTableViewController *_resultTableViewController;
}
@end

@implementation AddParticipantsTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _room = room;
    _participants = [[NSMutableDictionary alloc] init];
    _indexes = [[NSArray alloc] init];
    _alreadyAddedParticipants = [room.participants allKeys];
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:_resultTableViewController];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:navigationController];
    _searchController.searchResultsUpdater = self;
    _searchController.searchBar.barTintColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0]; //efeff4
    _searchController.searchBar.layer.borderWidth = 1;
    _searchController.searchBar.layer.borderColor = [[UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0] CGColor];
    [_searchController.searchBar sizeToFit];
    self.tableView.tableHeaderView = _searchController.searchBar;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    _searchController.hidesNavigationBarDuringPresentation = NO;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    self.navigationItem.title = @"Add participants";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self getPossibleParticipants];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - View controller actions

- (void)cancelButtonPressed
{
    [self close];
}

- (void)close
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Participants actions

- (NSMutableArray *)filterContacts:(NSMutableArray *)contacts
{
    NSMutableArray *participants = [[NSMutableArray alloc] init];
    for (NCUser *user in contacts) {
        if (![_alreadyAddedParticipants containsObject:user.userId]) {
            [participants addObject:user];
        }
    }
    return participants;
}

- (void)getPossibleParticipants
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSMutableArray *filteredParticipants = [self filterContacts:contactList];
            NSMutableDictionary *participants = [[NCAPIController sharedInstance] indexedUsersFromUsersArray:filteredParticipants];
            _participants = participants;
            _indexes = [[participants allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get participants: %@", error);
        }
    }];
}

- (void)searchForParticipantsWithString:(NSString *)searchString
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSMutableArray *filteredParticipants = [self filterContacts:contactList];
            NSMutableDictionary *participants = [[NCAPIController sharedInstance] indexedUsersFromUsersArray:filteredParticipants];
            _resultTableViewController.contacts = participants;
            _resultTableViewController.indexes = [[participants allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];;
            [_resultTableViewController.tableView reloadData];
        } else {
            NSLog(@"Error while searching for participants: %@", error);
        }
    }];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self searchForParticipantsWithString:_searchController.searchBar.text];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _indexes.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *index = [_indexes objectAtIndex:section];
    NSArray *participants = [_participants objectForKey:index];
    return participants.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 80.0f;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [_indexes objectAtIndex:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *index = [_indexes objectAtIndex:indexPath.section];
    NSArray *participants = [_participants objectForKey:index];
    NCUser *participant = [participants objectAtIndex:indexPath.row];
    ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
    }
    
    cell.labelTitle.text = participant.name;
    
    // Create avatar for every contact
    [cell.contactImage setImageWithString:participant.name color:nil circular:true];
    
    // Request user avatar to the server and set it if exist
    [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId andSize:96]
                             placeholderImage:nil
                                      success:nil
                                      failure:nil];
    
    cell.contactImage.layer.cornerRadius = 24.0;
    cell.contactImage.layer.masksToBounds = YES;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *index = [_indexes objectAtIndex:indexPath.section];
    NSArray *participants = [_participants objectForKey:index];
    
    if (_searchController.active) {
        index = [_resultTableViewController.indexes objectAtIndex:indexPath.section];
        participants = [_resultTableViewController.contacts objectForKey:index];
    }
    
    NCUser *participant = [participants objectAtIndex:indexPath.row];
    
    self.tableView.allowsSelection = NO;
    _resultTableViewController.tableView.allowsSelection = NO;
    
    [[NCAPIController sharedInstance] addParticipant:participant.userId toRoom:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self close];
        } else {
            self.tableView.allowsSelection = YES;
            _resultTableViewController.tableView.allowsSelection = YES;
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@"Could not add participant"
                                         message:[NSString stringWithFormat:@"An error occurred while adding %@ to the room", participant.name]
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:@"OK"
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];    
}

@end
