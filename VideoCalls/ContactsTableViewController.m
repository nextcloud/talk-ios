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
#import "PlaceholderView.h"
#import "SearchTableViewController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

NSString * const NCSelectedContactForVoiceCallNotification  = @"NCSelectedContactForVoiceCallNotification";
NSString * const NCSelectedContactForVideoCallNotification  = @"NCSelectedContactForVideoCallNotification";
NSString * const NCSelectedContactForChatNotification       = @"NCSelectedContactForChatNotification";

@interface ContactsTableViewController () <UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    NSDictionary *_contacts;
    NSArray *_indexes;
    UISearchController *_searchController;
    SearchTableViewController *_resultTableViewController;
    PlaceholderView *_contactsBackgroundView;
    NSURLSessionTask *_searchContactsTask;
}

@end

@implementation ContactsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contacts = [[NSDictionary alloc] init];
    _indexes = [[NSArray alloc] init];
    
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
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // Contacts placeholder view
    _contactsBackgroundView = [[PlaceholderView alloc] init];
    [_contactsBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"contacts-placeholder"]];
    [_contactsBackgroundView.placeholderText setText:@"No contacts found."];
    [_contactsBackgroundView.placeholderView setHidden:YES];
    [_contactsBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _contactsBackgroundView;
    
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
    [[NCAPIController sharedInstance] getContactsWithSearchParam:nil andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            _contacts = contacts;
            _indexes = indexes;
            [_contactsBackgroundView.loadingView stopAnimating];
            [_contactsBackgroundView.loadingView setHidden:YES];
            [_contactsBackgroundView.placeholderView setHidden:(contacts.count > 0)];
            [self.tableView reloadData];
        } else {
            NSLog(@"Error while trying to get contacts: %@", error);
        }
    }];
}

- (void)searchForContactsWithString:(NSString *)searchString
{
    [_searchContactsTask cancel];
    _searchContactsTask = [[NCAPIController sharedInstance] getContactsWithSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            _resultTableViewController.contacts = contacts;
            _resultTableViewController.indexes = indexes;
            [_resultTableViewController.tableView reloadData];
        } else {
            if (error.code != -999) {
                NSLog(@"Error while searching for contacts: %@", error);
            }
        }
    }];
}

- (void)presentOptionsForContactAtIndexPath:(NSIndexPath *)indexPath
{
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
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:contact.name
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *videocallAction = [UIAlertAction actionWithTitle:@"Video call"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^void (UIAlertAction *action) {
                                                                [self createRoomWithContact:contact forCall:YES withVideo:YES];
                                                            }];
    
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:@"Call"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [self createRoomWithContact:contact forCall:YES withVideo:NO];
                                                       }];
    
    UIAlertAction *chatAction = [UIAlertAction actionWithTitle:@"Chat"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [self createRoomWithContact:contact forCall:NO withVideo:NO];
                                                       }];
    
    [videocallAction setValue:[[UIImage imageNamed:@"videocall-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [callAction setValue:[[UIImage imageNamed:@"call-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [chatAction setValue:[[UIImage imageNamed:@"chat-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    
    [optionsActionSheet addAction:videocallAction];
    [optionsActionSheet addAction:callAction];
    [optionsActionSheet addAction:chatAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    UITableView *tableView = (_searchController.active) ? _resultTableViewController.tableView : self.tableView;
    optionsActionSheet.popoverPresentationController.sourceView = tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)createRoomWithContact:(NCUser *)contact forCall:(BOOL)call withVideo:(BOOL)video
{
    [[NCAPIController sharedInstance] createRoomWith:contact.userId
                                              ofType:kNCRoomTypeOneToOneCall
                                             andName:nil
                                 withCompletionBlock:^(NSString *token, NSError *error) {
                                     if (!error) {
                                         NSLog(@"Room %@ with %@ created", token, contact.name);
                                         if (!call) {
                                             [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedContactForChatNotification
                                                                                                 object:self
                                                                                               userInfo:@{@"token":token}];
                                         } else {
                                             if (video) {
                                                 [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedContactForVideoCallNotification
                                                                                                     object:self
                                                                                                   userInfo:@{@"token":token}];
                                             } else {
                                                 [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedContactForVoiceCallNotification
                                                                                                     object:self
                                                                                                   userInfo:@{@"token":token}];
                                             }
                                         }
                                     } else {
                                         NSLog(@"Failed creating a room with %@", contact.name);
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
    return [_indexes objectAtIndex:section];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return _indexes;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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
    if ([NCConnectionController sharedInstance].connectionState == kConnectionStateDisconnected) {
        [[NCUserInterfaceController sharedInstance] presentOfflineWarningAlert];
    } else {
        [self presentOptionsForContactAtIndexPath:indexPath];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
