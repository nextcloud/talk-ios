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
    NSMutableArray *_participants;
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
    _participants = [[NSMutableArray alloc] init];
    _alreadyAddedParticipants = [room.participants allKeys];
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 60, 0);
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:_resultTableViewController];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:navigationController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    self.tableView.tableHeaderView = _searchController.searchBar;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
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
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSMutableArray *contacts, NSMutableDictionary *indexedContacts, NSError *error) {
        if (!error) {
            _participants = [self filterContacts:contacts];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get participants: %@", error);
        }
    }];
}

- (void)searchForParticipantsWithString:(NSString *)searchString
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSMutableArray *contacts, NSMutableDictionary *indexedContacts, NSError *error) {
        if (!error) {
            _resultTableViewController.filteredContacts = [self filterContacts:contacts];
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
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _participants.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NCUser *participant = [_participants objectAtIndex:indexPath.row];
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
    NCUser *participant = [_participants objectAtIndex:indexPath.row];
    
    if (_searchController.active) {
        participant =  [_resultTableViewController.filteredContacts objectAtIndex:indexPath.row];
    }
    
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
