/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ShareViewController.h"

#import <Intents/Intents.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCIntentController.h"
#import "NCRoom.h"
#import "PlaceholderView.h"
#import "ShareTableViewCell.h"
#import "NCKeyChainController.h"
#import "NextcloudTalk-Swift.h"

@interface ShareViewController () <UISearchControllerDelegate, UISearchResultsUpdating, ShareConfirmationViewControllerDelegate>
{
    UISearchController *_searchController;
    UITableViewController *_resultTableViewController;
    NSMutableArray *_filteredRooms;
    NSMutableArray *_rooms;
    PlaceholderView *_roomsBackgroundView;
    PlaceholderView *_roomSearchBackgroundView;
    TalkAccount *_shareAccount;
    ServerCapabilities *_serverCapabilities;
    RLMRealm *_realm;
}

@end

@implementation ShareViewController

- (id)initToForwardMessage:(NSString *)message fromChatViewController:(UIViewController *)chatViewController
{
    self = [super init];
    if (self) {
        self.chatViewController = chatViewController;
        self.forwardMessage = message;
        self.forwarding = YES;
    }
    
    return self;
}

- (id)initToForwardObjectShareMessage:(NCChatMessage *)objectShareMessage fromChatViewController:(UIViewController *)chatViewController
{
    self = [super init];
    if (self) {
        self.chatViewController = chatViewController;
        self.forwardObjectShareMessage = objectShareMessage;
        self.forwarding = YES;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _filteredRooms = [[NSMutableArray alloc] init];
    
    // Configure database
    NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
    NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:databaseURL.path]) {
        @try {
            NSError *error = nil;
            
            // schemaVersionAtURL throws an exception when file is not readable
            uint64_t currentSchemaVersion = [RLMRealm schemaVersionAtURL:databaseURL encryptionKey:nil error:&error];
            
            if (error || currentSchemaVersion != kTalkDatabaseSchemaVersion) {
                NSLog(@"Current schemaVersion is %llu app schemaVersion is %llu", currentSchemaVersion, kTalkDatabaseSchemaVersion);
                NSLog(@"Database needs migration -> don't open database from extension");
                
                NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
                [self.extensionContext cancelRequestWithError:error];
                return;
            } else {
                NSLog(@"Current schemaVersion is %llu app schemaVersion is %llu", currentSchemaVersion, kTalkDatabaseSchemaVersion);
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Reading schemaVersion failed: %@", exception.reason);
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            [self.extensionContext cancelRequestWithError:error];
            return;
        }
    } else {
        NSLog(@"Database does not exist -> main app needs to run before extension.");
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
        [self.extensionContext cancelRequestWithError:error];
        return;
    }
    
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = databaseURL;
    configuration.schemaVersion= kTalkDatabaseSchemaVersion;
    configuration.objectClasses = @[TalkAccount.class, NCRoom.class, ServerCapabilities.class, FederatedCapabilities.class];
    configuration.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
        // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
    };
    NSError *error = nil;
        
    // When running as an extension, set the default configuration to make sure we always use the correct realm-file
    if ([[[NSBundle mainBundle] bundlePath] hasSuffix:@".appex"]) {
        [RLMRealmConfiguration setDefaultConfiguration:configuration];
    }
    _realm = [RLMRealm realmWithConfiguration:configuration error:&error];
    
    if (self.extensionContext && self.extensionContext.intent && [self.extensionContext.intent isKindOfClass:[INSendMessageIntent class]]) {
        INSendMessageIntent *intent = (INSendMessageIntent *)self.extensionContext.intent;

        NSPredicate *query = [NSPredicate predicateWithFormat:@"internalId = %@", intent.conversationIdentifier];
        NCRoom *managedRoom = [NCRoom objectsInRealm:_realm withPredicate:query].firstObject;

        if (managedRoom) {
            NCRoom *room = [[NCRoom alloc] initWithValue:managedRoom];

            if ([room isFederated]) {
                [self showFederatedAlert];

                NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
                [self.extensionContext cancelRequestWithError:error];
                return;
            }

            NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", room.accountId];
            TalkAccount *managedAccount = [TalkAccount objectsInRealm:_realm withPredicate:query].firstObject;

            if (managedAccount) {
                TalkAccount *intentAccount = [[TalkAccount alloc] initWithValue:managedAccount];
                [self setupShareViewForAccount:intentAccount];
                ShareConfirmationViewController *shareConfirmationVC = [[ShareConfirmationViewController alloc] initWithRoom:room thread:nil account:intentAccount serverCapabilities:_serverCapabilities];
                shareConfirmationVC.delegate = self;
                shareConfirmationVC.isModal = YES;
                [self setSharedItemToShareConfirmationViewController:shareConfirmationVC];
                [self.navigationController pushViewController:shareConfirmationVC animated:YES];

                return;
            }
        }
    }
    
    [self setupShareViewForAccount:nil];
    
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

    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    // Configure navigation bar
    [NCAppBranding styleViewController:self];

    self.navigationItem.title = _forwarding ? NSLocalizedString(@"Forward to", nil) : NSLocalizedString(@"Share with", nil);

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    cancelButton.accessibilityHint = NSLocalizedString(@"Double tap to dismiss sharing options", nil);
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;

    // Place resultTableViewController correctly
    self.definesPresentationContext = YES;
    
    // Rooms placeholder view
    _roomsBackgroundView = [[PlaceholderView alloc] init];
    [_roomsBackgroundView setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomsBackgroundView.placeholderTextView setText:NSLocalizedString(@"You are not part of any conversation", nil)];
    [_roomsBackgroundView.placeholderView setHidden:(_rooms.count > 0)];
    [_roomsBackgroundView.loadingView setHidden:YES];
    self.tableView.backgroundView = _roomsBackgroundView;
    
    _roomSearchBackgroundView = [[PlaceholderView alloc] init];
    [_roomSearchBackgroundView setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomSearchBackgroundView.placeholderTextView setText:NSLocalizedString(@"No results found", nil)];
    [_roomSearchBackgroundView.placeholderView setHidden:YES];
    [_roomSearchBackgroundView.loadingView setHidden:YES];
    _resultTableViewController.tableView.backgroundView = _roomSearchBackgroundView;
    
    // Fix uisearchcontroller animation
    self.extendedLayoutIncludesOpaqueBars = YES;
}

- (ServerCapabilities *)getServerCapabilitesForAccount:(TalkAccount *)account withRealm:(RLMRealm *)realm;
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
    ServerCapabilities *managedServerCapabilities = [ServerCapabilities objectsInRealm:realm withPredicate:query].firstObject;
    if (managedServerCapabilities) {
        return [[ServerCapabilities alloc] initWithValue:managedServerCapabilities];
    }
    
    return nil;
}

#pragma mark - Navigation buttons

- (void)cancelButtonPressed
{
    [self.delegate shareViewControllerDidCancel:self];
    
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
    [self.extensionContext cancelRequestWithError:error];
}

#pragma mark - Accounts

- (void)setProfileButtonForAccount:(TalkAccount *)account
{
    UIButton *profileButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [profileButton addTarget:self action:@selector(showAccountSelector) forControlEvents:UIControlEventTouchUpInside];
    profileButton.frame = CGRectMake(0, 0, 30, 30);
    profileButton.accessibilityLabel = NSLocalizedString(@"User profile and settings", nil);
    profileButton.accessibilityHint = NSLocalizedString(@"Double tap to go to user profile and application settings", nil);
    
    UIImage *profileImage = [[NCAPIController sharedInstance] userProfileImageForAccount:account withStyle:self.traitCollection.userInterfaceStyle];
    if (profileImage) {
        UIGraphicsBeginImageContextWithOptions(profileButton.bounds.size, NO, 3.0);
        [[UIBezierPath bezierPathWithRoundedRect:profileButton.bounds cornerRadius:profileButton.bounds.size.height] addClip];
        [profileImage drawInRect:profileButton.bounds];
        profileImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [profileButton setImage:profileImage forState:UIControlStateNormal];
    } else {
        UIImage *profileImage = [UIImage systemImageNamed:@"person"];
        [profileButton setImage:profileImage forState:UIControlStateNormal];
        profileButton.contentMode = UIViewContentModeCenter;
    }
    
    UIBarButtonItem *profileBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:profileButton];
	NSLayoutConstraint *width = [profileBarButtonItem.customView.widthAnchor constraintEqualToConstant:30];
	width.active = YES;
	NSLayoutConstraint *height = [profileBarButtonItem.customView.heightAnchor constraintEqualToConstant:30];
	height.active = YES;
    
    [self.navigationItem setRightBarButtonItem:profileBarButtonItem];
}

- (void)setupShareViewForAccount:(TalkAccount *)account
{
    _shareAccount = account;
    if (!account) {
        TalkAccount *managedActiveAccount = [TalkAccount objectsInRealm:_realm where:(@"active = true")].firstObject;
        if (managedActiveAccount) {
            _shareAccount = [[TalkAccount alloc] initWithValue:managedActiveAccount];
        } else {
            // No account is configured in the app yet
            return;
        }
    }
    
    // Show account button selector if there are more than one account
    if ([TalkAccount allObjectsInRealm:_realm].count > 1) {
        [self setProfileButtonForAccount:_shareAccount];
    }
    
    NSArray *accountRooms = [[NCDatabaseManager sharedInstance] roomsForAccountId:_shareAccount.accountId withRealm:_realm];
    _rooms = [[NSMutableArray alloc] initWithArray:accountRooms];
    _serverCapabilities = [self getServerCapabilitesForAccount:_shareAccount withRealm:_realm];
    
    [self.tableView reloadData];
}

- (void)showAccountSelector
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Accounts", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSMutableArray *allAccounts = [NSMutableArray new];
    for (TalkAccount *managedAccount in [TalkAccount allObjectsInRealm:_realm]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:managedAccount];
        [allAccounts addObject:account];
        
        UIAlertAction *action = [UIAlertAction actionWithTitle:account.userDisplayName
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [self setupShareViewForAccount:account];
                                                       }];
        if ([_shareAccount.accountId isEqualToString:account.accountId]) {
            [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        }
        
        [optionsActionSheet addAction:action];
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

#pragma mark - Shared items

- (void)setSharedItemToShareConfirmationViewController:(ShareConfirmationViewController *)shareConfirmationVC
{
    NSLog(@"Received %lu files to share", [self.extensionContext.inputItems count]);
    
    [self.extensionContext.inputItems enumerateObjectsUsingBlock:^(NSExtensionItem * _Nonnull extItem, NSUInteger idx, BOOL * _Nonnull stop) {
        [extItem.attachments enumerateObjectsUsingBlock:^(NSItemProvider * _Nonnull itemProvider, NSUInteger idx, BOOL * _Nonnull stop) {
            // Check if shared video
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeMovie
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared Video = %@", item);
                                              NSURL *videoURL = (NSURL *)item;
                                            
                                              [shareConfirmationVC.shareItemController addItemWithURL:videoURL];
                                          }
                                      }];
                return;
            }
            // Check if shared file
            // Make sure this is checked before image! Otherwise sharing images from Mail won't work >= iOS 13
            if ([itemProvider hasItemConformingToTypeIdentifier:@"public.file-url"]) {
                [itemProvider loadItemForTypeIdentifier:@"public.file-url"
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared File URL = %@", item);
                                              NSURL *fileURL = (NSURL *)item;
                                              
                                              [shareConfirmationVC.shareItemController addItemWithURL:fileURL];
                                          }
                                      }];
                return;
            }
            // Check if shared image
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeImage
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared Image = %@", item);
                                              NSURL *imageURL = (NSURL *)item;
                                              [shareConfirmationVC.shareItemController addItemWithURL:imageURL];
                                          } else if ([(NSObject *)item isKindOfClass:[UIImage class]]) {
                                              // Occurs when sharing a screenshot
                                              NSLog(@"Shared UIImage = %@", item);
                                              UIImage *image = (UIImage *)item;
                                              [shareConfirmationVC.shareItemController addItemWithImage:image];
                                          } else if ([(NSObject *)item isKindOfClass:[NSData class]]) {
                                              // Screenshots starting iOS 26
                                              NSLog(@"Shared UIImage = %@", item);
                                              UIImage *image = [UIImage imageWithData:(NSData *)item];
                                              [shareConfirmationVC.shareItemController addItemWithImage:image];
                                          }
                                      }];
                return;
            }
            // Check if shared URL
            if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
                [itemProvider loadItemForTypeIdentifier:@"public.url"
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSURL class]]) {
                                              NSLog(@"Shared URL = %@", item);
                                              NSURL *sharedURL = (NSURL *)item;
                                              [shareConfirmationVC shareText:sharedURL.absoluteString];
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
                                              [shareConfirmationVC shareText:sharedText];
                                          }
                                      }];
            }
            // Check if vcard
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeVCard]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeVCard
                                                options:nil
                                      completionHandler:^(id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
                                          if ([(NSObject *)item isKindOfClass:[NSData class]]) {
                                              NSLog(@"Shared Contact = %@", item);
                                              NSData *contactData = (NSData *)item;
                                              [shareConfirmationVC.shareItemController addItemWithContactData:contactData];
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

- (void)shareConfirmationViewControllerDidFail:(ShareConfirmationViewController *)viewController
{
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void)shareConfirmationViewControllerDidFinish:(ShareConfirmationViewController *)viewController
{
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void)shareConfirmationViewControllerDidCancel:(ShareConfirmationViewController *)viewController
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

    [cell.avatarImageView setAvatarFor:room];
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];

    if (tableView == _resultTableViewController.tableView) {
        room = [_filteredRooms objectAtIndex:indexPath.row];
    }

    if ([room isFederated]) {
        [self showFederatedAlert];
        return;
    }

    BOOL hasChatPermission = ![[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatPermission] || (room.permissions & NCPermissionChat) != 0;

    if (!hasChatPermission || room.readOnlyState == NCRoomReadOnlyStateReadOnly) {
        [self showChatPermissionAlert];
        return;
    }

    ShareConfirmationViewController *shareConfirmationVC = [[ShareConfirmationViewController alloc] initWithRoom:room thread:nil account:_shareAccount serverCapabilities:_serverCapabilities];
    shareConfirmationVC.delegate = self;
    if (_forwardMessage) {
        shareConfirmationVC.delegate = (id<ShareConfirmationViewControllerDelegate>)_chatViewController;
        shareConfirmationVC.forwardingMessage = YES;
        [shareConfirmationVC shareText:_forwardMessage];
    } else if (_forwardObjectShareMessage) {
        shareConfirmationVC.delegate = (id<ShareConfirmationViewControllerDelegate>)_chatViewController;
        shareConfirmationVC.forwardingMessage = YES;
        [shareConfirmationVC shareObjectShareMessage:_forwardObjectShareMessage];
    } else {
        [self setSharedItemToShareConfirmationViewController:shareConfirmationVC];
    }
    [self.navigationController pushViewController:shareConfirmationVC animated:YES];
}

- (void)showChatPermissionAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Cannot share to conversation", nil)
                                 message:NSLocalizedString(@"Either you don't have chat permission or the conversation is read-only.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];

    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFederatedAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Cannot share to conversation", nil)
                                 message:NSLocalizedString(@"Sharing to a federated conversation is not supported.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];

    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
