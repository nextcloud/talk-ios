/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "AddParticipantsTableViewController.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCContact.h"
#import "NCDatabaseManager.h"
#import "NCUserInterfaceController.h"
#import "PlaceholderView.h"
#import "ResultMultiSelectionTableViewController.h"

#import "NextcloudTalk-Swift.h"

@interface AddParticipantsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSMutableDictionary *_participants;
    NSArray *_indexes;
    NCRoom *_room;
    UISearchController *_searchController;
    ResultMultiSelectionTableViewController *_resultTableViewController;
    NSMutableArray *_selectedParticipants;
    PlaceholderView *_participantsBackgroundView;
    NSTimer *_searchTimer;
    NSURLSessionTask *_searchParticipantsTask;
    UIActivityIndicatorView *_addingParticipantsIndicator;
    BOOL _errorAddingParticipants;
}
@end

@implementation AddParticipantsTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    if (room) {
        _room = room;
    }

    _participants = [[NSMutableDictionary alloc] init];
    _indexes = [[NSArray alloc] init];
    _selectedParticipants = [[NSMutableArray alloc] init];

    _addingParticipantsIndicator = [[UIActivityIndicatorView alloc] init];
    if (@available(iOS 26.0, *)) {
        _addingParticipantsIndicator.color = [UIColor labelColor];
    } else {
        _addingParticipantsIndicator.color = [NCAppBranding themeTextColor];
    }

    return self;
}

- (instancetype)initWithParticipants:(NSArray<NCUser *> *)participants
{
    self = [self initForRoom:nil];
    if (!self) {
        return nil;
    }

    _selectedParticipants = [[NSMutableArray alloc] initWithArray:participants];

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    
    _resultTableViewController = [[ResultMultiSelectionTableViewController alloc] init];
    _resultTableViewController.selectedParticipants = _selectedParticipants;
    _resultTableViewController.room = _room;

    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];

    self.navigationItem.searchController = _searchController;

    [NCAppBranding styleViewController:self];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Contacts placeholder view
    _participantsBackgroundView = [[PlaceholderView alloc] init];
    [_participantsBackgroundView setImage:[UIImage imageNamed:@"contacts-placeholder"]];
    [_participantsBackgroundView.placeholderTextView setText:NSLocalizedString(@"No participants found", nil)];
    [_participantsBackgroundView.placeholderView setHidden:YES];
    [_participantsBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _participantsBackgroundView;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    _searchController.hidesNavigationBarDuringPresentation = NO;

    [self updateCounter];

    self.definesPresentationContext = YES;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    self.navigationItem.title = NSLocalizedString(@"Add participants", nil);

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
    
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self getPossibleParticipants];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.navigationItem.hidesSearchBarWhenScrolling = NO;
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
    if ([self.delegate respondsToSelector:@selector(addParticipantsTableViewControllerDidFinish:)]) {
        [self.delegate addParticipantsTableViewControllerDidFinish:self];
    }
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)addButtonPressed
{
    // Adding participants to a room
    if (_room && _selectedParticipants.count > 0) {
        // Extending a one2one room
        if (_room.type == kNCRoomTypeOneToOne && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityConversationCreationAll]) {
            [self extendOne2OneRoom];

        // Adding participants to a group room
        } else {
            dispatch_group_t addParticipantsGroup = dispatch_group_create();

            [self showAddingParticipantsView];
            for (NCUser *participant in _selectedParticipants) {
                [self addParticipantToRoom:participant withDispatchGroup:addParticipantsGroup];
            }

            dispatch_group_notify(addParticipantsGroup, dispatch_get_main_queue(), ^{
                [self removeAddingParticipantsView];

                if (!self->_errorAddingParticipants) {
                    [self close];
                }

                // Reset flag once adding participants process has finished
                self->_errorAddingParticipants = NO;
            });
        }

    // If there is no room, it means the AddParticipantsViewController is being used just to select participants
    } else if ([self.delegate respondsToSelector:@selector(addParticipantsTableViewController:wantsToAdd:)]) {
        [self.delegate addParticipantsTableViewController:self wantsToAdd:_selectedParticipants];
        [self close];
    }
}

- (void)addParticipantToRoom:(NCUser *)participant withDispatchGroup:(dispatch_group_t)dispatchGroup
{
    dispatch_group_enter(dispatchGroup);

    [[NCAPIController sharedInstance] addParticipant:participant.userId ofType:participant.source toRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(OcsResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"Could not add participant", nil)
                                         message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while adding %@ to the room", nil), participant.name]
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];

            self->_errorAddingParticipants = YES;

            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        }

        dispatch_group_leave(dispatchGroup);
    }];
}

- (void)extendOne2OneRoom
{
    RoomBuilder *roomBuilder = [[RoomBuilder alloc] init];
    [roomBuilder roomType:kNCRoomTypeGroup];
    [roomBuilder objecType:NCRoomObjectTypeExtendedConversation];
    [roomBuilder objectId:_room.token];

    // Create the other participant of the 1:1 room from room object
    NCUser *user = [[NCUser alloc] init];
    user.userId = _room.name;
    user.name = _room.displayName;
    user.source = kParticipantTypeUser;

    // Add the other participant of the 1:1 room at the beginning of the selected participants array
    NSArray *participants = [@[user] arrayByAddingObjectsFromArray:_selectedParticipants];
    [roomBuilder participants:participants];

    // Create the room name [Actor who extends the 1:1 room, other participant of the 1:1 room, selected participants...]
    NSMutableArray *namesArray = [NSMutableArray arrayWithArray:[participants valueForKey:@"name"]];
    [namesArray insertObject:_room.account.userDisplayName atIndex:0];
    NSString *roomName = [namesArray componentsJoinedByString:@", "];
    // Ensure the roomName does not exceed 255 characters limit.
    if (roomName.length > 255) {
        roomName = [[roomName substringToIndex:254] stringByAppendingString:@"…"];
    }
    [roomBuilder roomName:roomName];

    [self showAddingParticipantsView];
    [[NCAPIController sharedInstance] createRoomForAccount:_room.account withParameters:roomBuilder.roomParameters completionBlock:^(NCRoom *room, NSError *error) {
        [self removeAddingParticipantsView];
        if (error) {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"Could not start group conversation", nil)
                                         message:NSLocalizedString(@"An error occurred while starting a new group conversation", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:nil];

            [alert addAction:okButton];

            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        } else if (room) {
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedUserForChatNotification object:self userInfo:@{@"token": room.token}];
            }];
        }
    }];
}

- (void)updateCounter
{
    UIBarButtonItem *addButton = nil;
    if (!_room) {
        addButton = [[UIBarButtonItem alloc]
                     initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                     target:self
                     action:@selector(addButtonPressed)];
    } else if (_selectedParticipants.count > 0) {
        addButton = [[UIBarButtonItem alloc]
                     initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Add (%lu)", nil), (unsigned long)_selectedParticipants.count]
                     style:UIBarButtonItemStylePlain
                     target:self
                     action:@selector(addButtonPressed)];
    }

    self.navigationController.navigationBar.topItem.rightBarButtonItem = addButton;
}

- (void)showAddingParticipantsView
{
    [_addingParticipantsIndicator startAnimating];
    UIBarButtonItem *addingParticipantButton = [[UIBarButtonItem alloc] initWithCustomView:_addingParticipantsIndicator];
    self.navigationItem.rightBarButtonItems = @[addingParticipantButton];
    self.tableView.allowsSelection = NO;
    _resultTableViewController.tableView.allowsSelection = NO;
}

- (void)removeAddingParticipantsView
{
    [_addingParticipantsIndicator stopAnimating];
    [self updateCounter];
    self.tableView.allowsSelection = YES;
    _resultTableViewController.tableView.allowsSelection = YES;
}

#pragma mark - Participants actions

- (void)getPossibleParticipants
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getContactsForAccount:activeAccount forRoom:_room.token groupRoom:YES withSearchParam:nil andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSMutableArray *storedContacts = [NCContact contactsForAccountId:activeAccount.accountId contains:nil];
            NSMutableArray *combinedContactList = [NCUser combineUsersArray:storedContacts withUsersArray:contactList];
            NSMutableDictionary *participants = [NCUser indexedUsersFromUsersArray:combinedContactList];
            self->_participants = participants;
            self->_indexes = [[participants allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            [self->_participantsBackgroundView.loadingView stopAnimating];
            [self->_participantsBackgroundView.loadingView setHidden:YES];
            [self->_participantsBackgroundView.placeholderView setHidden:(participants.count > 0)];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get participants: %@", error);
        }
    }];
}

- (void)searchForParticipantsWithString:(NSString *)searchString
{
    [_searchParticipantsTask cancel];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    _searchParticipantsTask = [[NCAPIController sharedInstance] getContactsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] forRoom:_room.token groupRoom:YES withSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSMutableArray *storedContacts = [NCContact contactsForAccountId:activeAccount.accountId contains:searchString];
            NSMutableArray *combinedContactList = [NCUser combineUsersArray:storedContacts withUsersArray:contactList];
            NSMutableDictionary *participants = [NCUser indexedUsersFromUsersArray:combinedContactList];
            NSArray *sortedIndexes = [[participants allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            [self->_resultTableViewController setSearchResultContacts:participants withIndexes:sortedIndexes];
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
        if ([user.userId isEqualToString:participant.userId] &&
            [user.source isEqualToString:participant.source]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeSelectedParticipant:(NCUser *)participant
{
    NCUser *userToDelete = nil;
    for (NCUser *user in _selectedParticipants) {
        if ([user.userId isEqualToString:participant.userId] &&
            [user.source isEqualToString:participant.source]) {
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
    [_resultTableViewController showSearchingUI];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_searchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(searchForParticipants) userInfo:nil repeats:NO];
    });
}

- (void)searchForParticipants
{
    NSString *searchString = _searchController.searchBar.text;
    if (![searchString isEqualToString:@""]) {
        [self searchForParticipantsWithString:searchString];
    }
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
    return kContactsTableCellHeight;
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

    TalkAccount *account = self->_room.account;

    if (!account) {
        account = [[NCDatabaseManager sharedInstance] activeAccount];
    }

    [cell.contactImage setActorAvatarForId:participant.userId withType:participant.source withDisplayName:participant.name withRoomToken:_room.token using:account];

    UIImage *selectionImage = [UIImage systemImageNamed:@"circle"];
    UIColor *selectionImageColor = [UIColor tertiaryLabelColor];
    if ([self isParticipantAlreadySelected:participant]) {
        selectionImage = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        selectionImageColor = [NCAppBranding elementColor];
    }
    UIImageView *selectionImageView = [[UIImageView alloc] initWithImage:selectionImage];
    selectionImageView.tintColor = selectionImageColor;
    cell.accessoryView = selectionImageView;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *index = nil;
    NSArray *participants = nil;
    
    if (_searchController.active && _resultTableViewController.contacts.count > 0) {
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
