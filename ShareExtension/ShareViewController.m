//
//  ShareViewController.m
//  ShareExtension
//
//  Created by Ivan Sein on 17.07.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import "ShareViewController.h"

#import <NCCommunication/NCCommunication.h>

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCRoom.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUtils.h"
#import "PlaceholderView.h"
#import "ShareConfirmationViewController.h"
#import "ShareTableViewCell.h"
#import "UIImageView+AFNetworking.h"

@interface ShareViewController () <UISearchControllerDelegate, UISearchResultsUpdating, ShareConfirmationViewControllerDelegate>
{
    UISearchController *_searchController;
    UITableViewController *_resultTableViewController;
    NSMutableArray *_filteredRooms;
    NSMutableArray *_rooms;
    PlaceholderView *_roomsBackgroundView;
    PlaceholderView *_roomSearchBackgroundView;
    TalkAccount *_activeAccount;
    ServerCapabilities *_serverCapabilities;
}

@end

@implementation ShareViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _filteredRooms = [[NSMutableArray alloc] init];
    
    // Configure database
    NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.nextcloud.Talk"] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];
    configuration.fileURL = databaseURL;
    configuration.schemaVersion= kTalkDatabaseSchemaVersion;
    configuration.objectClasses = @[TalkAccount.class, ServerCapabilities.class, NCRoom.class];
    NSError *error = nil;
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:&error];
    TalkAccount *managedActiveAccount = [TalkAccount objectsInRealm:realm where:(@"active = true")].firstObject;
    _activeAccount = [[TalkAccount alloc] initWithValue:managedActiveAccount];
    NSArray *accountRooms = [[NCRoomsManager sharedInstance] roomsForAccountId:_activeAccount.accountId witRealm:realm];
    _rooms = [[NSMutableArray alloc] initWithArray:accountRooms];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", _activeAccount.accountId];
    ServerCapabilities *managedServerCapabilities = [ServerCapabilities objectsInRealm:realm withPredicate:query].firstObject;
    _serverCapabilities = [[ServerCapabilities alloc] initWithValue:managedServerCapabilities];
    
    // Configure table views
    NSBundle *bundle = [NSBundle bundleForClass:[ShareTableViewCell class]];
    [self.tableView registerNib:[UINib nibWithNibName:kShareTableCellNibName bundle:bundle] forCellReuseIdentifier:kShareCellIdentifier];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 0, 0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    _resultTableViewController = [[UITableViewController alloc] init];
    _resultTableViewController.tableView.delegate = self;
    _resultTableViewController.tableView.dataSource = self;
    [_resultTableViewController.tableView registerNib:[UINib nibWithNibName:kShareTableCellNibName bundle:bundle] forCellReuseIdentifier:kShareCellIdentifier];
    _resultTableViewController.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 0, 0);
    _resultTableViewController.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.delegate = self;
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    
    // Configure navigation bar
    self.navigationItem.title = @"Share with";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    cancelButton.accessibilityHint = @"Double tap to dismiss sharing options";
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[UIColor whiteColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;

        self.navigationItem.searchController = _searchController;
        self.navigationItem.searchController.searchBar.searchTextField.backgroundColor = [NCUtils darkerColorFromColor:themeColor];
        _searchController.searchBar.tintColor = [UIColor whiteColor];
        UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
        searchTextField.tintColor = [UIColor whiteColor];
        searchTextField.textColor = [UIColor whiteColor];
        dispatch_async(dispatch_get_main_queue(), ^{
            searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search"
            attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:0.5]}];
        });
    } else if (@available(iOS 11.0, *)) {
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
    
    // Place resultTableViewController correctly
    self.definesPresentationContext = YES;
    
    // Rooms placeholder view
    _roomsBackgroundView = [[PlaceholderView alloc] init];
    [_roomsBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomsBackgroundView.placeholderText setText:@"You are not part of any conversation."];
    [_roomsBackgroundView.placeholderView setHidden:(_rooms.count > 0)];
    self.tableView.backgroundView = _roomsBackgroundView;
    
    _roomSearchBackgroundView = [[PlaceholderView alloc] init];
    [_roomSearchBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomSearchBackgroundView.placeholderText setText:@"No results found."];
    [_roomSearchBackgroundView.placeholderView setHidden:YES];
    [_roomSearchBackgroundView.loadingView setHidden:YES];
    _resultTableViewController.tableView.backgroundView = _roomSearchBackgroundView;
    
    // Fix uisearchcontroller animation
    self.extendedLayoutIncludesOpaqueBars = YES;
}

#pragma mark - Navigation buttons

- (void)cancelButtonPressed
{
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
    [self.extensionContext cancelRequestWithError:error];
}

#pragma mark - Shared items

- (void)setSharedItemToShareConfirmationViewController:(ShareConfirmationViewController *)shareConfirmationVC
{
    [self.extensionContext.inputItems enumerateObjectsUsingBlock:^(NSExtensionItem * _Nonnull extItem, NSUInteger idx, BOOL * _Nonnull stop) {
        [extItem.attachments enumerateObjectsUsingBlock:^(NSItemProvider * _Nonnull itemProvider, NSUInteger idx, BOOL * _Nonnull stop) {
            // Check if shared URL
            if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
                [itemProvider loadItemForTypeIdentifier:@"public.url"
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared URL = %@", item);
                                              NSURL *sharedURL = (NSURL *)item;
                                              shareConfirmationVC.type = ShareConfirmationTypeText;
                                              shareConfirmationVC.sharedText = sharedURL.absoluteString;
                                          }
                                      }];
            }
            // Check if shared text
            if ([itemProvider hasItemConformingToTypeIdentifier:@"public.plain-text"]) {
                [itemProvider loadItemForTypeIdentifier:@"public.plain-text"
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSString class]]) {
                                              NSLog(@"Shared Text = %@", item);
                                              NSString *sharedText = (NSString *)item;
                                              shareConfirmationVC.type = ShareConfirmationTypeText;
                                              shareConfirmationVC.sharedText = sharedText;
                                          }
                                      }];
            }
            // Check if shared image
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeImage
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared Image = %@", item);
                                              NSURL *imageURL = (NSURL *)item;
                                              NSString *imageName = imageURL.lastPathComponent;
                                              UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:imageURL]];
                                              shareConfirmationVC.type = ShareConfirmationTypeImage;
                                              shareConfirmationVC.sharedImageName = imageName;
                                              shareConfirmationVC.sharedImage = image;
                                          }
                                      }];
            }
        }];
    }];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self searchForRoomsWithString:_searchController.searchBar.text];
}

- (void)searchForRoomsWithString:(NSString *)searchString
{
    NSArray *filteredRooms = [self filterRoomsWithString:searchString];
    _filteredRooms = [[NSMutableArray alloc] initWithArray:filteredRooms];
    [_roomSearchBackgroundView.placeholderView setHidden:(_filteredRooms.count > 0)];
    [_resultTableViewController.tableView reloadData];
}

- (NSArray *)filterRoomsWithString:(NSString *)searchString
{
    NSPredicate *sPredicate = [NSPredicate predicateWithFormat:@"displayName CONTAINS[c] %@", searchString];
    return [_rooms filteredArrayUsingPredicate:sPredicate];
}

#pragma mark - ShareConfirmationViewController Delegate

- (void)shareConfirmationViewControllerDidFailed:(ShareConfirmationViewController *)viewController
{
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void)shareConfirmationViewControllerDidFinish:(ShareConfirmationViewController *)viewController
{
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == _resultTableViewController.tableView) {
        return _filteredRooms.count;
    }
    return _rooms.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kShareTableCellHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    if (tableView == _resultTableViewController.tableView) {
        room = [_filteredRooms objectAtIndex:indexPath.row];
    }
    
    ShareTableViewCell *cell = (ShareTableViewCell *)[tableView dequeueReusableCellWithIdentifier:kShareCellIdentifier];
    if (!cell) {
        cell = [[ShareTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kShareCellIdentifier];
    }
    
    cell.titleLabel.text = room.displayName;
    
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOne:
        {
            NSURLRequest *request = [[NCAPIController sharedInstance] createAvatarRequestForUser:room.name andSize:96 usingAccount:_activeAccount];
            [cell.avatarImageView setImageWithURLRequest:request placeholderImage:nil success:nil failure:nil];
        }
            break;
            
        case kNCRoomTypeGroup:
            [cell.avatarImageView setImage:[UIImage imageNamed:@"group-bg"]];
            break;
            
        case kNCRoomTypePublic:
            [cell.avatarImageView setImage:(room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
            break;
            
        case kNCRoomTypeChangelog:
            [cell.avatarImageView setImage:[UIImage imageNamed:@"changelog"]];
            break;
            
        default:
            break;
    }
    
    // Set objectType image
    if ([room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [cell.avatarImageView setImage:[UIImage imageNamed:@"file-bg"]];
    } else if ([room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [cell.avatarImageView setImage:[UIImage imageNamed:@"password-bg"]];
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    BOOL isFilteredTable = NO;
    if (tableView == _resultTableViewController.tableView) {
        room = [_filteredRooms objectAtIndex:indexPath.row];
        isFilteredTable = YES;
    }
    
    ShareConfirmationViewController *shareConfirmationVC = [[ShareConfirmationViewController alloc] initWithRoom:room account:_activeAccount serverCapabilities:_serverCapabilities];
    shareConfirmationVC.delegate = self;
    [self setSharedItemToShareConfirmationViewController:shareConfirmationVC];
    [self.navigationController pushViewController:shareConfirmationVC animated:YES];
}

@end
