//
//  NewRoomTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 25.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NewRoomTableViewController.h"

#import "RoomCreationTableViewController.h"
#import "RoomCreation2TableViewController.h"
#import "ContactsTableViewController.h"
#import "NCAPIController.h"
#import "NCUserInterfaceController.h"
#import "SearchTableViewController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

typedef enum HeaderSection {
    kHeaderSectionNewGroup = 0,
    kHeaderSectionNewPublic,
    kHeaderSectionNumber
} HeaderSection;

@interface NewRoomTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSDictionary *_contacts;
    NSMutableArray *_indexes;
    UISearchController *_searchController;
    SearchTableViewController *_resultTableViewController;
}
@end

@implementation NewRoomTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contacts = [[NSDictionary alloc] init];
    _indexes = [[NSMutableArray alloc] init];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = _searchController;
        _searchController.searchBar.tintColor = [UIColor whiteColor];
        UIColor *color = [UIColor colorWithWhite:1.0 alpha:0.9];
        _searchController.searchBar.tintColor = color;
        [[UITextField appearanceWhenContainedInInstancesOfClasses:@[[UISearchBar class]]] setDefaultTextAttributes:@{NSForegroundColorAttributeName:color}];
    } else {
        self.tableView.tableHeaderView = _searchController.searchBar;
        _searchController.searchBar.barTintColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0]; //efeff4
        _searchController.searchBar.layer.borderWidth = 1;
        _searchController.searchBar.layer.borderColor = [[UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0] CGColor];
    }
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain
                                                                  target:nil action:nil];
    self.navigationItem.backBarButtonItem = backButton;
    
    self.navigationItem.title = @"New conversation";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    }
    
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
    [[NCAPIController sharedInstance] createRoomWith:contact.userId
                                              ofType:kNCRoomTypeOneToOneCall
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
    RoomCreationTableViewController *roomCreationVC = [[RoomCreationTableViewController alloc] init];
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
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            _contacts = contacts;
            _indexes = [NSMutableArray arrayWithArray:indexes];
            [_indexes insertObject:@"" atIndex:0];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get contacts: %@", error);
        }
    }];
}

- (void)searchForContactsWithString:(NSString *)searchString
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            _resultTableViewController.contacts = contacts;
            _resultTableViewController.indexes = indexes;
            [_resultTableViewController.tableView reloadData];
        } else {
            NSLog(@"Error while searching for contacts: %@", error);
        }
    }];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self searchForContactsWithString:_searchController.searchBar.text];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _indexes.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return kHeaderSectionNumber;
    }
    NSString *index = [_indexes objectAtIndex:section];
    NSArray *contacts = [_contacts objectForKey:index];
    return contacts.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 80.0f;
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
                cell.labelTitle.text = @"New group conversation";
                [cell.contactImage setImage:[UIImage imageNamed:@"group-bg"]];
                break;
                
            case kHeaderSectionNewPublic:
                cell.labelTitle.text = @"New public conversation";
                [cell.contactImage setImage:[UIImage imageNamed:@"public-bg"]];
                break;
                
            default:
                break;
        }
        cell.contactImage.layer.cornerRadius = 24.0;
        cell.contactImage.layer.masksToBounds = YES;
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
    
    // Create avatar for every contact
    [cell.contactImage setImageWithString:contact.name color:nil circular:true];
    
    // Request user avatar to the server and set it if exist
    [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:contact.userId andSize:96]
                             placeholderImage:nil
                                      success:nil
                                      failure:nil];
    
    cell.contactImage.layer.cornerRadius = 24.0;
    cell.contactImage.layer.masksToBounds = YES;
    
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
