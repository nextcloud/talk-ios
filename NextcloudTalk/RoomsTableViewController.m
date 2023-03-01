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

#import "RoomsTableViewController.h"

@import NextcloudKit;
#import <Realm/Realm.h>

#import "AFNetworking.h"
#import "AFImageDownloader.h"
#import "UIButton+AFNetworking.h"
#import "UIImageView+AFNetworking.h"

#import "NextcloudTalk-Swift.h"

#import "CCCertificate.h"
#import "FTPopOverMenu.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatViewController.h"
#import "NCDatabaseManager.h"
#import "NCConnectionController.h"
#import "NCNavigationController.h"
#import "NCNotificationController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "NewRoomTableViewController.h"
#import "NotificationCenterNotifications.h"
#import "PlaceholderView.h"
#import "RoomCreation2TableViewController.h"
#import "RoomInfoTableViewController.h"
#import "RoomSearchTableViewController.h"
#import "RoomTableViewCell.h"
#import "UIBarButtonItem+Badge.h"

typedef void (^FetchRoomsCompletionBlock)(BOOL success);

@interface RoomsTableViewController () <CCCertificateDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating>
{
    RLMNotificationToken *_rlmNotificationToken;
    NSMutableArray *_rooms;
    UIRefreshControl *_refreshControl;
    BOOL _allowEmptyGroupRooms;
    UISearchController *_searchController;
    NSString *_searchString;
    RoomSearchTableViewController *_resultTableViewController;
    NCUnifiedSearchController *_unifiedSearchController;
    PlaceholderView *_roomsBackgroundView;
    UIBarButtonItem *_settingsButton;
    NSTimer *_refreshRoomsTimer;
    NSIndexPath *_nextRoomWithMentionIndexPath;
    NSIndexPath *_lastRoomWithMentionIndexPath;
    UIButton *_unreadMentionsBottomButton;
}

@end

@implementation RoomsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    __weak typeof(self) weakSelf = self;
    _rlmNotificationToken = [[RLMRealm defaultRealm] addNotificationBlock:^(NSString *notification, RLMRealm * realm) {
        [weakSelf refreshRoomList];
    }];
    
    [self.tableView registerNib:[UINib nibWithNibName:kRoomTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomCellIdentifier];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    
    self.addButton.accessibilityLabel = NSLocalizedString(@"Create a new conversation", nil);
    self.addButton.accessibilityHint = NSLocalizedString(@"Double tap to create group, public or one to one conversations.", nil);
    
    [UIImageView setSharedImageDownloader:[[NCAPIController sharedInstance] imageDownloaderAvatars]];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    _resultTableViewController = [[RoomSearchTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];
    
    [self setupNavigationBar];
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    // Rooms placeholder view
    _roomsBackgroundView = [[PlaceholderView alloc] init];
    [_roomsBackgroundView setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomsBackgroundView.placeholderTextView setText:NSLocalizedString(@"You are not part of any conversation. Press + to start a new one.", nil)];
    [_roomsBackgroundView.placeholderView setHidden:YES];
    [_roomsBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _roomsBackgroundView;
    
    // Unread mentions bottom indicator
    _unreadMentionsBottomButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 126, 28)];
    _unreadMentionsBottomButton.backgroundColor = [NCAppBranding themeColor];
    [_unreadMentionsBottomButton setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];
    _unreadMentionsBottomButton.titleLabel.font = [UIFont systemFontOfSize:14];
    _unreadMentionsBottomButton.layer.cornerRadius = 14;
    _unreadMentionsBottomButton.clipsToBounds = YES;
    _unreadMentionsBottomButton.hidden = NO;
    _unreadMentionsBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    _unreadMentionsBottomButton.contentEdgeInsets = UIEdgeInsetsMake(0.0f, 12.0f, 0.0f, 12.0f);
    _unreadMentionsBottomButton.titleLabel.minimumScaleFactor = 0.9f;
    _unreadMentionsBottomButton.titleLabel.numberOfLines = 1;
    _unreadMentionsBottomButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    NSString *unreadMentionsString = NSLocalizedString(@"Unread mentions", nil);
    NSString *buttonText = [NSString stringWithFormat:@"↓ %@", unreadMentionsString];
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14]};
    CGRect textSize = [buttonText boundingRectWithSize:CGSizeMake(300, 28) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
    CGFloat buttonWidth = textSize.size.width + 20;

    [_unreadMentionsBottomButton addTarget:self action:@selector(unreadMentionsBottomButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_unreadMentionsBottomButton setTitle:buttonText forState:UIControlStateNormal];
    
    [self.view addSubview:_unreadMentionsBottomButton];

    // Set selection color for selected cells
    [self.tableView setTintColor:UIColor.systemGray4Color];

    // Remove the backButtonTitle, otherwise when we transition to a conversation, "Back" is briefly visible
    self.navigationItem.backButtonTitle = @"";

    NSDictionary *views = @{@"unreadMentionsButton": _unreadMentionsBottomButton};
    NSDictionary *metrics = @{@"buttonWidth": @(buttonWidth)};
    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=0)-[unreadMentionsButton(28)]-30-|" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[unreadMentionsButton(buttonWidth)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:@[[_unreadMentionsBottomButton.centerXAnchor constraintEqualToAnchor:margins.centerXAnchor]]];
    [self.view addConstraint:[_unreadMentionsBottomButton.bottomAnchor constraintEqualToAnchor:self.tableView.safeAreaLayoutGuide.bottomAnchor constant:-20]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomsDidUpdate:) name:NCRoomsManagerDidUpdateRoomsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationWillBePresented:) name:NCNotificationControllerWillPresentNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCapabilitiesUpdated:) name:NCServerCapabilitiesUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userProfileImageUpdated:) name:NCUserProfileImageUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCSelectedContactForChatNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
}

- (void)setupNavigationBar
{
    [self setNavigationLogoButton];
    [self createRefreshControl];
    
    self.addButton.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;

    self.navigationItem.searchController = _searchController;
    self.navigationItem.searchController.searchBar.searchTextField.backgroundColor = [NCUtils searchbarBGColorForColor:themeColor];

    if (@available(iOS 16.0, *)) {
        self.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementStacked;
    }
    
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
    
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)dealloc
{
    [_rlmNotificationToken invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController sharedInstance].connectionState];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self refreshRoomList];
    
    self.clearsSelectionOnViewWillAppear = self.splitViewController.isCollapsed;

    if (self.splitViewController.isCollapsed) {
        [self setSelectedRoomToken:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self stopRefreshRoomsTimer];
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

- (void)roomsDidUpdate:(NSNotification *)notification
{
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (error) {
        NSLog(@"Error while trying to get rooms: %@", error);
        if ([error code] == NSURLErrorServerCertificateUntrusted) {
            NSLog(@"Untrusted certificate");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
            });
            
        }
    }
    
    [_refreshControl endRefreshing];
}

- (void)notificationWillBePresented:(NSNotification *)notification
{
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO withCompletionBlock:nil];
    [self setUnreadMessageForInactiveAccountsIndicator];
}

- (void)serverCapabilitiesUpdated:(NSNotification *)notification
{
    [self setupNavigationBar];
}

- (void)userProfileImageUpdated:(NSNotification *)notification
{
    [self setProfileButton];
}

- (void)appWillEnterForeground:(NSNotification *)notification
{
    if ([NCConnectionController sharedInstance].appState == kAppStateReady) {
        [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES withCompletionBlock:nil];
        [self startRefreshRoomsTimer];

        dispatch_async(dispatch_get_main_queue(), ^{
            // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
            [self setProfileButton];
            [self setUnreadMessageForInactiveAccountsIndicator];
        });
    }
    
    [FTPopOverMenu dismiss];
}

- (void)appWillResignActive:(NSNotification *)notification
{
    [self stopRefreshRoomsTimer];
}

- (void)roomCreated:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshRooms];
        NSString *roomToken = [notification.userInfo objectForKey:@"token"];
        [self setSelectedRoomToken:roomToken];
    });
}

#pragma mark - Interface Builder Actions

- (IBAction)addButtonPressed:(id)sender
{
    NewRoomTableViewController *newRoowVC = [[NewRoomTableViewController alloc] init];
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:newRoowVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Refresh Timer

- (void)startRefreshRoomsTimer
{
    [self stopRefreshRoomsTimer];
    _refreshRoomsTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(refreshRooms) userInfo:nil repeats:YES];
}

- (void)stopRefreshRoomsTimer
{
    [_refreshRoomsTimer invalidate];
    _refreshRoomsTimer = nil;
}

- (void)refreshRooms
{
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES withCompletionBlock:nil];

    if ([NCConnectionController sharedInstance].connectionState == kConnectionStateConnected) {
        [[NCRoomsManager sharedInstance] resendOfflineMessagesWithCompletionBlock:nil];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
        [self setProfileButton];
        [self setUnreadMessageForInactiveAccountsIndicator];
    });
}

#pragma mark - Refresh Control

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = [NCAppBranding themeTextColor];

    [_refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = _refreshControl;
}

- (void)deleteRefreshControl
{
    [_refreshControl endRefreshing];
    self.refreshControl = nil;
}

- (void)refreshControlTarget
{
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES withCompletionBlock:nil];
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

#pragma mark - Title menu

- (void)setNavigationLogoButton
{
    UIImage *logoImage = [UIImage imageNamed:[NCAppBranding navigationLogoImageName]];
    if (multiAccountEnabled) {
        UIButton *logoButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        [logoButton setImage:logoImage forState:UIControlStateNormal];
        [logoButton addTarget:self action:@selector(showAccountsMenu:) forControlEvents:UIControlEventTouchUpInside];
        self.navigationItem.titleView = logoButton;
    } else {
        self.navigationItem.titleView = [[UIImageView alloc] initWithImage:logoImage];
    }
    self.navigationItem.titleView.accessibilityLabel = talkAppName;
    self.navigationItem.titleView.accessibilityHint = NSLocalizedString(@"Double tap to change accounts or add a new one", nil);
}

-(void)showAccountsMenu:(UIButton*)sender
{
    NSMutableArray *menuArray = [NSMutableArray new];
    NSMutableArray *actionsArray = [NSMutableArray new];
    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        NSString *accountName = account.userDisplayName;
        UIImage *accountImage = [[NCAPIController sharedInstance] userProfileImageForAccount:account withStyle:self.traitCollection.userInterfaceStyle andSize:CGSizeMake(72, 72)];
        UIImageView *accessoryImageView = (account.active) ? [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"checkbox-checked"]] : nil;
        FTPopOverMenuModel *accountModel = [[FTPopOverMenuModel alloc] initWithTitle:accountName image:accountImage selected:NO accessoryView:accessoryImageView];
        [menuArray addObject:accountModel];
        [actionsArray addObject:account];
    }
    FTPopOverMenuModel *addAccountModel = [[FTPopOverMenuModel alloc] initWithTitle:NSLocalizedString(@"Add account", nil) image:[UIImage imageNamed:@"add-settings"] selected:NO accessoryView:nil];
    [menuArray addObject:addAccountModel];
    [actionsArray addObject:@"AddAccountAction"];
    
    FTPopOverMenuConfiguration *menuConfiguration = [[FTPopOverMenuConfiguration alloc] init];
    menuConfiguration.menuIconMargin = 12;
    menuConfiguration.menuTextMargin = 12;
    menuConfiguration.imageSize = CGSizeMake(24, 24);
    menuConfiguration.separatorInset = UIEdgeInsetsMake(0, 48, 0, 0);
    menuConfiguration.menuRowHeight = 44;
    menuConfiguration.autoMenuWidth = YES;
    menuConfiguration.textFont = [UIFont systemFontOfSize:15];
    menuConfiguration.shadowOpacity = 0.8;
    menuConfiguration.roundedImage = YES;
    menuConfiguration.defaultSelection = YES;
    menuConfiguration.borderWidth = 1;
    menuConfiguration.borderColor = [NCAppBranding placeholderColor];
    menuConfiguration.backgroundColor = [NCAppBranding backgroundColor];
    menuConfiguration.separatorColor = [NCAppBranding placeholderColor];
    menuConfiguration.textColor = [UIColor labelColor];
    menuConfiguration.shadowColor = [UIColor secondaryLabelColor];

    [FTPopOverMenu showForSender:sender
                   withMenuArray:menuArray
                      imageArray:nil
                   configuration:menuConfiguration
                       doneBlock:^(NSInteger selectedIndex) {
                           id action = [actionsArray objectAtIndex:selectedIndex];
                           if ([action isKindOfClass:[TalkAccount class]]) {
                               TalkAccount *account = action;
                               [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:account.accountId];
                           } else {
                               [[NCUserInterfaceController sharedInstance] presentLoginViewController];
                           }
                       } dismissBlock:nil];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *searchString = _searchController.searchBar.text;
    // Do not search for the same term twice (e.g. when the searchbar retrieves back the focus)
    if ([_searchString isEqualToString:searchString]) {return;}
    _searchString = searchString;
    // Cancel previous call to search listable rooms and messages
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchListableRoomsAndMessages) object:nil];
    
    // Filer rooms and search for listable rooms and messages
    if (searchString.length > 0) {
        // Set searchingMessages flag if we are going to search for messages
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityUnifiedSearch]) {
            [self setLoadMoreButtonHidden:YES];
            _resultTableViewController.searchingMessages = YES;
        }
        // Filter rooms
        [self filterRooms];
        // Throttle listable rooms and messages search
        [self performSelector:@selector(searchListableRoomsAndMessages) withObject:nil afterDelay:1];
    } else {
        // Clear search results
        [self setLoadMoreButtonHidden:YES];
        _resultTableViewController.searchingMessages = NO;
        [_resultTableViewController clearSearchedResults];
    }
}

- (void)filterRooms
{
    NSString *searchString = _searchController.searchBar.text;
    _resultTableViewController.rooms = [self filterRoomsWithString:searchString];
}

- (void)searchListableRoomsAndMessages
{
    NSString *searchString = _searchController.searchBar.text;
    TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
    // Search for listable rooms
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityListableRooms]) {
        _resultTableViewController.listableRooms = @[];
        [[NCAPIController sharedInstance] getListableRoomsForAccount:account withSearchTerm:searchString andCompletionBlock:^(NSArray *rooms, NSError *error, NSInteger statusCode) {
            if (!error) {
                self->_resultTableViewController.listableRooms = rooms;
            }
        }];
    }
    // Search for messages
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityUnifiedSearch]) {
        _unifiedSearchController = [[NCUnifiedSearchController alloc] initWithAccount:account searchTerm:searchString];
        _resultTableViewController.messages = @[];
        [self searchForMessagesWithCurrentSearchTerm];
    }
}

- (void)searchForMessagesWithCurrentSearchTerm
{
    [_unifiedSearchController searchMessagesWithCompletionHandler:^(NSArray<NCCSearchEntry *> *entries) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultTableViewController.searchingMessages = NO;
            self->_resultTableViewController.messages = entries;
            [self setLoadMoreButtonHidden:!self->_unifiedSearchController.showMore];
        });
    }];
}

- (NSArray *)filterRoomsWithString:(NSString *)searchString
{
    NSPredicate *sPredicate = [NSPredicate predicateWithFormat:@"displayName CONTAINS[c] %@", searchString];
    return [_rooms filteredArrayUsingPredicate:sPredicate];
}

- (void)setLoadMoreButtonHidden:(BOOL)hidden
{
    if (!hidden) {
        UIButton *loadMoreButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 44)];
        loadMoreButton.titleLabel.font = [UIFont systemFontOfSize:15];
        [loadMoreButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
        [loadMoreButton setTitle:NSLocalizedString(@"Load more results", @"") forState:UIControlStateNormal];
        [loadMoreButton addTarget:self action:@selector(loadMoreMessagesWithCurrentSearchTerm) forControlEvents:UIControlEventTouchUpInside];
        _resultTableViewController.tableView.tableFooterView = loadMoreButton;
    } else {
        _resultTableViewController.tableView.tableFooterView = nil;
    }
}

- (void)loadMoreMessagesWithCurrentSearchTerm
{
    if (_unifiedSearchController && [_unifiedSearchController.searchTerm isEqualToString:_searchController.searchBar.text]) {
        [_resultTableViewController showSearchingFooterView];
        [self searchForMessagesWithCurrentSearchTerm];
    }
}

#pragma mark - User Interface

- (void)refreshRoomList
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
    NSArray *accountRooms = [[NCRoomsManager sharedInstance] roomsForAccountId:account.accountId witRealm:nil];
    _rooms = [[NSMutableArray alloc] initWithArray:accountRooms];
    
    // Show/Hide placeholder view
    [_roomsBackgroundView.loadingView stopAnimating];
    [_roomsBackgroundView.loadingView setHidden:YES];
    [_roomsBackgroundView.placeholderView setHidden:(_rooms.count > 0)];
    
    // Calculate index of last room with a mention
    _lastRoomWithMentionIndexPath = nil;
    for (int i = 0; i < _rooms.count; i++) {
        NCRoom *room = [_rooms objectAtIndex:i];
        if (room.hasUnreadMention) {
            _lastRoomWithMentionIndexPath = [NSIndexPath indexPathForRow:i inSection:0];
        }
    }
    
    // Reload search controller if active
    NSString *searchString = _searchController.searchBar.text;
    if (_searchController.isActive && searchString.length > 0) {
        // Filter rooms to show updated rooms
        [self filterRooms];
    }
    
    // Reload room list
    [self.tableView reloadData];
    
    // Update unread mentions indicator
    [self updateMentionsIndicator];

    [self highlightSelectedRoom];
}

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case kAppStateNotServerProvided:
        case kAppStateMissingUserProfile:
        case kAppStateMissingServerCapabilities:
        case kAppStateMissingSignalingConfiguration:
        {
            [self setProfileButton];
        }
            break;
        case kAppStateReady:
        {
            [self setProfileButton];
            BOOL isAppActive = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:isAppActive];
            [self startRefreshRoomsTimer];
            [self setupNavigationBar];
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
    self.addButton.enabled = NO;
    if (!customNavigationLogo) {
        self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogoOffline"]];
    }
}

- (void)setOnlineAppearance
{
    self.addButton.enabled = YES;
    [self setNavigationLogoButton];
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if ([scrollView isEqual:self.tableView]) {
        [self updateMentionsIndicator];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if ([scrollView isEqual:self.tableView]) {
        [self updateMentionsIndicator];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if ([scrollView isEqual:self.tableView]) {
        [self updateMentionsIndicator];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    if ([scrollView isEqual:self.tableView]) {
        [self updateMentionsIndicator];
    }
}

#pragma mark - Mentions

- (void)updateMentionsIndicator
{
    NSArray *visibleRows = [self.tableView indexPathsForVisibleRows];
    NSIndexPath *lastVisibleRowIndexPath = visibleRows.lastObject;
    _unreadMentionsBottomButton.hidden = YES;
    
    // Calculate index of first room with a mention outside visible cells
    _nextRoomWithMentionIndexPath = nil;
    if (_lastRoomWithMentionIndexPath) {
        for (int i = (int)lastVisibleRowIndexPath.row; i <= (int)_lastRoomWithMentionIndexPath.row; i++) {
            NCRoom *room = [_rooms objectAtIndex:i];
            if (room.hasUnreadMention) {
                _nextRoomWithMentionIndexPath = [NSIndexPath indexPathForRow:i inSection:0];
                break;
            }
        }
    }
    
    // Update unread mentions indicator visibility
    if (_lastRoomWithMentionIndexPath) {
        _unreadMentionsBottomButton.hidden = [visibleRows containsObject:_lastRoomWithMentionIndexPath] || lastVisibleRowIndexPath.row > _lastRoomWithMentionIndexPath.row;

        // Make sure the style is adjusted to current accounts theme
        _unreadMentionsBottomButton.backgroundColor = [NCAppBranding themeColor];
        [_unreadMentionsBottomButton setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];
    }
}

- (void)unreadMentionsBottomButtonPressed:(id)sender
{
    if (_nextRoomWithMentionIndexPath) {
        [self.tableView scrollToRowAtIndexPath:_nextRoomWithMentionIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

#pragma mark - User profile

- (void)setProfileButton
{
    UIButton *profileButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [profileButton addTarget:self action:@selector(showUserProfile) forControlEvents:UIControlEventTouchUpInside];
    profileButton.frame = CGRectMake(0, 0, 30, 30);
    profileButton.accessibilityLabel = NSLocalizedString(@"User profile and settings", nil);
    profileButton.accessibilityHint = NSLocalizedString(@"Double tap to go to user profile and application settings", nil);
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    UIImage *profileImage = [[NCAPIController sharedInstance] userProfileImageForAccount:activeAccount withStyle:self.traitCollection.userInterfaceStyle andSize:CGSizeMake(90, 90)];
    if (profileImage) {
        UIGraphicsBeginImageContextWithOptions(profileButton.bounds.size, NO, 3.0);
        [[UIBezierPath bezierPathWithRoundedRect:profileButton.bounds cornerRadius:profileButton.bounds.size.height] addClip];
        [profileImage drawInRect:profileButton.bounds];
        profileImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [profileButton setImage:profileImage forState:UIControlStateNormal];
    } else {
        [profileButton setImage:[UIImage imageNamed:@"settings-white"] forState:UIControlStateNormal];
        profileButton.contentMode = UIViewContentModeCenter;
    }
    
    _settingsButton = [[UIBarButtonItem alloc] initWithCustomView:profileButton];
    [self setUnreadMessageForInactiveAccountsIndicator];

    NSLayoutConstraint *width = [_settingsButton.customView.widthAnchor constraintEqualToConstant:30];
    width.active = YES;
    NSLayoutConstraint *height = [_settingsButton.customView.heightAnchor constraintEqualToConstant:30];
    height.active = YES;
    
    [self.navigationItem setLeftBarButtonItem:_settingsButton];
}

- (void)setUnreadMessageForInactiveAccountsIndicator
{
    NSInteger numberOfInactiveAccountsWithUnreadNotifications = [[NCDatabaseManager sharedInstance] numberOfInactiveAccountsWithUnreadNotifications];
    if (numberOfInactiveAccountsWithUnreadNotifications > 0) {
        _settingsButton.badgeValue = [NSString stringWithFormat:@"%ld", numberOfInactiveAccountsWithUnreadNotifications];
    }
}

- (void)showUserProfile
{
    [[NCDatabaseManager sharedInstance] removeUnreadNotificationForInactiveAccounts];
    [self setUnreadMessageForInactiveAccountsIndicator];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    NCNavigationController *settingsNC = [storyboard instantiateViewControllerWithIdentifier:@"settingsNC"];
    [self presentViewController:settingsNC animated:YES completion:nil];
}

#pragma mark - CCCertificateDelegate

- (void)trustedCerticateAccepted
{
    [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:NO];
}

#pragma mark - Room actions

- (void)setNotificationLevelForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Notifications", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelAlways forRoom:room]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelMention forRoom:room]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelNever forRoom:room]];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (UIAlertAction *)actionForNotificationLevel:(NCRoomNotificationLevel)level forRoom:(NCRoom *)room
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:[room stringForNotificationLevel:level]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
                                                       if (level == room.notificationLevel) {
                                                           return;
                                                       }
                                                       [[NCAPIController sharedInstance] setNotificationLevel:level forRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
                                                           if (error) {
                                                               NSLog(@"Error renaming the room: %@", error.description);
                                                           }
                                                           [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
                                                       }];
                                                   }];
    if (room.notificationLevel == level) {
        [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    return action;
}

- (void)shareLinkFromRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *joinConversationString = NSLocalizedString(@"Join the conversation at", nil);
    
    if (room.displayName && ![room.displayName isEqualToString:@""]) {
        joinConversationString = [NSString stringWithFormat:NSLocalizedString(@"Join the conversation %@ at", nil), [NSString stringWithFormat:@"\"%@\"", room.name]];
    }
    NSString *shareMessage = [NSString stringWithFormat:@"%@ %@/index.php/call/%@", joinConversationString, activeAccount.server, room.token];
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:NSLocalizedString(@"%@ invitation", nil), appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];

    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:controller animated:YES completion:nil];
    
    controller.completionWithItemsHandler = ^(NSString *activityType,
                                              BOOL completed,
                                              NSArray *returnedItems,
                                              NSError *error) {
        if (error) {
            NSLog(@"An Error occured sharing room: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

- (void)markRoomAsReadAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    [[NCAPIController sharedInstance] setChatReadMarker:room.lastMessage.messageId inRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error marking room as read: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
    }];
}

- (void)markRoomAsUnreadAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    [[NCAPIController sharedInstance] markChatAsUnreadInRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error marking chat as unread: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
    }];
}

- (void)addRoomToFavoritesAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    [[NCAPIController sharedInstance] addRoomToFavorites:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error adding room to favorites: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
    }];
}

- (void)removeRoomFromFavoritesAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    [[NCAPIController sharedInstance] removeRoomFromFavorites:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error removing room from favorites: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
    }];
}

- (void)presentRoomInfoForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    RoomInfoTableViewController *roomInfoVC = [[RoomInfoTableViewController alloc] initForRoom:room];
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:roomInfoVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)leaveRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Leave conversation", nil)
                                        message:NSLocalizedString(@"Once a conversation is left, to rejoin a closed conversation, an invite is needed. An open conversation can be rejoined at any time.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Leave", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
        [self->_rooms removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [[NCAPIController sharedInstance] removeSelfFromRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSInteger errorCode, NSError *error) {
            if (errorCode == 400) {
                [self showLeaveRoomLastModeratorErrorForRoom:room];
            } else if (error) {
                NSLog(@"Error leaving room: %@", error.description);
            }
            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
        }];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)deleteRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete conversation", nil)
                                        message:room.deletionMessage
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
        [self->_rooms removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [[NCAPIController sharedInstance] deleteRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
            if (error) {
                NSLog(@"Error deleting room: %@", error.description);
            }
            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES];
        }];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)presentMoreActionsForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:room.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add/Remove room to/from favorites
    UIAlertAction *favoriteAction = [UIAlertAction actionWithTitle:(room.isFavorite) ? NSLocalizedString(@"Remove from favorites", nil) : NSLocalizedString(@"Add to favorites", nil)
                                                             style:UIAlertActionStyleDefault
                                                           handler:^void (UIAlertAction *action) {
                                                               if (room.isFavorite) {
                                                                   [self removeRoomFromFavoritesAtIndexPath:indexPath];
                                                               } else {
                                                                   [self addRoomToFavoritesAtIndexPath:indexPath];
                                                               }
                                                           }];
    NSString *favImageName = (room.isFavorite) ? @"favorite-action" : @"fav-setting";
    [favoriteAction setValue:[[UIImage imageNamed:favImageName] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:favoriteAction];
    // Mark room as read/unread
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker]) {
        if (room.unreadMessages > 0) {
            // Mark room as read
            UIAlertAction *markReadkAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Mark as read", nil)
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self markRoomAsReadAtIndexPath:indexPath];
                                                                    }];
            [markReadkAction setValue:[[UIImage imageNamed:@"visibility"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
            [optionsActionSheet addAction:markReadkAction];
        } else if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatUnread]) {
            // Mark room as unread
            UIAlertAction *markUnreadkAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Mark as unread", nil)
                                                                        style:UIAlertActionStyleDefault
                                                                      handler:^void (UIAlertAction *action) {
                                                                        [self markRoomAsUnreadAtIndexPath:indexPath];
                                                                    }];
            [markUnreadkAction setValue:[[UIImage imageNamed:@"visibility-off"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
            [optionsActionSheet addAction:markUnreadkAction];
        }
    }
    // Notification levels
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels]) {
        UIAlertAction *notificationsAction = [UIAlertAction actionWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Notifications: %@", nil), room.notificationLevelString]
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self setNotificationLevelForRoomAtIndexPath:indexPath];
                                                                    }];
        [notificationsAction setValue:[[UIImage imageNamed:@"notifications"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:notificationsAction];
    }

    // Share link
    if (room.type != kNCRoomTypeChangelog) {
        // Share Link
        UIAlertAction *shareLinkAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Share link", nil)
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^void (UIAlertAction *action) {
                                                                    [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                }];
        [shareLinkAction setValue:[[UIImage imageNamed:@"share"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:shareLinkAction];
    }

    // Room info
    UIAlertAction *roomInfoAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Conversation info", nil)
                                                             style:UIAlertActionStyleDefault
                                                           handler:^void (UIAlertAction *action) {
                                                               [self presentRoomInfoForRoomAtIndexPath:indexPath];
                                                           }];
    [roomInfoAction setValue:[[UIImage imageNamed:@"info"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    [optionsActionSheet addAction:roomInfoAction];
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)presentChatForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    [[NCRoomsManager sharedInstance] startChatInRoom:room];
}

#pragma mark - Utils

- (NCRoom *)roomForIndexPath:(NSIndexPath *)indexPath
{
    if (_searchController.active && !_resultTableViewController.view.isHidden) {
        return [_resultTableViewController roomForIndexPath:indexPath];
    } else if (indexPath.row < _rooms.count) {
        return [_rooms objectAtIndex:indexPath.row];
    }
    
    return nil;
}

- (void)showLeaveRoomLastModeratorErrorForRoom:(NCRoom *)room
{
    UIAlertController *leaveRoomFailedDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not leave conversation", nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"You need to promote a new moderator before you can leave %@.", nil), room.displayName]
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [leaveRoomFailedDialog addAction:okAction];
    
    [self presentViewController:leaveRoomFailedDialog animated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _rooms.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kRoomTableCellHeight;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIContextualAction *moreAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil
                                                                            handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                                [self presentMoreActionsForRoomAtIndexPath:indexPath];
                                                                                completionHandler(false);
                                                                            }];
    moreAction.image = [UIImage imageNamed:@"more-action"];
    
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                                            handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                                [self deleteRoomAtIndexPath:indexPath];
                                                                                completionHandler(false);
                                                                            }];
    deleteAction.image = [UIImage imageNamed:@"delete"];
    
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    // Do not show swipe actions for open conversations or messages
    if ((tableView == _resultTableViewController.tableView && room.listable) || !room) {return nil;}
    
    if (room.isLeavable) {
        deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                 [self leaveRoomAtIndexPath:indexPath];
                                                                 completionHandler(false);
                                                             }];
        deleteAction.image = [UIImage imageNamed:@"exit-white"];
    }
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, moreAction]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    // Do not show swipe actions for open conversations or messages
    if ((tableView == _resultTableViewController.tableView && room.listable) || !room) {return nil;}
    
    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil
                                                                               handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                                   if (room.isFavorite) {
                                                                                       [self removeRoomFromFavoritesAtIndexPath:indexPath];
                                                                                   } else {
                                                                                       [self addRoomToFavoritesAtIndexPath:indexPath];
                                                                                   }
                                                                                   completionHandler(true);
                                                                               }];
    favoriteAction.image = [UIImage imageNamed:@"fav-white"];
    favoriteAction.backgroundColor = [UIColor colorWithRed:0.97 green:0.80 blue:0.27 alpha:1.0]; // Favorite yellow
    
    return [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomCellIdentifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomCellIdentifier];
    }
    
    // Set room name
    cell.titleLabel.text = room.displayName;
    
    // Set last activity
    if (room.lastMessage) {
        cell.titleOnly = NO;
        cell.subtitleLabel.text = room.lastMessageString;
    } else {
        cell.titleOnly = YES;
    }
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastActivity];
    cell.dateLabel.text = [NCUtils readableTimeOrDateFromDate:date];
    
    // Set unread messages
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag]) {
        BOOL mentioned = room.unreadMentionDirect || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        BOOL groupMentioned = room.unreadMention && !room.unreadMentionDirect;
        [cell setUnreadMessages:room.unreadMessages mentioned:mentioned groupMentioned:groupMentioned];
    } else {
        BOOL mentioned = room.unreadMention || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        [cell setUnreadMessages:room.unreadMessages mentioned:mentioned groupMentioned:NO];
    }
    
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOne:
            [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                  placeholderImage:nil success:nil failure:nil];
            [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
            break;
            
        case kNCRoomTypeGroup:
            [cell.roomImage setImage:[UIImage imageNamed:@"group"]];
            break;
            
        case kNCRoomTypePublic:
            [cell.roomImage setImage:[UIImage imageNamed:@"public"]];
            break;
            
        case kNCRoomTypeChangelog:
            [cell.roomImage setImage:[UIImage imageNamed:@"changelog"]];
            [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
            break;

        case kNCRoomTypeFormerOneToOne:
            [cell.roomImage setImage:[UIImage imageNamed:@"user"]];
            break;

        default:
            break;
    }

    //Show User Status
    if (room.type == kNCRoomTypeOneToOne && [room.status length] != 0) {
        if (![room.status isEqualToString:@"dnd"] && [room.statusIcon length] != 0) {
            [cell setUserStatusIcon:room.statusIcon];
        } else {
            [cell setUserStatus:room.status];
        }
    }
    
    // Set objectType image
    if ([room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [cell.roomImage setImage:[UIImage imageNamed:@"file-conv"]];
    } else if ([room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [cell.roomImage setImage:[UIImage imageNamed:@"pass-conv"]];
    }
    
    // Set favorite image
    if (room.isFavorite) {
        [cell.favoriteImage setImage:[UIImage imageNamed:@"favorite-room"]];
    }

    cell.roomToken = room.token;
        
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self setSelectedRoomToken:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // Present searched messages
    if (tableView == _resultTableViewController.tableView) {
        NKSearchEntry *searchMessage = [_resultTableViewController messageForIndexPath:indexPath];
        NSString *roomToken = [searchMessage.attributes objectForKey:@"conversation"];
        NSString *messageId = [searchMessage.attributes objectForKey:@"messageId"];
        if (roomToken && messageId) {
            // Present message in chat view
            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
            [userInfo setObject:roomToken forKey:@"token"];
            [userInfo setObject:messageId forKey:@"messageId"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCPresentChatHighlightingMessageNotification
                                                                object:self
                                                              userInfo:userInfo];
            return;
        }
    }
    
    // Present room chat
    [self presentChatForRoomAtIndexPath:indexPath];
}

- (void)setSelectedRoomToken:(NSString *)selectedRoomToken
{
    _selectedRoomToken = selectedRoomToken;
    [self highlightSelectedRoom];
}

- (void)removeRoomSelection {
    [self setSelectedRoomToken:nil];
}

- (void)highlightSelectedRoom
{
    if(_selectedRoomToken != nil) {
        NSUInteger idx = [_rooms indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){
            NCRoom* room = (NCRoom*)obj;
            return [room.token isEqualToString:_selectedRoomToken];
        }];
        
        if (idx != NSNotFound) {
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    } else {
        NSIndexPath *selectedRow = [self.tableView indexPathForSelectedRow];
        if (selectedRow != nil) {
            [self.tableView deselectRowAtIndexPath:selectedRow animated:YES];

            // Needed to make sure the highlight is really removed
            [self.tableView reloadRowsAtIndexPaths:@[selectedRow] withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
