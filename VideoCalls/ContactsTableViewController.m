//
//  ContactsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "ContactsTableViewController.h"

#import "AFNetworking.h"
#import "AuthenticationViewController.h"
#import "LoginViewController.h"
#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCSettingsController.h"
#import "SearchTableViewController.h"

@interface ContactsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSMutableArray *_contacts;
    BOOL _networkDisconnectedRetry;
    UISearchController *_searchController;
    SearchTableViewController *_resultTableViewController;
}

@end

@implementation ContactsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contacts = [[NSMutableArray alloc] init];
    _networkDisconnectedRetry = NO;
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    
    _resultTableViewController = [[SearchTableViewController alloc] init];
    
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    self.tableView.tableHeaderView = _searchController.searchBar;
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.dimsBackgroundDuringPresentation = NO;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginHasBeenCompleted:) name:NCLoginCompletedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityHasChanged:) name:NCNetworkReachabilityHasChangedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self checkConnectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)loginHasBeenCompleted:(NSNotification *)notification
{
    if ([notification.userInfo objectForKey:kNCTokenKey]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)networkReachabilityHasChanged:(NSNotification *)notification
{
    AFNetworkReachabilityStatus status = [[notification.userInfo objectForKey:kNCNetworkReachabilityKey] intValue];
    NSLog(@"Network Status:%ld", (long)status);
}

- (void)checkConnectionState
{
    ConnectionState connectionState = [[NCConnectionController sharedInstance] connectionState];
    
    switch (connectionState) {
        case kConnectionStateNotServerProvided:
        {
            LoginViewController *loginVC = [[LoginViewController alloc] init];
            [self presentViewController:loginVC animated:YES completion:nil];
        }
            break;
        case kConnectionStateAuthenticationNeeded:
        {
            AuthenticationViewController *authVC = [[AuthenticationViewController alloc] init];
            [self presentViewController:authVC animated:YES completion:nil];
        }
            break;
            
        case kConnectionStateNetworkDisconnected:
        {
            NSLog(@"No network connection!");
            if (!_networkDisconnectedRetry) {
                _networkDisconnectedRetry = YES;
                double delayInSeconds = 1.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [self checkConnectionState];
                });
            }
        }
            break;
            
        default:
        {
            [self getContacts];
            _networkDisconnectedRetry = NO;
        }
            break;
    }
}

- (void)getContacts
{
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSMutableArray *contacts, NSError *error, NSInteger errorCode) {
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
    [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSMutableArray *contacts, NSError *error, NSInteger errorCode) {
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NCUser *contact = [_contacts objectAtIndex:indexPath.row];
    ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
    }
    
    cell.labelTitle.text = contact.name;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCUser *contact = [_contacts objectAtIndex:indexPath.row];
    
    [[NCAPIController sharedInstance] createRoomWith:contact.userId
                                              ofType:kNCRoomTypeOneToOneCall
                                 withCompletionBlock:^(NSString *token, NSError *error, NSInteger errorCode) {
        if (!error) {
            // Join created room.
            NSLog(@"Room %@ with %@ created", token, contact.name);
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil
                                                            message:[NSString stringWithFormat:@"Room %@ with %@ created", token, contact.name]
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        } else {
            NSLog(@"Failed creating a room with %@", contact.name);
        }
    }];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
