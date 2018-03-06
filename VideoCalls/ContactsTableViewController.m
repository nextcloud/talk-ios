//
//  ContactsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "ContactsTableViewController.h"

#import "AFNetworking.h"
#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "SearchTableViewController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

@interface ContactsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSMutableArray *_contacts;
    UISearchController *_searchController;
    SearchTableViewController *_resultTableViewController;
}

@end

@implementation ContactsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contacts = [[NSMutableArray alloc] init];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 60, 0);
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    self.tableView.tableHeaderView = _searchController.searchBar;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
        
    self.definesPresentationContext = YES;
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController sharedInstance].connectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)appStateHasChanged:(NSNotification *)notification
{
    AppState appState = [[notification.userInfo objectForKey:@"appState"] intValue];
    [self adaptInterfaceForAppState:appState];
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    [self adaptInterfaceForConnectionState:connectionState];
}

#pragma mark - User Interface

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case kAppStateReady:
        {
            [self getContacts];
        }
            break;
            
        default:
            break;
    }
}

- (void)adaptInterfaceForConnectionState:(ConnectionState)connectionState
{
    switch (connectionState) {
        case kConnectionStateConnected:
        {
            [self setOnlineAppearance];
        }
            break;
            
        case kConnectionStateDisconnected:
        {
            [self setOfflineAppearance];
        }
            break;
            
        default:
            break;
    }
}

- (void)setOfflineAppearance
{
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogoOffline"]];
}

- (void)setOnlineAppearance
{
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"]];
}

- (void)getContacts
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSMutableArray *contacts, NSError *error) {
        if (!error) {
            _contacts = contacts;
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get contacts: %@", error);
        }
    }];
}

- (void)searchForContactsWithString:(NSString *)searchString
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSMutableArray *contacts, NSError *error) {
        if (!error) {
            _resultTableViewController.filteredContacts = contacts;
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
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _contacts.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NCUser *contact = [_contacts objectAtIndex:indexPath.row];
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
    if ([NCConnectionController sharedInstance].connectionState == kConnectionStateDisconnected) {
        [[NCUserInterfaceController sharedInstance] presentOfflineWarningAlert];
    } else {
        NCUser *contact = [_contacts objectAtIndex:indexPath.row];
        if (_searchController.active) {
            contact =  [_resultTableViewController.filteredContacts objectAtIndex:indexPath.row];
        }
        
        [[NCAPIController sharedInstance] createRoomWith:contact.userId
                                                  ofType:kNCRoomTypeOneToOneCall
                                                 andName:nil
                                     withCompletionBlock:^(NSString *token, NSError *error) {
                                         if (!error) {
                                             // Join created room.
                                             NSLog(@"Room %@ with %@ created", token, contact.name);
                                             [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomCreatedNotification
                                                                                                 object:self
                                                                                               userInfo:@{@"token":token}];
                                         } else {
                                             NSLog(@"Failed creating a room with %@", contact.name);
                                         }
                                     }];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
