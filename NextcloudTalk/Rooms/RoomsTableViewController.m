/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "RoomsTableViewController.h"

@import NextcloudKit;
#import <Realm/Realm.h>

#import "NextcloudTalk-Swift.h"

#import "JDStatusBarNotification.h"

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCNavigationController.h"
#import "NCNotificationController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NotificationCenterNotifications.h"
#import "PlaceholderView.h"
#import "RoomSearchTableViewController.h"
#import "UIBarButtonItem+LegacyBadge.h"

typedef void (^FetchRoomsCompletionBlock)(BOOL success);

typedef enum RoomsFilter {
    kRoomsFilterAll = 0,
    kRoomsFilterUnread,
    kRoomsFilterMentioned,
    kRoomsFilterEvent
} RoomsFilter;

typedef enum RoomsSections {
    kRoomsSectionPendingFederationInvitation = 0,
    kRoomsSectionThreads,
    kRoomsSectionArchivedConversations,
    kRoomsSectionRoomList,
    kRoomsSectionsCount
} RoomsSections;

@interface RoomsTableViewController () <CCCertificateDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating, UserStatusViewDelegate>
{
    RLMNotificationToken *_rlmNotificationToken;
    NSMutableArray *_rooms;
    NSMutableArray *_allRooms;
    NSArray *_threads;
    BOOL _showingArchivedRooms;
    UIRefreshControl *_refreshControl;
    BOOL _allowEmptyGroupRooms;
    UISearchController *_searchController;
    NSString *_searchString;
    RoomSearchTableViewController *_resultTableViewController;
    NCUnifiedSearchController *_unifiedSearchController;
    PlaceholderView *_roomsBackgroundView;
    UIBarButtonItem *_newConversationButton;
    UIBarButtonItem *_settingsButton;
    UIButton *_profileButton;
    NCUserStatus *_activeUserStatus;
    NSTimer *_refreshRoomsTimer;
    NSIndexPath *_nextRoomWithMentionIndexPath;
    NSIndexPath *_lastRoomWithMentionIndexPath;
    UIButton *_unreadMentionsBottomButton;
    NCNavigationController *_contextChatNavigationController;
}

@property (nonatomic, copy, nullable) void (^contextMenuActionBlock)(void);

@end

@implementation RoomsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    __weak typeof(self) weakSelf = self;
    _rlmNotificationToken = [[NCRoom allObjects] addNotificationBlock:^(RLMResults * _Nullable results, RLMCollectionChange * _Nullable change, NSError * _Nullable error) {
       [weakSelf refreshRoomList];
    }];
    
    [self.tableView registerNib:[UINib nibWithNibName:RoomTableViewCell.nibName bundle:nil] forCellReuseIdentifier:RoomTableViewCell.identifier];
    [self.tableView registerClass:InfoLabelTableViewCell.class forCellReuseIdentifier:InfoLabelTableViewCell.identifier];

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = UITableViewAutomaticDimension;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    _resultTableViewController = [[RoomSearchTableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.searchResultsUpdater = self;
    [_searchController.searchBar sizeToFit];

    [self setupSearchBar];
    [self setupNavigationBar];
    
    // We want ourselves to be the delegate for the result table so didSelectRowAtIndexPath is called for both tables.
    _resultTableViewController.tableView.delegate = self;
    _searchController.delegate = self;
    _searchController.searchBar.delegate = self;
    
    self.definesPresentationContext = YES;
    
    // Rooms placeholder view
    _roomsBackgroundView = [[PlaceholderView alloc] init];
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
    [self.tableView setTintColor:[UIColor clearColor]];

    // Remove the backButtonTitle, otherwise when we transition to a conversation, "Back" is briefly visible
    self.navigationItem.backButtonTitle = @"";

    NSDictionary *views = @{@"unreadMentionsButton": _unreadMentionsBottomButton};
    NSDictionary *metrics = @{@"buttonWidth": @(buttonWidth)};
    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=0)-[unreadMentionsButton(28)]-30-|" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[unreadMentionsButton(buttonWidth)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:@[[_unreadMentionsBottomButton.centerXAnchor constraintEqualToAnchor:margins.centerXAnchor]]];
    [self.view addConstraint:[_unreadMentionsBottomButton.bottomAnchor constraintEqualToAnchor:self.tableView.safeAreaLayoutGuide.bottomAnchor constant:-20]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NSNotification.NCAppStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NSNotification.NCConnectionStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomsDidUpdate:) name:NCRoomsManagerDidUpdateRoomsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationWillBePresented:) name:NCNotificationControllerWillPresentNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCapabilitiesUpdated:) name:NCServerCapabilitiesUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userProfileImageUpdated:) name:NCUserProfileImageUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activeAccountDidChange:) name:NCSettingsControllerDidChangeActiveAccountNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pendingInvitationsDidUpdate:) name:NCDatabaseManagerPendingFederationInvitationsDidChange object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inviationDidAccept:) name:NSNotification.FederationInvitationDidAcceptNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userThreadsUpdated:) name:NCUserThreadsUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userHasThreadsUpdated:) name:NCUserHasThreadsFlagUpdatedNotification object:nil];
}

- (void)setupSearchBar
{
    _searchController.searchBar.scopeButtonTitles = [self getFilters];
    _searchController.scopeBarActivation = UISearchControllerScopeBarActivationOnSearchActivation;

#if defined(__IPHONE_26_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_26_0
    if (@available(iOS 26, *)) {
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
            __weak typeof(self) weakSelf = self;
            NSMutableArray *menuItems = [[NSMutableArray alloc] init];

            for (NSNumber *filterId in [self availableFilters]) {
                UIAction *action = [UIAction actionWithTitle:[self filterName:filterId.intValue]
                                                       image:[self filterImage:filterId.intValue]
                                                  identifier:nil
                                                     handler:^(UIAction *action) {
                    weakSelf.navigationItem.searchController.searchBar.selectedScopeButtonIndex = filterId.intValue;
                    [self filterRooms];
                    [self setupSearchBar];
                    [self updateMentionsIndicator];
                }];

                if (filterId == [NSNumber numberWithInt:kRoomsFilterAll]) {
                    UIMenu *noFilterMenu = [UIMenu menuWithTitle:@""
                                                           image:nil
                                                      identifier:nil
                                                         options:UIMenuOptionsDisplayInline
                                                        children:@[action]];
                    [menuItems addObject:noFilterMenu];
                } else {
                    [menuItems addObject:action];
                }
            }

            UIMenu *menu = [UIMenu menuWithTitle:NSLocalizedString(@"Filters", @"Title for available conversations filters")
                                           image:nil
                                      identifier:nil
                                         options:UIMenuOptionsDisplayInline
                                        children:menuItems];

            UIBarButtonItem *filterBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease"] menu:menu];

            RoomsFilter filter = (RoomsFilter) _searchController.searchBar.selectedScopeButtonIndex;

            if (filter != kRoomsFilterAll) {
                filterBarButton.style = UIBarButtonItemStyleProminent;
                filterBarButton.tintColor = [NCAppBranding elementColor];
            }

            [self setToolbarItems:@[
                self.navigationItem.searchBarPlacementBarButtonItem,
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                filterBarButton
            ] animated:YES];

            [self.navigationController setToolbarHidden:NO];

            _searchController.scopeBarActivation = UISearchControllerScopeBarActivationManual;
        }
    }
#endif
}

- (void)setupNavigationBar
{
    [self setNavigationLogoButton];
    [self createNewConversationButton];
    [self createRefreshControl];

    self.navigationItem.searchController = _searchController;

    if (@available(iOS 26.0, *)) {
        self.tableView.backgroundColor = [UIColor clearColor];

        // Set a solid background in collapsed mode, as otherwise we have a weird color transition
        // when navigating back in light mode
        if (self.splitViewController.isCollapsed) {
            self.view.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            self.view.backgroundColor = [UIColor clearColor];
        }
    } else {
        [NCAppBranding styleViewController:self];
    }
}

- (void)setNavigationLogoButton
{
    UIImageView *logoImageView = [[UIImageView alloc] initWithImage:[NCAppBranding navigationLogoImage]];
    if (!customNavigationLogo) {
        logoImageView.tintColor = [UIColor labelColor];
    }
    self.navigationItem.titleView = logoImageView;
    self.navigationItem.titleView.accessibilityLabel = talkAppName;
}

- (void)createNewConversationButton
{
    if ([[NCSettingsController sharedInstance] canCreateGroupAndPublicRooms] ||
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityListableRooms]) {

        _newConversationButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(presentNewRoomViewController)];
        _newConversationButton.accessibilityLabel = NSLocalizedString(@"Create or join a conversation", nil);

#if defined(__IPHONE_26_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_26_0
        if (@available(iOS 26.0, *)) {
            _newConversationButton.tintColor = [NCAppBranding elementColor];

            if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPhone) {
                // On non-iPhones we want to hide the shared background (glass effect)
                _newConversationButton.hidesSharedBackground = YES;
            } else {
                // On iPhones we want to have a prominent glass button with non-filled icon
                _newConversationButton.image = [UIImage systemImageNamed:@"plus"];
                _newConversationButton.style = UIBarButtonItemStyleProminent;
            }
        }
#endif

        [self.navigationItem setRightBarButtonItem:_newConversationButton];
    }
}

- (void)presentNewRoomViewController
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NewRoomTableViewController *newRoowVC = [[NewRoomTableViewController alloc] initWithAccount:activeAccount];
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:newRoowVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)dealloc
{
    [_rlmNotificationToken invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self adaptInterfaceForAppState:[NCConnectionController shared].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController shared].connectionState];

    if ([[NCSettingsController sharedInstance] isContactSyncEnabled] && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityPhonebookSearch]) {
        [[NCContactsManager sharedInstance] searchInServerForAddressBookContacts:NO];
    }
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

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self setProfileButton];
        [self setupNavigationBar];
    }
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

- (void)pendingInvitationsDidUpdate:(NSNotification *)notification
{
    [self refreshRoomList];
}

- (void)inviationDidAccept:(NSNotification *)notification
{
    // We accepted an invitation, so we refresh the rooms from the API to show it directly
    [self refreshRooms];
}

- (void)userThreadsUpdated:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSArray *threads = [notification.userInfo objectForKey:@"threads"];

    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([activeAccount.accountId isEqualToString:accountId]) {
        _threads = threads;
        [self refreshRoomList];
    }
}

- (void)userHasThreadsUpdated:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([activeAccount.accountId isEqualToString:accountId]) {
        [self refreshRoomList];
    }
}

- (void)notificationWillBePresented:(NSNotification *)notification
{
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO onlyLastModified:NO withCompletionBlock:nil];
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
    if ([NCConnectionController shared].appState == AppStateReady) {
        [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES onlyLastModified:NO withCompletionBlock:nil];
        [self startRefreshRoomsTimer];

        dispatch_async(dispatch_get_main_queue(), ^{
            // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
            [self setProfileButton];
            [self setUnreadMessageForInactiveAccountsIndicator];
        });
    }
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

- (void)activeAccountDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshRoomList];

        // Setup the navigation bar here, otherwise it would only be updated
        // when the capabilities were updated, which fails when the server is not reachable.
        [self setupNavigationBar];
    });
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
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES onlyLastModified:NO withCompletionBlock:nil];

    if ([NCConnectionController shared].connectionState == ConnectionStateConnected) {
        [[NCRoomsManager sharedInstance] resendOfflineMessagesWithCompletionBlock:nil];
    }

    [self getUserStatusWithCompletionBlock:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        // Dispatch to main, otherwise the traitCollection is not updated yet and profile buttons shows wrong style
        [self setUnreadMessageForInactiveAccountsIndicator];
    });
}

#pragma mark - Refresh Control

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];

    if (@available(iOS 26.0, *)) {
        _refreshControl.tintColor = [UIColor labelColor];
    } else {
        _refreshControl.tintColor = [NCAppBranding themeTextColor];
    }

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
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:YES onlyLastModified:NO withCompletionBlock:nil];

    [self getUserStatusWithCompletionBlock:nil];

    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

#pragma mark - User Status SwiftUI View Delegate

- (void)userStatusViewDidDisappear
{
    [self getUserStatusWithCompletionBlock:nil];
}

#pragma mark - Title menu

- (UIMenu *)getActiveAccountMenuOptions
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];

    UIDeferredMenuElement *userStatusDeferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        if (!activeAccount || !serverCapabilities.userStatus) {
            completion(@[]);
            return;
        }

        [self getUserStatusWithCompletionBlock:^(NSDictionary *userStatusDict, NSError *error) {
            if (error) {
                completion(@[]);
                return;
            }

            NCUserStatus *userStatus = [NCUserStatus userStatusWithDictionary:userStatusDict];
            UIImage *userStatusImage = [userStatus getSFUserStatusIcon];
            UIViewController *vc = [UserStatusSwiftUIViewFactory createWithUserStatus:userStatus delegate:self];

            UIAction *onlineOption = [UIAction actionWithTitle:[userStatus readableUserStatusOrMessage] image:userStatusImage identifier:nil handler:^(UIAction *action) {
                [self presentViewController:vc animated:YES completion:nil];
            }];

            completion(@[onlineOption]);
        }];
    }];

    return [UIMenu menuWithTitle:@""
                           image:nil
                      identifier:nil
                         options:UIMenuOptionsDisplayInline
                        children:@[userStatusDeferred]];
}

- (UIDeferredMenuElement *)getInactiveAccountMenuOptions
{
    // We use a deferred action here to always have an up-to-date list of inactive accounts and their notifications
    UIDeferredMenuElement *inactiveAccountMenuDeferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        NSMutableArray *inactiveAccounts = [[NSMutableArray alloc] init];

        for (TalkAccount *account in [[NCDatabaseManager sharedInstance] inactiveAccounts]) {
            NSString *accountName = account.userDisplayName;
            UIImage *accountImage = [[NCAPIController sharedInstance] userProfileImageForAccount:account withStyle:self.traitCollection.userInterfaceStyle];

            if (accountImage) {
                accountImage = [NCUtils roundedImageFromImage:accountImage];

                // Draw a red circle to the image in case we have unread notifications for that account
                if (account.unreadNotification) {
                    UIGraphicsBeginImageContextWithOptions(CGSizeMake(82, 82), NO, 3);
                    CGContextRef context = UIGraphicsGetCurrentContext();
                    [accountImage drawInRect:CGRectMake(0, 4, 78, 78)];
                    CGContextSaveGState(context);

                    CGContextSetFillColorWithColor(context, [UIColor systemRedColor].CGColor);
                    CGContextFillEllipseInRect(context, CGRectMake(52, 0, 30, 30));

                    accountImage = UIGraphicsGetImageFromCurrentImageContext();

                    UIGraphicsEndImageContext();
                }
            }

            UIAction *switchAccountAction = [UIAction actionWithTitle:accountName image:accountImage identifier:nil handler:^(UIAction *action) {
                [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:account.accountId];
            }];

            if (account.unreadBadgeNumber > 0) {
                switchAccountAction.subtitle = [NSString localizedStringWithFormat:NSLocalizedString(@"%ld notifications", nil), (long)account.unreadBadgeNumber];
            } else {
                switchAccountAction.subtitle = [account.server stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            }

            [inactiveAccounts addObject:switchAccountAction];
        }

        if (inactiveAccounts.count > 0) {
            TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
            UIImage *accountImage = [[NCAPIController sharedInstance] userProfileImageForAccount:activeAccount withStyle:self.traitCollection.userInterfaceStyle];
            if (accountImage) {
                accountImage = [NCUtils roundedImageFromImage:accountImage];
            }
            UIAction *activeAccountAction = [UIAction actionWithTitle:activeAccount.userDisplayName image:accountImage identifier:nil handler:^(UIAction *action) {}];
            activeAccountAction.subtitle = [activeAccount.server stringByReplacingOccurrencesOfString:@"https://" withString:@""];
            activeAccountAction.state = UIMenuElementStateOn;
            [inactiveAccounts insertObject:activeAccountAction atIndex:0];
        }

        UIMenu *inactiveAccountsMenu = [UIMenu menuWithTitle:@""
                                                       image:nil
                                                  identifier:nil
                                                     options:UIMenuOptionsDisplayInline
                                                    children:inactiveAccounts];
        if (@available(iOS 17.4, *)) {
            UIMenuDisplayPreferences *displayPreferences = [[UIMenuDisplayPreferences alloc] init];
            displayPreferences.maximumNumberOfTitleLines = 1;

            inactiveAccountsMenu.displayPreferences = displayPreferences;
        }

        completion(@[inactiveAccountsMenu]);
    }];

    return inactiveAccountMenuDeferred;
}

- (void)updateAccountPickerMenu
{
    NSMutableArray *accountPickerMenu = [[NSMutableArray alloc] init];

    // When no elements are returned by the deferred menu, the entries / inline-menu will be hidden
    [accountPickerMenu addObject:[self getActiveAccountMenuOptions]];
    [accountPickerMenu addObject:[self getInactiveAccountMenuOptions]];

    NSMutableArray *optionItems = [[NSMutableArray alloc] init];

    if (multiAccountEnabled) {
        UIAction *addAccountOption = [UIAction actionWithTitle:NSLocalizedString(@"Add account", nil) image:[[UIImage systemImageNamed:@"person.crop.circle.badge.plus"] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal] identifier:nil handler:^(UIAction *action) {
            [[NCUserInterfaceController sharedInstance] presentLoginViewController];
        }];

        [optionItems addObject:addAccountOption];
    }

    UIAction *openSettingsOption = [UIAction actionWithTitle:NSLocalizedString(@"Settings", nil) image:[[UIImage systemImageNamed:@"gear"] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal] identifier:nil handler:^(UIAction *action) {
        [[NCDatabaseManager sharedInstance] removeUnreadNotificationForInactiveAccounts];
        [self setUnreadMessageForInactiveAccountsIndicator];
        [AppStoreReviewController recordAction:AppStoreReviewController.visitAppSettings];
        [[NCUserInterfaceController sharedInstance] presentSettingsViewController];
    }];

    [optionItems addObject:openSettingsOption];

    UIMenu *optionMenu = [UIMenu menuWithTitle:@""
                                          image:nil
                                     identifier:nil
                                        options:UIMenuOptionsDisplayInline
                                       children:optionItems];

    [accountPickerMenu addObject:optionMenu];

    _profileButton.menu = [UIMenu menuWithTitle:@"" children:accountPickerMenu];
    _profileButton.showsMenuAsPrimaryAction = YES;
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
    
    // Search for listable rooms and messages
    if (searchString.length > 0) {
        // Set searchingMessages flag if we are going to search for messages
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityUnifiedSearch]) {
            [self setLoadMoreButtonHidden:YES];
            _resultTableViewController.searchingMessages = YES;
        }
        // Throttle listable rooms and messages search
        [self performSelector:@selector(searchListableRoomsAndMessages) withObject:nil afterDelay:1];
    } else {
        // Clear search results
        [self setLoadMoreButtonHidden:YES];
        _resultTableViewController.searchingMessages = NO;
        [_resultTableViewController clearSearchedResults];
    }

    // Filter rooms
    [self filterRooms];
}

- (void)willDismissSearchController:(UISearchController *)searchController
{
    _searchController.searchBar.text = @"";
    _searchController.searchBar.selectedScopeButtonIndex = kRoomsFilterAll;

    [self filterRooms];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    [self filterRooms];
}

- (void)filterRooms
{
    RoomsFilter filter = (RoomsFilter) _searchController.searchBar.selectedScopeButtonIndex;
    NSArray *filteredRooms = [self filterRoomsWithFilter:filter];

    NSString *searchString = _searchController.searchBar.text;
    if (searchString.length == 0) {
        _rooms = [[NSMutableArray alloc] initWithArray:filteredRooms];
        [self calculateLastRoomWithMention];
        [self.tableView reloadData];
        [self highlightSelectedRoom];
    } else {
        _resultTableViewController.rooms = [self filterRooms:filteredRooms withString:searchString];
        [self calculateLastRoomWithMention];
    }

    [self updatePlaceholderView];
}

- (void)searchListableRoomsAndMessages
{
    NSString *searchString = _searchController.searchBar.text;
    TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
    // Search for contacts
    _resultTableViewController.users = @[];
    [[NCAPIController sharedInstance] getContactsForAccount:account forRoom:nil groupRoom:NO withSearchParam:searchString andCompletionBlock:^(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error) {
        if (!error) {
            NSArray *users = [self usersWithoutOneToOneConversations:contactList];
            if ([[NCSettingsController sharedInstance] isContactSyncEnabled] && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityPhonebookSearch]) {
                TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
                NSArray *addressBookContacts = [NCContact contactsForAccountId:activeAccount.accountId contains:nil];
                users = [NCUser combineUsersArray:addressBookContacts withUsersArray:users];
            }
            self->_resultTableViewController.users = users;
        }
    }];
    // Search for listable rooms
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityListableRooms]) {
        _resultTableViewController.listableRooms = @[];
        [[NCAPIController sharedInstance] getListableRoomsForAccount:account withSerachTerm:searchString completionBlock:^(NSArray<NCRoom *> * _Nullable rooms, NSError * _Nullable error) {
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

- (NSArray *)usersWithoutOneToOneConversations:(NSArray *)users
{
    NSPredicate *oneToOnePredicate = [NSPredicate predicateWithFormat:@"type == %ld", kNCRoomTypeOneToOne];
    NSArray *oneToOneRooms = [_rooms filteredArrayUsingPredicate:oneToOnePredicate];
    NSPredicate *namePredicate = [NSPredicate predicateWithFormat:@"NOT (userId  IN %@)", [oneToOneRooms valueForKey:@"name"]];

    return [users filteredArrayUsingPredicate:namePredicate];
}

- (void)searchForMessagesWithCurrentSearchTerm
{
    [_unifiedSearchController searchMessagesWithCompletionHandler:^(NSArray<NKSearchEntry *> *entries) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultTableViewController.searchingMessages = NO;
            self->_resultTableViewController.messages = entries;
            [self setLoadMoreButtonHidden:!self->_unifiedSearchController.showMore];
        });
    }];
}

- (NSArray *)filterRoomsWithFilter:(RoomsFilter)filter
{
    switch (filter) {
        case kRoomsFilterUnread:
            return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isVisible == YES AND unreadMessages > 0 AND isArchived == %@", @(_showingArchivedRooms)]];
        case kRoomsFilterMentioned:
            return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isVisible == YES AND hasUnreadMention == YES AND isArchived == %@", @(_showingArchivedRooms)]];
        case kRoomsFilterEvent:
            return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"objectType == 'event' AND isArchived == %@", @(_showingArchivedRooms)]];
        default:
            return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isVisible == YES AND isArchived == %@", @(_showingArchivedRooms)]];
    }
}

- (NSArray *)filterRooms:(NSArray *)rooms withString:(NSString *)searchString
{
    return [rooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"displayName CONTAINS[c] %@", searchString]];
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

#pragma mark - Rooms filter

- (NSArray *)availableFilters
{
    NSMutableArray *filters = [[NSMutableArray alloc] init];
    [filters addObject:[NSNumber numberWithInt:kRoomsFilterAll]];
    [filters addObject:[NSNumber numberWithInt:kRoomsFilterUnread]];
    [filters addObject:[NSNumber numberWithInt:kRoomsFilterMentioned]];
    [filters addObject:[NSNumber numberWithInt:kRoomsFilterEvent]];

    return [NSArray arrayWithArray:filters];
}

- (NSString *)filterName:(RoomsFilter)filter
{
    switch (filter) {
        case kRoomsFilterAll:
            return NSLocalizedString(@"No filter", @"'No filter' meaning 'No filter will be applied in conversations list'");
        case kRoomsFilterUnread:
            return NSLocalizedString(@"Unread", @"'Unread' meaning 'Unread conversations'");
        case kRoomsFilterMentioned:
            return NSLocalizedString(@"Mentioned", @"'Mentioned' meaning 'Mentioned conversations'");
        case kRoomsFilterEvent:
            return NSLocalizedString(@"Meetings", @"'Meetings' meaning 'Conversations that were created from a calendar event'");
        default:
            return @"";
    }
}

- (UIImage *)filterImage:(RoomsFilter)filter
{
    switch (filter) {
        case kRoomsFilterAll:
            return [UIImage imageNamed:@"custom.line.3.horizontal.decrease.slash"];
        case kRoomsFilterUnread:
            return [UIImage imageNamed:@"custom.bubble.badge"];
        case kRoomsFilterMentioned:
            return [UIImage systemImageNamed:@"at"];
        case kRoomsFilterEvent:
            return [UIImage systemImageNamed:@"calendar"];
        default:
            return nil;
    }
}

- (UIImage *)filterPlaceholderImage:(RoomsFilter)filter
{
    if (filter == kRoomsFilterAll) {
        return [UIImage imageNamed:@"conversations-placeholder"];
    }

    return [self filterImage:filter];
}

- (NSString *)filterPlaceholderText:(RoomsFilter)filter
{
    switch (filter) {
        case kRoomsFilterAll:
            return NSLocalizedString(@"You are not part of any conversation. Press + to start a new one.", nil);
        case kRoomsFilterUnread:
            return NSLocalizedString(@"You have no unread messages.", nil);
        case kRoomsFilterMentioned:
            return NSLocalizedString(@"You have no unread mentions.", nil);
        case kRoomsFilterEvent:
            return NSLocalizedString(@"You have no meetings scheduled.", nil);
        default:
            return nil;
    }
}

- (NSArray *)getFilters
{
    NSMutableArray *filters = [[NSMutableArray alloc] init];
    for (NSNumber *filter in [self availableFilters]) {
        [filters addObject:[self filterName:filter.intValue]];
    }

    return [NSArray arrayWithArray:filters];
}

#pragma mark - User Interface

- (void)refreshRoomList
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
    NSArray *accountRooms = [[NCDatabaseManager sharedInstance] roomsForAccountId:account.accountId withRealm:nil];
    _allRooms = [[NSMutableArray alloc] initWithArray:accountRooms];
    _rooms = [[NSMutableArray alloc] initWithArray:accountRooms];

    // Filter rooms
    [self filterRooms];

    // Update placeholder view
    [self updatePlaceholderView];

    // Reload room list
    [self.tableView reloadData];
    
    // Update unread mentions indicator
    [self updateMentionsIndicator];

    [self highlightSelectedRoom];
}

- (void)updatePlaceholderView
{
    [_roomsBackgroundView.loadingView stopAnimating];
    [_roomsBackgroundView.loadingView setHidden:YES];

    RoomsFilter filter = (RoomsFilter) _searchController.searchBar.selectedScopeButtonIndex;
    [_roomsBackgroundView setImage:[self filterPlaceholderImage:filter]];
    [_roomsBackgroundView.placeholderTextView setText:[self filterPlaceholderText:filter]];
    [_roomsBackgroundView.placeholderView setHidden:(_rooms.count > 0)];
}

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case AppStateNoServerProvided:
        case AppStateMissingUserProfile:
        case AppStateMissingServerCapabilities:
        case AppStateMissingSignalingConfiguration:
        {
            // Clear active user status and threads when changing users
            _activeUserStatus = nil;
            _threads = nil;
            [self setProfileButton];
        }
            break;
        case AppStateReady:
        {
            [self setProfileButton];
            BOOL isAppActive = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:isAppActive onlyLastModified:NO];
            [self getUserStatusWithCompletionBlock:nil];
            [self getUserThreads];
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
        case ConnectionStateConnected:
        {
            [self setOnlineAppearance];
        }
            break;
            
        case ConnectionStateDisconnected:
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
    _newConversationButton.enabled = NO;
}

- (void)setOnlineAppearance
{
    _newConversationButton.enabled = YES;
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

    if (!_lastRoomWithMentionIndexPath) {
        return;
    }

    for (int i = (int)lastVisibleRowIndexPath.row; i <= (int)_lastRoomWithMentionIndexPath.row && i < [_rooms count]; i++) {
        NCRoom *room = [_rooms objectAtIndex:i];
        if (room.hasUnreadMention) {
            _nextRoomWithMentionIndexPath = [NSIndexPath indexPathForRow:i inSection:kRoomsSectionRoomList];
            break;
        }
    }

    // Update unread mentions indicator visibility
    _unreadMentionsBottomButton.hidden = [visibleRows containsObject:_lastRoomWithMentionIndexPath] || lastVisibleRowIndexPath.row > _lastRoomWithMentionIndexPath.row;

    // Make sure the style is adjusted to current accounts theme
    _unreadMentionsBottomButton.backgroundColor = [NCAppBranding themeColor];
    [_unreadMentionsBottomButton setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];
}

- (void)unreadMentionsBottomButtonPressed:(id)sender
{
    if (_nextRoomWithMentionIndexPath) {
        [self.tableView scrollToRowAtIndexPath:_nextRoomWithMentionIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (void)calculateLastRoomWithMention
{
    _lastRoomWithMentionIndexPath = nil;
    for (int i = 0; i < _rooms.count; i++) {
        NCRoom *room = [_rooms objectAtIndex:i];
        if (room.hasUnreadMention) {
            _lastRoomWithMentionIndexPath = [NSIndexPath indexPathForRow:i inSection:kRoomsSectionRoomList];
        }
    }
}

#pragma mark - User profile

- (void)setProfileButton
{
    _profileButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _profileButton.frame = CGRectMake(0, 0, 38, 38);
    _profileButton.accessibilityLabel = NSLocalizedString(@"User profile and settings", nil);

    _settingsButton = [[UIBarButtonItem alloc] initWithCustomView:_profileButton];

#if defined(__IPHONE_26_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPhone) {
            // On non-iPhones we want to hide the shared background (glass effect)
            _settingsButton.hidesSharedBackground = YES;
        }
    }
#endif

    [self.navigationItem setLeftBarButtonItem:_settingsButton];

    [self updateProfileButtonImage];
    [self updateAccountPickerMenu];
    [self setUnreadMessageForInactiveAccountsIndicator];
}

- (void)updateProfileButtonImage
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    UIImage *profileImage = [[NCAPIController sharedInstance] userProfileImageForAccount:activeAccount withStyle:self.traitCollection.userInterfaceStyle];
    if (profileImage) {
        // Crop the profile image into a circle
        profileImage = [profileImage cropToCircleWithSize:CGSizeMake(30, 30)];
        // Increase the profile image size to leave space for the status
        profileImage = [profileImage withCircularBackgroundWithBackgroundColor:[UIColor separatorColor] diameter:32.0 padding:1.0];
        profileImage = [profileImage withCircularBackgroundWithBackgroundColor:[UIColor clearColor] diameter:38.0 padding:3.0];

        // Online status icon
        UIImage *statusImage = nil;
        if ([_activeUserStatus hasVisibleStatusIcon]) {
            if (@available(iOS 26.0, *)) {
                // TODO: Also cut out the avatar as we do in AvatarView?
                statusImage = [[_activeUserStatus getSFUserStatusIcon] withCircularBackgroundWithBackgroundColor:[UIColor clearColor]
                                                                                                        diameter:14.0 padding:1.0];
            } else {
                statusImage = [[_activeUserStatus getSFUserStatusIcon] withCircularBackgroundWithBackgroundColor:self.navigationController.navigationBar.barTintColor
                                                                                                        diameter:14.0 padding:1.0];
            }
        }

        // Status message icon
        if (_activeUserStatus.icon.length > 0) {
            UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 14, 14)];
            iconLabel.text = _activeUserStatus.icon;
            iconLabel.adjustsFontSizeToFitWidth = YES;
            statusImage = [UIImage imageFrom:iconLabel];
        }

        // Set status image
        if (statusImage) {
            profileImage = [profileImage overlayWith:statusImage at:CGRectMake(24, 24, 14, 14)];
        }

        [_profileButton setImage:profileImage forState:UIControlStateNormal];
        // Used to distinguish between a "completely loaded" button (with a profile image) and the default gear one
        _profileButton.accessibilityIdentifier = @"LoadedProfileButton";
    } else {
        [_profileButton setImage:[UIImage systemImageNamed:@"gear"] forState:UIControlStateNormal];
        _profileButton.contentMode = UIViewContentModeCenter;
    }
}

- (void)getUserStatusWithCompletionBlock:(GetUserStatusCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getUserStatusForAccount:activeAccount withCompletionBlock:^(NSDictionary *userStatusDict, NSError *error) {
        if (!error) {
            self->_activeUserStatus = [NCUserStatus userStatusWithDictionary:userStatusDict];
            [self updateProfileButtonImage];

            if (block) {
                block(userStatusDict, nil);
            }
        } else if (block) {
            block(nil, error);
        }
    }];
}

- (void)setUnreadMessageForInactiveAccountsIndicator
{
    NSInteger numberOfInactiveAccountsWithUnreadNotifications = [[NCDatabaseManager sharedInstance] numberOfInactiveAccountsWithUnreadNotifications];
    if (numberOfInactiveAccountsWithUnreadNotifications > 0) {
        if (@available(iOS 26.0, *)) {
            [_settingsButton setBadge:[UIBarButtonItemBadge badgeWithCount:numberOfInactiveAccountsWithUnreadNotifications]];
        } else {
            _settingsButton.legacyBadgeValue = [NSString stringWithFormat:@"%ld", numberOfInactiveAccountsWithUnreadNotifications];
        }
    }
}

#pragma mark - Threads

- (void)getUserThreads
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSInteger currentTimestamp = [[NSDate date] timeIntervalSince1970];

    // Check if user has threads on app fresh launch or if last check was over 2 hours ago
    if ((currentTimestamp - activeAccount.threadsLastCheckTimestamp) > (2 * 60 * 60)) {
        [[NCAPIController sharedInstance] getSubscribedThreadsFor:activeAccount.accountId withLimit:100 andOffset:0 completionBlock:^(NSArray<NCThread *> * _Nullable threads, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error getting user threads: %@", error);
            }
        }];
    }
}

#pragma mark - CCCertificateDelegate

- (void)trustedCerticateAccepted
{
    [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:NO onlyLastModified:NO];
}

#pragma mark - Room actions

- (UIAction *)actionForNotificationLevel:(NCRoomNotificationLevel)level forRoom:(NCRoom *)room
{
    UIAction *notificationAction = [UIAction actionWithTitle:[NCRoom stringForNotificationLevel:level] image:nil identifier:nil handler:^(UIAction *action) {
        if (level == room.notificationLevel) {
            return;
        }
        [[NCAPIController sharedInstance] setNotificationLevelWithLevel:level forRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(BOOL success) {
            if (success) {
                [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Updated notification settings", "") dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
            } else {
                NSLog(@"Error setting notification level");
            }

            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
        }];
    }];

    if (room.notificationLevel == level) {
        notificationAction.state = UIMenuElementStateOn;
    }

    return notificationAction;
}

- (void)shareLinkFromRoom:(NCRoom *)room
{
    NSIndexPath *indexPath = [self indexPathForRoom:room];
    if (indexPath) {
        [[NCUserInterfaceController sharedInstance] presentShareLinkDialogForRoom:room inViewContoller:self forIndexPath:indexPath];
    }
}

- (void)archiveRoom:(NCRoom *)room
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

    [[NCAPIController sharedInstance] archiveRoom:room.token forAccount:activeAccount completionBlock:^(BOOL success) {
        if (!success) {
            NSLog(@"Error archiving room");
        }

        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)unarchiveRoom:(NCRoom *)room
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

    [[NCAPIController sharedInstance] unarchiveRoom:room.token forAccount:activeAccount completionBlock:^(BOOL success) {
        if (!success) {
            NSLog(@"Error unarchiving room");
        }

        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)markRoomAsRead:(NCRoom *)room
{
    [[NCAPIController sharedInstance] setChatReadMarker:room.lastMessage.messageId inRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error marking room as read: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)markRoomAsUnread:(NCRoom *)room
{
    [[NCAPIController sharedInstance] markChatAsUnreadInRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error marking chat as unread: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)addRoomToFavorites:(NCRoom *)room
{
    [[NCAPIController sharedInstance] addRoomToFavorites:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error adding room to favorites: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)removeRoomFromFavorites:(NCRoom *)room
{
    [[NCAPIController sharedInstance] removeRoomFromFavorites:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error removing room from favorites: %@", error.description);
        }
        [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
    }];
}

- (void)presentRoomInfoForRoom:(NCRoom *)room
{
    UIViewController *roomInfoVC = [RoomInfoUIViewFactory createWithRoom:room showDestructiveActions:YES scrollToParticipantsSectionOnAppear:NO];
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:roomInfoVC];

    UIAction *cancelAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        [roomInfoVC dismissModalViewControllerAnimated:YES];
    }];

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel primaryAction:cancelAction];
    navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;

    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)leaveRoom:(NCRoom *)room
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Leave conversation", nil)
                                        message:NSLocalizedString(@"Once a conversation is left, to rejoin a closed conversation, an invite is needed. An open conversation can be rejoined at any time.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Leave", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];

        NSIndexPath *indexPath = [self indexPathForRoom:room];

        if (indexPath) {
            [self->_rooms removeObjectAtIndex:indexPath.row];
            [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }

        [[NCAPIController sharedInstance] removeSelfFromRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(OcsResponse * _Nullable response, NSError * _Nullable error) {
            if (error) {
                OcsError *ocsError = [error.userInfo objectForKey:@"ocsError"];
                if (ocsError.responseStatusCode == 400) {
                    [self showLeaveRoomLastModeratorErrorForRoom:room];
                } else {
                    NSLog(@"Error leaving room: %@", error.description);
                }
            }

            [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
        }];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)deleteRoom:(NCRoom *)room
{
    [[NCRoomsManager sharedInstance] deleteRoomWithConfirmation:room withStartedBlock:^{
        NSIndexPath *indexPath = [self indexPathForRoom:room];

        if (indexPath) {
            [self->_rooms removeObjectAtIndex:indexPath.row];
            [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    } andWithFinishedBlock:nil];
}

- (void)presentChatForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [self roomForIndexPath:indexPath];
    ChatViewController *currentChatViewController = [NCRoomsManager sharedInstance].chatViewController;

    // When a room is selected, that is currently displayed, leave that room and optionally show the placeholder view again
    if (currentChatViewController && [room.token isEqualToString:currentChatViewController.room.token]) {
        [currentChatViewController leaveChat];
        [[NCUserInterfaceController sharedInstance].mainViewController showPlaceholderView];

        return;
    }

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

- (NSIndexPath *)indexPathForRoom:(NCRoom *)room
{
    NSUInteger idx = [_rooms indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop){
        NCRoom *currentRoom = (NCRoom *)obj;
        return [currentRoom.internalId isEqualToString:room.internalId];
    }];

    if (idx != NSNotFound) {
        return [NSIndexPath indexPathForRow:idx inSection:kRoomsSectionRoomList];
    }

    return nil;
}

- (NSArray *)archivedRooms
{
    return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isArchived == YES"]];
}

- (BOOL)areArchivedRoomsWithUnreadMentions
{
    return [_allRooms filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"hasUnreadMention == YES AND isArchived == YES"]].count > 0;
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

#pragma mark - Search results

- (void)presentSelectedMessageInChat:(NKSearchEntry *)message
{
    NSString *roomToken = [message.attributes objectForKey:@"conversation"];
    NSString *messageIdString = [message.attributes objectForKey:@"messageId"];
    NSString *threadIdString = [message.attributes objectForKey:@"threadId"];
    if (roomToken && messageIdString) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        NSInteger messageId = [messageIdString intValue];
        NCRoom *room = [[NCDatabaseManager sharedInstance] roomWithToken:roomToken forAccountId:activeAccount.accountId];
        NSInteger threadId = [threadIdString intValue];
        NCThread *thread = [NCThread threadWithThreadId:threadId inRoom:roomToken forAccountId:activeAccount.accountId];
        if (room) {
            [self presentContextChatInRoom:room inThread:thread forMessageId:messageId];
        } else {
            [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:roomToken completionBlock:^(NSDictionary *roomDict, NSError *error) {
                if (!error) {
                    NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                    [self presentContextChatInRoom:room inThread:thread forMessageId:messageId];
                } else {
                    NSString *errorMessage = NSLocalizedString(@"Unable to get conversation of the message", nil);
                    [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:errorMessage dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleDark];
                }
            }];
        }
    }
}

- (void)presentContextChatInRoom:(NCRoom *)room inThread:(NCThread *)thread forMessageId:(NSInteger)messageId
{
    TalkAccount *account = room.account;

    if (!account) {
        return;
    }

    ContextChatViewController *contextChatViewController = [[ContextChatViewController alloc] initForRoom:room withAccount:account withMessage:@[] withHighlightId:0];
    contextChatViewController.thread = thread;
    [contextChatViewController showContextOfMessageId:messageId withLimit:50 withCloseButton:YES];

    _contextChatNavigationController = [[NCNavigationController alloc] initWithRootViewController:contextChatViewController];
    [self presentViewController:_contextChatNavigationController animated:YES completion:nil];
}

- (void)createRoomForSelectedUser:(NCUser *)user
{
    [[NCAPIController sharedInstance]
     createRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withInvite:user.userId
     ofType:kNCRoomTypeOneToOne
     andName:nil
     completionBlock:^(NCRoom *room, NSError *error) {
        if (!error && room.token != nil) {
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [[NSNotificationCenter defaultCenter] postNotificationName:NCSelectedUserForChatNotification
                                                                    object:self
                                                                  userInfo:@{@"token":room.token}];
            }];
        }

        [self->_searchController setActive:NO];
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kRoomsSectionsCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kRoomsSectionPendingFederationInvitation) {
        TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
        return account.pendingFederationInvitations > 0 ? 1 : 0;
    }

    if (section == kRoomsSectionArchivedConversations) {
        return [self archivedRooms].count > 0 || _showingArchivedRooms ? 1 : 0;
    }

    if (section == kRoomsSectionThreads) {
        TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
        return (account.hasThreads || _threads.count > 0) ? 1 : 0;
    }

    return _rooms.count;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == self.tableView &&
        (indexPath.section == kRoomsSectionPendingFederationInvitation ||
         indexPath.section == kRoomsSectionArchivedConversations ||
         indexPath.section == kRoomsSectionThreads)) {
        // No swipe action for pending invitations or archived conversations
        return nil;
    }

    NCRoom *room = [self roomForIndexPath:indexPath];

    // Do not show swipe actions for open conversations or messages
    if ((tableView == _resultTableViewController.tableView && room.listable) || !room) {
        return nil;
    }

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                                            handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                                [self deleteRoom:room];
                                                                                completionHandler(false);
                                                                            }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];

    if (room.canLeaveConversation) {
        deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                 [self leaveRoom:room];
                                                                 completionHandler(false);
                                                             }];
        deleteAction.image = [UIImage systemImageNamed:@"arrow.right.square"];
    }
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if (tableView == self.tableView &&
        (indexPath.section == kRoomsSectionPendingFederationInvitation ||
         indexPath.section == kRoomsSectionArchivedConversations ||
         indexPath.section == kRoomsSectionThreads)) {
        // No swipe action for pending invitations or archived conversations
        return nil;
    }

    NCRoom *room = [self roomForIndexPath:indexPath];
    
    // Do not show swipe actions for open conversations or messages
    if ((tableView == _resultTableViewController.tableView && room.listable) || !room) {
        return nil;
    }

    // Add/Remove room to/from favorites
    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil
                                                                               handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                                                                                   if (room.isFavorite) {
                                                                                       [self removeRoomFromFavorites:room];
                                                                                   } else {
                                                                                       [self addRoomToFavorites:room];
                                                                                   }
                                                                                   completionHandler(true);
                                                                               }];
    NSString *favImageName = (room.isFavorite) ? @"star" : @"star.fill";
    favoriteAction.image = [UIImage systemImageNamed:favImageName];
    favoriteAction.backgroundColor = [UIColor colorWithRed:0.97 green:0.80 blue:0.27 alpha:1.0]; // Favorite yellow

    // Mark room as read/unread
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker] &&
        (!room.isFederated || [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadLast])) {

        UIContextualAction *markReadAction = [UIContextualAction
                                              contextualActionWithStyle:UIContextualActionStyleNormal title:nil
                                              handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            if (room.unreadMessages > 0) {
                [self markRoomAsRead:room];
            } else {
                [self markRoomAsUnread:room];
            }
            completionHandler(true);
        }];

        markReadAction.image = (room.unreadMessages > 0) ? [UIImage systemImageNamed:@"checkmark.bubble"] : [UIImage imageNamed:@"custom.bubble.badge"];
        markReadAction.backgroundColor = [UIColor systemBlueColor];

        return [UISwipeActionsConfiguration configurationWithActions:@[markReadAction, favoriteAction]];
    }
    
    return [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kRoomsSectionPendingFederationInvitation) {
        InfoLabelTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:InfoLabelTableViewCell.identifier];
        if (!cell) {
            cell = [[InfoLabelTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:InfoLabelTableViewCell.identifier];
        }

        // Pending federation invitations
        TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];

        NSString *pendingInvitationsString = [NSString localizedStringWithFormat:NSLocalizedString(@"You have %ld pending invitations", nil), (long)account.pendingFederationInvitations];
        UIFont *resultFont = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

        NSTextAttachment *pendingInvitationsAttachment = [[NSTextAttachment alloc] init];
        pendingInvitationsAttachment.image = [UIImage imageNamed:@"pending-federation-invitations"];
        pendingInvitationsAttachment.bounds = CGRectMake(0, roundf(resultFont.capHeight - 20) / 2, 20, 20);

        NSMutableAttributedString *resultString = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:pendingInvitationsAttachment]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:pendingInvitationsString]];

        NSRange range = NSMakeRange(0, [resultString length]);
        [resultString addAttribute:NSFontAttributeName value:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] range:range];

        cell.label.attributedText = resultString;

        return cell;
    }

    if (indexPath.section == kRoomsSectionArchivedConversations) {
        InfoLabelTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:InfoLabelTableViewCell.identifier];
        if (!cell) {
            cell = [[InfoLabelTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:InfoLabelTableViewCell.identifier];
        }

        NSString *actionString = _showingArchivedRooms ? NSLocalizedString(@"Back to conversations", nil) : NSLocalizedString(@"Archived conversations", nil);
        NSString *iconName = _showingArchivedRooms ? @"arrow.left" : @"archivebox";
        UIFont *resultFont = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = [[UIImage systemImageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        attachment.bounds = CGRectMake(0, roundf(resultFont.capHeight - 20) / 2, 24, 20);

        NSMutableAttributedString *resultString = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:actionString]];

        NSRange range = NSMakeRange(0, [resultString length]);
        [resultString addAttribute:NSFontAttributeName value:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] range:range];

        if (!_showingArchivedRooms && [self areArchivedRoomsWithUnreadMentions]) {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:[NCAppBranding elementColor] renderingMode:UIImageRenderingModeAlwaysTemplate];
            attachment.bounds = CGRectMake(0, roundf(resultFont.capHeight - 20) / 2, 20, 20);

            [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
            [resultString appendAttributedString:[[NSAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]]];
        }

        cell.label.attributedText = resultString;

        return cell;
    }

    if (indexPath.section == kRoomsSectionThreads) {
        InfoLabelTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:InfoLabelTableViewCell.identifier];
        if (!cell) {
            cell = [[InfoLabelTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:InfoLabelTableViewCell.identifier];
        }

        UIFont *resultFont = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = [[UIImage systemImageNamed:@"bubble.left.and.bubble.right"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        attachment.bounds = CGRectMake(0, roundf(resultFont.capHeight - 20) / 2, 24, 20);

        NSMutableAttributedString *resultString = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        [resultString appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"Threads", nil)]];

        NSRange range = NSMakeRange(0, [resultString length]);
        [resultString addAttribute:NSFontAttributeName value:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] range:range];

        cell.label.attributedText = resultString;
        cell.separatorInset = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, CGFLOAT_MAX);

        return cell;
    }

    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RoomTableViewCell.identifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RoomTableViewCell.identifier];
    }

    cell.backgroundColor = [UIColor clearColor];

    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    // Set room name
    cell.titleLabel.text = room.displayName;
    
    // Set last activity
    if (room.lastMessageId || room.lastMessageProxiedJSONString) {
        cell.titleOnly = NO;
        cell.subtitleLabel.attributedText = room.lastMessageString;
    } else {
        cell.titleOnly = YES;
        cell.subtitleLabel.text = @"";
    }
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastActivity];
    cell.dateLabel.text = [NCUtils readableTimeOrDateFromDate:date];

    // Event conversation handling
    if ([room isFutureEvent]) {
        cell.titleOnly = NO;
        cell.subtitleLabel.text = [room eventStartString];
        cell.dateLabel.text = @"";
    }

    // Set unread messages
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag]) {
        BOOL mentioned = room.unreadMentionDirect || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        BOOL groupMentioned = room.unreadMention && !room.unreadMentionDirect;
        [cell setUnreadWithMessages:room.unreadMessages mentioned:mentioned groupMentioned:groupMentioned];
    } else {
        BOOL mentioned = room.unreadMention || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        [cell setUnreadWithMessages:room.unreadMessages mentioned:mentioned groupMentioned:NO];
    }

    if (room.unreadMessages > 0) {
        // When there are unread messages, we need to show the subtitle at the moment
        cell.titleOnly = NO;
    }

    [cell.avatarView setAvatarFor:room];

    // Set favorite or call image
    if (room.hasCall) {
        [cell.avatarView.favoriteImageView setTintColor:[UIColor systemRedColor]];
        [cell.avatarView.favoriteImageView setImage:[UIImage systemImageNamed:@"video.fill"]];
    } else if (room.isFavorite) {
        [cell.avatarView.favoriteImageView setTintColor:[UIColor systemYellowColor]];
        [cell.avatarView.favoriteImageView setImage:[UIImage systemImageNamed:@"star.fill"]];
    }

    cell.roomToken = room.token;

    return cell;
}

- (void)tableView:(UITableView *)tableView didHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    RoomTableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [cell setSelected:YES];
}


- (void)tableView:(UITableView *)tableView didUnhighlightRowAtIndexPath:(NSIndexPath *)indexPath
{
    RoomTableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [cell setSelected:NO];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)rcell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView != self.tableView ||
        indexPath.section == kRoomsSectionPendingFederationInvitation ||
        indexPath.section == kRoomsSectionArchivedConversations ||
        indexPath.section == kRoomsSectionThreads) {
        return;
    }

    RoomTableViewCell *cell = (RoomTableViewCell *)rcell;
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];

    [cell.avatarView setStatusFor:room allowCustomStatusIcon:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL isAppInForeground = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;

    if (!isAppInForeground) {
        // In case we are not in the active state, we don't want to invoke any navigation event as this might
        // lead to crashes, when the wrong NavBar is referenced
        return;
    }

    if (self.navigationController.transitionCoordinator != nil) {
        // In case we are currently in a transition (e.g. swipe back from a conversation),
        // we don't want to present any new view controller, as that leads to crashes on iOS >= 26
        [self removeRoomSelection];
        return;
    }

    if (tableView == self.tableView && indexPath.section == kRoomsSectionPendingFederationInvitation) {
        FederationInvitationTableViewController *federationInvitationVC = [[FederationInvitationTableViewController alloc] init];
        NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:federationInvitationVC];
        [self presentViewController:navigationController animated:YES completion:nil];
        
        return;
    }

    if (tableView == self.tableView && indexPath.section == kRoomsSectionArchivedConversations) {
        _showingArchivedRooms = !_showingArchivedRooms;
        [UIView transitionWithView:self.tableView duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            [self filterRooms];
            [self updateMentionsIndicator];
        } completion:nil];
        return;
    }

    if (tableView == self.tableView && indexPath.section == kRoomsSectionThreads) {
        [UIView transitionWithView:self.tableView duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            ThreadsTableViewController *threadsVC = [[ThreadsTableViewController alloc] initWithThreads:self->_threads];
            NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:threadsVC];
            [self presentViewController:navigationController animated:YES completion:nil];
        } completion:nil];
        return;
    }

    if (tableView == _resultTableViewController.tableView) {
        // Messages
        NKSearchEntry *message = [_resultTableViewController messageForIndexPath:indexPath];
        if (message) {
            [self presentSelectedMessageInChat:message];
            return;
        }

        // Users
        NCUser *user = [_resultTableViewController userForIndexPath:indexPath];
        if (user) {
            [self createRoomForSelectedUser:user];
            return;
        }
    }
    
    // Present room chat
    [self removeRoomSelection];
    [self presentChatForRoomAtIndexPath:indexPath];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point
{
    if (tableView != self.tableView ||
        indexPath.section == kRoomsSectionPendingFederationInvitation ||
        indexPath.section == kRoomsSectionArchivedConversations ||
        indexPath.section == kRoomsSectionThreads) {
        return nil;
    }

    __weak typeof(self) weakSelf = self;

    NCRoom *room = [self roomForIndexPath:indexPath];
    NSMutableArray *actions = [[NSMutableArray alloc] init];

    NSString *favImageName = (room.isFavorite) ? @"star.slash" : @"star";
    UIImage *favImage = [[UIImage systemImageNamed:favImageName] imageWithTintColor:UIColor.systemYellowColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    NSString *favActionName = (room.isFavorite) ? NSLocalizedString(@"Remove from favorites", nil) : NSLocalizedString(@"Add to favorites", nil);
    UIAction *favAction = [UIAction actionWithTitle:favActionName image:favImage identifier:nil handler:^(UIAction *action) {
        weakSelf.contextMenuActionBlock = ^{
            if (room.isFavorite) {
                [weakSelf removeRoomFromFavorites:room];
            } else {
                [weakSelf addRoomToFavorites:room];
            }
        };
    }];

    [actions addObject:favAction];

    // Mark room as read/unread
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker] &&
        (!room.isFederated || [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadLast])) {
        if (room.unreadMessages > 0) {
            // Mark room as read
            UIAction *markReadAction = [UIAction actionWithTitle:NSLocalizedString(@"Mark as read", nil) image:[UIImage systemImageNamed:@"checkmark.bubble"] identifier:nil handler:^(UIAction *action) {
                weakSelf.contextMenuActionBlock = ^{
                    [weakSelf markRoomAsRead:room];
                };
            }];

            [actions addObject:markReadAction];
        } else if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatUnread]) {
            // Mark room as unread
            UIAction *markUnreadAction = [UIAction actionWithTitle:NSLocalizedString(@"Mark as unread", nil) image:[UIImage imageNamed:@"custom.bubble.badge"] identifier:nil handler:^(UIAction *action) {
                weakSelf.contextMenuActionBlock = ^{
                    [weakSelf markRoomAsUnread:room];
                };
            }];

            [actions addObject:markUnreadAction];
        }
    }

    // Notification levels
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels] &&
        room.type != kNCRoomTypeChangelog && room.type != kNCRoomTypeNoteToSelf) {

        NSMutableArray *notificationActions = [[NSMutableArray alloc] init];

        // Chat notification settings
        [notificationActions addObject:[self actionForNotificationLevel:kNCRoomNotificationLevelAlways forRoom:room]];
        [notificationActions addObject:[self actionForNotificationLevel:kNCRoomNotificationLevelMention forRoom:room]];
        [notificationActions addObject:[self actionForNotificationLevel:kNCRoomNotificationLevelNever forRoom:room]];

        // Call notification
        if ([[NCDatabaseManager sharedInstance] roomHasTalkCapability:kCapabilityNotificationCalls forRoom:room] && [room supportsCalling]) {
            UIAction *callNotificationAction = [UIAction actionWithTitle:NSLocalizedString(@"Notify about calls", nil) image:nil identifier:nil handler:^(UIAction *action) {
                BOOL newState = !(action.state == UIMenuElementStateOn);

                [[NCAPIController sharedInstance] setCallNotificationLevelWithEnabled:newState forRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(BOOL success) {
                    if (success) {
                        [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Updated notification settings", "") dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
                    } else {
                        NSLog(@"Error setting call notification");
                    }

                    [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
                }];
            }];

            if (room.notificationCalls) {
                callNotificationAction.state = UIMenuElementStateOn;
            }

            UIMenu *callNotificationMenu = [UIMenu menuWithTitle:nil image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[callNotificationAction]];
            [notificationActions addObject:callNotificationMenu];
        }

        // Important conversation
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityImportantConversations]) {
            UIAction *importantConversationAction = [UIAction actionWithTitle:NSLocalizedString(@"Important conversation", nil) image:nil identifier:nil handler:^(UIAction *action) {
                BOOL newState = !(action.state == UIMenuElementStateOn);

                [[NCAPIController sharedInstance] setImportantStateWithEnabled:newState forRoom:room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(NCRoom * _Nullable room, NSError * _Nullable error) {
                    if (error) {
                        NSLog(@"Error setting call notification: %@", error.description);
                    } else {
                        [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Updated notification settings", "") dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
                    }

                    [[NCRoomsManager sharedInstance] updateRoomsUpdatingUserStatus:YES onlyLastModified:NO];
                }];
            }];

            importantConversationAction.subtitle = NSLocalizedString(@"'Do not disturb' user status is ignored for important conversations", nil);

            if (room.isImportant) {
                importantConversationAction.state = UIMenuElementStateOn;
            }

            UIMenu *importantConversationMenu = [UIMenu menuWithTitle:nil image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[importantConversationAction]];
            [notificationActions addObject:importantConversationMenu];
        }

        UIMenu *notificationMenu = [UIMenu menuWithTitle:NSLocalizedString(@"Notifications", nil)
                                                   image:[UIImage systemImageNamed:@"bell"]
                                              identifier:nil
                                                 options:0
                                                children:notificationActions];

        [actions addObject:notificationMenu];
    }

    // Share link
    if (room.type != kNCRoomTypeChangelog && room.type != kNCRoomTypeNoteToSelf) {
        UIAction *notificationActions = [UIAction actionWithTitle:NSLocalizedString(@"Share link", nil) image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *action) {
            [weakSelf shareLinkFromRoom:room];
        }];

        [actions addObject:notificationActions];
    }

    // Archive conversation
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityArchivedConversationsV2]) {
        if (room.isArchived) {
            UIAction *unarchiveAction = [UIAction actionWithTitle:NSLocalizedString(@"Unarchive conversation", nil) image:[UIImage systemImageNamed:@"arrow.up.bin"] identifier:nil handler:^(UIAction *action) {
                [weakSelf unarchiveRoom:room];
            }];

            [actions addObject:unarchiveAction];
        } else {
            UIAction *archiveAction = [UIAction actionWithTitle:NSLocalizedString(@"Archive conversation", nil) image:[UIImage systemImageNamed:@"archivebox"] identifier:nil handler:^(UIAction *action) {
                [weakSelf archiveRoom:room];
            }];

            [actions addObject:archiveAction];
        }
    }

    // Room info
    UIAction *roomInfoAction = [UIAction actionWithTitle:NSLocalizedString(@"Conversation settings", nil) image:[UIImage systemImageNamed:@"gearshape"] identifier:nil handler:^(UIAction *action) {
        [weakSelf presentRoomInfoForRoom:room];
    }];

    [actions addObject:roomInfoAction];

    NSMutableArray *destructiveActions = [[NSMutableArray alloc] init];

    if (room.canLeaveConversation) {
        UIAction *leaveAction = [UIAction actionWithTitle:NSLocalizedString(@"Leave conversation", nil) image:[UIImage systemImageNamed:@"arrow.right.square"] identifier:nil handler:^(UIAction *action) {
            [weakSelf leaveRoom:room];
        }];

        leaveAction.attributes = UIMenuElementAttributesDestructive;
        [destructiveActions addObject:leaveAction];
    }

    if (room.canDeleteConversation) {
        UIAction *deleteAction = [UIAction actionWithTitle:NSLocalizedString(@"Delete conversation", nil) image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            [weakSelf deleteRoom:room];
        }];

        deleteAction.attributes = UIMenuElementAttributesDestructive;
        [destructiveActions addObject:deleteAction];
    }

    if (destructiveActions.count > 0) {
        UIMenu *deleteMenu = [UIMenu menuWithTitle:@""
                                             image:nil
                                        identifier:nil
                                           options:UIMenuOptionsDisplayInline
                                          children:destructiveActions];
        
        [actions addObject:deleteMenu];
    }

    UIMenu *menu = [UIMenu menuWithTitle:@"" children:actions];

    UIContextMenuConfiguration *configuration = [UIContextMenuConfiguration configurationWithIdentifier:indexPath previewProvider:^UIViewController * _Nullable{
        return nil;
    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return menu;
    }];

    return configuration;
}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
    if (![tableView isEqual:self.tableView]) {
        return nil;
    }

    if (@available(iOS 26.0, *)) {
        // Don't provide a preview here in case of iOS 26 as it just looks bad
        return nil;
    }

    NSIndexPath *indexPath = (NSIndexPath *)configuration.identifier;

    // Use a snapshot here to not interfere with room refresh
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    UIView *previewView = [cell.contentView snapshotViewAfterScreenUpdates:NO];
    previewView.backgroundColor = UIColor.systemBackgroundColor;

    // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
    CGFloat cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2;
    CGPoint cellCenter = CGPointMake(cellCenterX, cell.center.y);

    // Create a preview target which allows us to have a transparent background
    UIPreviewTarget *previewTarget = [[UIPreviewTarget alloc] initWithContainer:self.view center:cellCenter];
    UIPreviewParameters *previewParameter = [[UIPreviewParameters alloc] init];

    // Remove the background and the drop shadow from our custom preview view
    previewParameter.backgroundColor = UIColor.systemBackgroundColor;
    previewParameter.shadowPath = [[UIBezierPath alloc] init];

    return [[UITargetedPreview alloc] initWithView:previewView parameters:previewParameter target:previewTarget];
}

- (void)tableView:(UITableView *)tableView willEndContextMenuInteractionWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator
{
    if (![tableView isEqual:self.tableView]) {
        return;
    }

    [animator addCompletion:^{
        // Wait until the context menu is completely hidden before we execute any method
        if (self->_contextMenuActionBlock) {
            self->_contextMenuActionBlock();
            self->_contextMenuActionBlock = nil;
        }
    }];
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
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:idx inSection:kRoomsSectionRoomList];
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    } else {
        NSIndexPath *selectedRow = [self.tableView indexPathForSelectedRow];
        if (selectedRow != nil) {
            [self.tableView deselectRowAtIndexPath:selectedRow animated:YES];

            // It might happen that this is called while we are switching accounts, so wait for the reload to be finished.
            // Example: Active account has 1 pending invitation, switch to an account with no pending invitation -> crash.
            dispatch_async(dispatch_get_main_queue(), ^{
                // Needed to make sure the highlight is really removed
                [self.tableView reloadRowsAtIndexPaths:@[selectedRow] withRowAnimation:UITableViewRowAnimationNone];
            });
        }
    }
}

@end
