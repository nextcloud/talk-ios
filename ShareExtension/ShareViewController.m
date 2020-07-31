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
#import "ShareTableViewCell.h"
#import "UIImageView+AFNetworking.h"

@interface ShareViewController () <UISearchControllerDelegate, UISearchResultsUpdating, NCCommunicationCommonDelegate>
{
    UISearchController *_searchController;
    UITableViewController *_resultTableViewController;
    NSMutableArray *_selectedRooms;
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
    
    _selectedRooms = [[NSMutableArray alloc] init];
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
    
    // Configure communication lib
    NSString *userToken = [[NCSettingsController sharedInstance] tokenForAccountId:_activeAccount.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", _activeAccount.accountId];
    _serverCapabilities = [[ServerCapabilities alloc] initWithValue:[ServerCapabilities objectsWithPredicate:query].firstObject];
    
    [[NCCommunicationCommon shared] setupWithAccount:_activeAccount.accountId user:_activeAccount.user userId:_activeAccount.userId password:userToken url:_activeAccount.server userAgent:userAgent capabilitiesGroup:@"group.com.nextcloud.Talk" webDavRoot:_serverCapabilities.webDAVRoot davRoot:nil nextcloudVersion:_serverCapabilities.versionMajor delegate:self];
    
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
    
    UIBarButtonItem *sendButton = [[UIBarButtonItem alloc] initWithTitle:@"Send" style:UIBarButtonItemStyleDone
                                                                  target:self action:@selector(sendButtonPressed)];
    sendButton.accessibilityHint = @"Double tap to share with selected conversations";
    self.navigationItem.rightBarButtonItem = sendButton;
    
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

#pragma mark - Shared items

- (void)sendSharedItem
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
                                              [self sendSharedString:sharedURL.absoluteString];
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
                                              [self sendSharedString:sharedText];
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
                                              UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:(NSURL *)item]];
                                              [self sendSharedImage:image];
                                          }
                                      }];
            }
        }];
    }];
}

#pragma mark - Navigation buttons

- (void)cancelButtonPressed
{
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
    [self.extensionContext cancelRequestWithError:error];
}

- (void)sendButtonPressed
{
    [self sendSharedItem];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

#pragma mark - Actions

- (void)sendSharedString:(NSString *)sharedString
{
    for (NCRoom *room in _selectedRooms) {
        [[NCAPIController sharedInstance] sendChatMessage:sharedString toRoom:room.token displayName:nil replyTo:-1 referenceId:nil forAccount:_activeAccount withCompletionBlock:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to send shared item");
            }
        }];
    }
}

- (void)sendSharedImage:(UIImage *)image
{
    NSString *fileNameServer = [NSString stringWithFormat:@"%@/%@/%@", _activeAccount.server, _serverCapabilities.webDAVRoot, @"image.png"];
    NSData *pngData = UIImagePNGRepresentation(image);
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileURL = [[tmpDirURL URLByAppendingPathComponent:@"image"] URLByAppendingPathExtension:@"jpg"];
    [pngData writeToFile:[fileURL path] atomically:YES];
    
    [[NCCommunication shared] uploadWithServerUrlFileName:fileNameServer fileNameLocalPath:[fileURL path] dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        NSLog(@"Progress: %@", progress);
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Error: %@", errorDescription);
    }];
}

#pragma mark - Utils

- (BOOL)isRoomAlreadySelected:(NCRoom *)selectedRoom
{
    for (NCRoom *room in _selectedRooms) {
        if ([room.internalId isEqualToString:selectedRoom.internalId]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeSelectedRoom:(NCRoom *)selectedRoom
{
    NCRoom *roomToDelete = nil;
    for (NCRoom *room in _selectedRooms) {
        if ([room.internalId isEqualToString:selectedRoom.internalId]) {
            roomToDelete = room;
            break;
        }
    }
    
    if (roomToDelete) {
        [_selectedRooms removeObject:roomToDelete];
    }
}

#pragma mark - NCCommunicationCommon Delegate

- (void)authenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    // The pinnning check
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
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
    
    UIImageView *checkboxChecked = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-checked"]];
    UIImageView *checkboxUnchecked = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-unchecked"]];
    cell.accessoryView = ([self isRoomAlreadySelected:room]) ? checkboxChecked : checkboxUnchecked;
        
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
    
    if (![self isRoomAlreadySelected:room]) {
        [_selectedRooms addObject:room];
    } else {
        [self removeSelectedRoom:room];
    }
        
    [tableView beginUpdates];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [tableView endUpdates];
    
    // Refresh table view if selection was done in filtered table.
    if (isFilteredTable) {
        [self.tableView reloadData];
    }
}

@end
