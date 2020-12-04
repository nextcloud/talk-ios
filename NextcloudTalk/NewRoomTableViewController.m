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

#import "NewRoomTableViewController.h"

#import "RoomCreationTableViewController.h"
#import "RoomCreation2TableViewController.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCContactsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "PlaceholderView.h"
#import "SearchTableViewController.h"
#import "UIImageView+AFNetworking.h"

typedef enum HeaderSection {
    kHeaderSectionNewGroup = 0,
    kHeaderSectionNewPublic,
    kHeaderSectionNumber
} HeaderSection;

NSString * const NCSelectedContactForChatNotification = @"NCSelectedContactForChatNotification";

@interface NewRoomTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSMutableDictionary *_contacts;
    NSMutableArray *_indexes;
    UISearchController *_searchController;
    PlaceholderView *_newRoomBackgroundView;
    SearchTableViewController *_resultTableViewController;
    NSTimer *_searchTimer;
    NSURLSessionTask *_searchContactsTask;
}
@end

@implementation NewRoomTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contacts = [[NSMutableDictionary alloc] init];
    _indexes = [[NSMutableArray alloc] init];
    [_indexes insertObject:@"" atIndex:0];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
        
        self.navigationItem.searchController = _searchController;
        self.navigationItem.searchController.searchBar.searchTextField.backgroundColor = [NCUtils searchbarBGColorForColor:themeColor];
        _searchController.searchBar.tintColor = [NCAppBranding themeTextColor];
        UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
        UIButton *clearButton = [searchTextField valueForKey:@"_clearButton"];
        searchTextField.tintColor = [NCAppBranding themeTextColor];
        searchTextField.textColor = [NCAppBranding themeTextColor];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Search bar placeholder
            searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search", nil)
            attributes:@{NSForegroundColorAttributeName:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]}];
            // Search bar search icon
            UIImageView *searchImageView = (UIImageView *)searchTextField.leftView;
            searchImageView.image = [searchImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [searchImageView setTintColor:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]];
            // Search bar search clear button
            UIImage *clearButtonImage = [clearButton.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [clearButton setImage:clearButtonImage forState:UIControlStateNormal];
            [clearButton setImage:clearButtonImage forState:UIControlStateHighlighted];
            [clearButton setTintColor:[NCAppBranding themeTextColor]];
        });
    } else if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = _searchController;
        _searchController.searchBar.tintColor = [NCAppBranding themeTextColor];
        UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
        searchTextField.tintColor = [NCAppBranding themeColor];
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
    
    // New room placeholder view
    _newRoomBackgroundView = [[PlaceholderView alloc] init];
    [_newRoomBackgroundView.placeholderView setHidden:YES];
    [_newRoomBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _newRoomBackgroundView;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    _searchController.hidesNavigationBarDuringPresentation = NO;
    
    self.definesPresentationContext = YES;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    self.navigationController.navigationBar.topItem.leftBarButtonItem.accessibilityHint = NSLocalizedString(@"Cancel conversation creation", nil);
    
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", nil) style:UIBarButtonItemStylePlain
                                                                  target:nil action:nil];
    self.navigationItem.backBarButtonItem = backButton;
    
    self.navigationItem.title = NSLocalizedString(@"New conversation", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
    
    [[NCContactsManager sharedInstance] searchInServerForAddressBookContacts];
    [self getContacts];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Actions

- (void)cancelButtonPressed
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)createRoomWithContact:(NCUser *)contact
{
    [[NCAPIController sharedInstance] createRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] with:contact.userId
                                              ofType:kNCRoomTypeOneToOne
                                             andName:nil
                                 withCompletionBlock:^(NSString *token, NSError *error) {
                                     if (!error) {
                                         [self.navigationController dismissViewControllerAnimated:YES completion:^{
                                             [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedContactForChatNotification
                                                                                                 object:self
                                                                                               userInfo:@{@"token":token}];
                                         }];
                                         NSLog(@"Room %@ with %@ created", token, contact.name);
                                     } else {
                                         NSLog(@"Failed creating a room with %@", contact.name);
                                     }
                                 }];
}

- (void)startCreatingNewGroup
{
    RoomCreationTableViewController *roomCreationVC = [[RoomCreationTableViewController alloc] initWithParticipants:_contacts andIndexes:_indexes];
    [self.navigationController pushViewController:roomCreationVC animated:YES];
}

- (void)startCreatingNewPublicRoom
{
    RoomCreation2TableViewController *roomCreationVC = [[RoomCreation2TableViewController alloc] initForPublicRoom];
    [self.navigationController pushViewController:roomCreationVC animated:YES];
}

#pragma mark - Contacts

- (void)getContacts
{
    [[NCAPIController sharedInstance] getContactsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] forRoom:nil groupRoom:NO withSearchParam:nil andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            _contacts = contacts;
            _indexes = [NSMutableArray arrayWithArray:indexes];
            [_indexes insertObject:@"" atIndex:0];
            [_newRoomBackgroundView.loadingView stopAnimating];
            [_newRoomBackgroundView.loadingView setHidden:YES];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get contacts: %@", error);
        }
    }];
}

- (void)searchForContactsWithString:(NSString *)searchString
{
    [_searchContactsTask cancel];
    _searchContactsTask = [[NCAPIController sharedInstance] getContactsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] forRoom:nil groupRoom:NO withSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            [_resultTableViewController setSearchResultContacts:contacts withIndexes:indexes];
        } else {
            if (error.code != -999) {
                NSLog(@"Error while searching for contacts: %@", error);
            }
        }
    }];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [_searchTimer invalidate];
    _searchTimer = nil;
    [_resultTableViewController showSearchingUI];
    dispatch_async(dispatch_get_main_queue(), ^{
        _searchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(searchForContacts) userInfo:nil repeats:NO];
    });
}

- (void)searchForContacts
{
    NSString *searchString = _searchController.searchBar.text;
    if (![searchString isEqualToString:@""]) {
        [self searchForContactsWithString:searchString];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _indexes.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        BOOL canCreate = [[NCSettingsController sharedInstance] canCreateGroupAndPublicRooms];
        return canCreate ? kHeaderSectionNumber : 0;
    }
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
    if (section == 0) {
        return nil;
    }
    return [_indexes objectAtIndex:section];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return _indexes;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
        if (!cell) {
            cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
        }
        switch (indexPath.row) {
            case kHeaderSectionNewGroup:
                cell.labelTitle.text = NSLocalizedString(@"Group conversation", nil);
                cell.labelTitle.accessibilityLabel = NSLocalizedString(@"Create a new group conversation", nil);
                cell.labelTitle.accessibilityHint = NSLocalizedString(@"Double tap to start creating a new group conversation", nil);
                cell.labelTitle.textColor = [UIColor colorWithRed:0.00 green:0.48 blue:1.00 alpha:1.0]; //#007AFF
                [cell.contactImage setImage:[UIImage imageNamed:@"group-bg"]];
                break;
                
            case kHeaderSectionNewPublic:
                cell.labelTitle.text = NSLocalizedString(@"Public conversation", nil);
                cell.labelTitle.accessibilityLabel = NSLocalizedString(@"Create a new public conversation", nil);
                cell.labelTitle.accessibilityHint = NSLocalizedString(@"Double tap to start creating a new public conversation", nil);
                cell.labelTitle.textColor = [UIColor colorWithRed:0.00 green:0.48 blue:1.00 alpha:1.0]; //#007AFF
                [cell.contactImage setImage:[UIImage imageNamed:@"public-bg"]];
                break;
                
            default:
                break;
        }
        return cell;
    }
    NSString *index = [_indexes objectAtIndex:indexPath.section];
    NSArray *contacts = [_contacts objectForKey:index];
    NCUser *contact = [contacts objectAtIndex:indexPath.row];
    ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
    }
    
    cell.labelTitle.text = contact.name;
    cell.labelTitle.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Create a conversation with %@", nil), contact.name];
    cell.labelTitle.accessibilityHint = [NSString stringWithFormat:NSLocalizedString(@"Double tap to create a conversation with %@", nil), contact.name];
    
    [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:contact.userId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                             placeholderImage:nil success:nil failure:nil];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_searchController.active && indexPath.section == 0) {
        switch (indexPath.row) {
            case kHeaderSectionNewGroup:
                [self startCreatingNewGroup];
                break;
                
            case kHeaderSectionNewPublic:
                [self startCreatingNewPublicRoom];
                break;
                
            default:
                break;
        }

    } else {
        NSString *index = nil;
        NSArray *contacts = nil;
        
        if (_searchController.active) {
            index = [_resultTableViewController.indexes objectAtIndex:indexPath.section];
            contacts = [_resultTableViewController.contacts objectForKey:index];
        } else {
            index = [_indexes objectAtIndex:indexPath.section];
            contacts = [_contacts objectForKey:index];
        }
        
        NCUser *contact = [contacts objectAtIndex:indexPath.row];
        [self createRoomWithContact:contact];
    }
}


@end
