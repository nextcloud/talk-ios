//
//  AddParticipantsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "AddParticipantsTableViewController.h"

#import "NCAPIController.h"
#import "NCUserInterfaceController.h"
#import "PlaceholderView.h"
#import "ResultMultiSelectionTableViewController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

@interface AddParticipantsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSMutableDictionary *_participants;
    NSArray *_indexes;
    NCRoom *_room;
    NSArray *_participantsInRoom;
    UISearchController *_searchController;
    ResultMultiSelectionTableViewController *_resultTableViewController;
    NSMutableArray *_selectedParticipants;
    PlaceholderView *_participantsBackgroundView;
    NSTimer *_searchTimer;
    NSURLSessionTask *_searchParticipantsTask;
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
    _participantsInRoom = [room.participants allKeys];
    _participants = [[NSMutableDictionary alloc] init];
    _indexes = [[NSArray alloc] init];
    _selectedParticipants = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    
    _resultTableViewController = [[ResultMultiSelectionTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = _searchController;
        _searchController.searchBar.tintColor = [UIColor whiteColor];
        UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
        searchTextField.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
        UIView *backgroundview = [searchTextField.subviews firstObject];
        backgroundview.backgroundColor = [UIColor whiteColor];
        backgroundview.layer.cornerRadius = 8;
        backgroundview.clipsToBounds = YES;
    } else {
        self.tableView.tableHeaderView = _searchController.searchBar;
        _searchController.searchBar.barTintColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0]; //efeff4
        _searchController.searchBar.layer.borderWidth = 1;
        _searchController.searchBar.layer.borderColor = [[UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0] CGColor];
    }
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Contacts placeholder view
    _participantsBackgroundView = [[PlaceholderView alloc] init];
    [_participantsBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"contacts-placeholder"]];
    [_participantsBackgroundView.placeholderText setText:@"No participants found."];
    [_participantsBackgroundView.placeholderView setHidden:YES];
    [_participantsBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _participantsBackgroundView;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    _searchController.hidesNavigationBarDuringPresentation = NO;

    
    self.definesPresentationContext = YES;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    self.navigationItem.title = @"Add participants";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    // Fix uisearchcontroller animation
    self.extendedLayoutIncludesOpaqueBars = YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
    
    [self getPossibleParticipants];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
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

- (void)addButtonPressed
{
    self.tableView.allowsSelection = NO;
    _resultTableViewController.tableView.allowsSelection = NO;
    
    for (NCUser *participant in _selectedParticipants) {
        [self addParticipantToRoom:participant];
    }
    
    [self close];
}

- (void)addParticipantToRoom:(NCUser *)participant
{
    [[NCAPIController sharedInstance] addParticipant:participant.userId toRoom:_room.token withCompletionBlock:^(NSError *error) {
        if (error) {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@"Could not add participant"
                                         message:[NSString stringWithFormat:@"An error occurred while adding %@ to the room", participant.name]
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:@"OK"
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];
            
            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        }
    }];
}

- (void)updateCounter
{
    if (_selectedParticipants.count > 0) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"Add (%lu)", (unsigned long)_selectedParticipants.count]
                                                                      style:UIBarButtonItemStylePlain target:self action:@selector(addButtonPressed)];
        self.navigationController.navigationBar.topItem.rightBarButtonItem = addButton;
    } else {
        self.navigationController.navigationBar.topItem.rightBarButtonItem = nil;
    }
}

#pragma mark - Participants actions

- (NSMutableArray *)filterContacts:(NSMutableArray *)contacts
{
    NSMutableArray *participants = [[NSMutableArray alloc] init];
    for (NCUser *user in contacts) {
        if (![_participantsInRoom containsObject:user.userId]) {
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
            [_participantsBackgroundView.loadingView stopAnimating];
            [_participantsBackgroundView.loadingView setHidden:YES];
            [_participantsBackgroundView.placeholderView setHidden:(participants.count > 0)];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get participants: %@", error);
        }
    }];
}

- (void)searchForParticipantsWithString:(NSString *)searchString
{
    [_searchParticipantsTask cancel];
    _searchParticipantsTask = [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSMutableArray *filteredParticipants = [self filterContacts:contactList];
            NSMutableDictionary *participants = [[NCAPIController sharedInstance] indexedUsersFromUsersArray:filteredParticipants];
            _resultTableViewController.contacts = participants;
            _resultTableViewController.indexes = [[participants allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];;
            [_resultTableViewController.tableView reloadData];
        } else {
            if (error.code != -999) {
                NSLog(@"Error while searching for participants: %@", error);
            }
        }
    }];
}

- (BOOL)isParticipantAlreadySelected:(NCUser *)participant
{
    for (NCUser *user in _selectedParticipants) {
        if ([user.userId isEqualToString:participant.userId]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeSelectedParticipant:(NCUser *)participant
{
    NCUser *userToDelete = nil;
    for (NCUser *user in _selectedParticipants) {
        if ([user.userId isEqualToString:participant.userId]) {
            userToDelete = user;
        }
    }
    
    if (userToDelete) {
        [_selectedParticipants removeObject:userToDelete];
    }
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [_searchTimer invalidate];
    _searchTimer = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        _searchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(searchForParticipants) userInfo:nil repeats:NO];
    });
}

- (void)searchForParticipants
{
    [self searchForParticipantsWithString:_searchController.searchBar.text];
}

- (void)didDismissSearchController:(UISearchController *)searchController
{
    [self.tableView reloadData];
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

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return _indexes;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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
    
    UIImageView *checkboxChecked = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-checked"]];
    UIImageView *checkboxUnchecked = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-unchecked"]];
    cell.accessoryView = ([self isParticipantAlreadySelected:participant]) ? checkboxChecked : checkboxUnchecked;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *index = nil;
    NSArray *participants = nil;
    
    if (_searchController.active) {
        index = [_resultTableViewController.indexes objectAtIndex:indexPath.section];
        participants = [_resultTableViewController.contacts objectForKey:index];
    } else {
        index = [_indexes objectAtIndex:indexPath.section];
        participants = [_participants objectForKey:index];
    }
    
    NCUser *participant = [participants objectAtIndex:indexPath.row];
    if (![self isParticipantAlreadySelected:participant]) {
        [_selectedParticipants addObject:participant];
    } else {
        [self removeSelectedParticipant:participant];
    }
    
    _resultTableViewController.selectedParticipants = _selectedParticipants;
    
    [tableView beginUpdates];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [tableView endUpdates];
    
    [self updateCounter];
}

@end
