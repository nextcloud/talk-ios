//
//  SettingsViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 05.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "SettingsViewController.h"

#import "NCSettingsController.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "AccountTableViewCell.h"
#import "UserSettingsTableViewCell.h"
#import "NCAPIController.h"
#import "NCUserInterfaceController.h"
#import "NCUserStatus.h"
#import "NCConnectionController.h"
#import "OpenInFirefoxControllerObjC.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "CCBKPasscode.h"
#import "RoundedNumberView.h"
#import <SafariServices/SafariServices.h>

typedef enum SettingsSection {
    kSettingsSectionUser = 0,
    kSettingsSectionUserStatus,
    kSettingsSectionAccounts,
    kSettingsSectionConfiguration,
    kSettingsSectionLock,
    kSettingsSectionAbout
} SettingsSection;

typedef enum LockSection {
    kLockSectionOn = 0,
    kLockSectionUseSimply,
    kLockSectionNumber
} LockSection;

typedef enum ConfigurationSection {
    kConfigurationSectionVideo = 0,
    kConfigurationSectionBrowser,// Keep it always as last option
    kConfigurationSectionNumber
} ConfigurationSection;

typedef enum AboutSection {
    kAboutSectionPrivacy = 0,
    kAboutSectionSourceCode,
    kAboutSectionNumber
} AboutSection;

@interface SettingsViewController ()
{
    NCUserStatus *_activeUserStatus;
}

@end

@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Profile", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[UIColor whiteColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
    
    [self.tableView registerNib:[UINib nibWithNibName:kUserSettingsTableCellNibName bundle:nil] forCellReuseIdentifier:kUserSettingsCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kAccountTableViewCellNibName bundle:nil] forCellReuseIdentifier:kAccountCellIdentifier];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self.tableView reloadData];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)cancelButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:true completion:nil];
}

- (NSArray *)getSettingsSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    // Active user sections
    [sections addObject:[NSNumber numberWithInt:kSettingsSectionUser]];
    // User Status section
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities.userStatus) {
        [sections addObject:[NSNumber numberWithInt:kSettingsSectionUserStatus]];
    }
    // Accounts section
    if ([[NCDatabaseManager sharedInstance] inactiveAccounts].count > 0) {
        [sections addObject:[NSNumber numberWithInt:kSettingsSectionAccounts]];
    }
    // Configuration section
    [sections addObject:[NSNumber numberWithInt:kSettingsSectionConfiguration]];
    // Lock section
//    [sections addObject:[NSNumber numberWithInt:kSettingsSectionLock]];
    // About section
    [sections addObject:[NSNumber numberWithInt:kSettingsSectionAbout]];

    return [NSArray arrayWithArray:sections];
}

- (NSInteger)getSectionForSettingsSection:(SettingsSection)section
{
    NSInteger sectionNumber = [[self getSettingsSections] indexOfObject:[NSNumber numberWithInt:section]];
    if(NSNotFound != sectionNumber) {
        return sectionNumber;
    }
    return 0;
}

#pragma mark - User Profile

- (void)refreshUserProfile
{
    [[NCSettingsController sharedInstance] getUserProfileWithCompletionBlock:^(NSError *error) {
        [self.tableView reloadData];
    }];
    
    [self getActiveUserStatus];
}

- (void)getActiveUserStatus
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getUserStatusForAccount:activeAccount withCompletionBlock:^(NSDictionary *userStatus, NSError *error) {
        if (!error && userStatus) {
            self->_activeUserStatus = [NCUserStatus userStatusWithDictionary:userStatus];
            [self.tableView reloadData];
        }
    }];
}

#pragma mark - Notifications

- (void)appStateHasChanged:(NSNotification *)notification
{
    AppState appState = [[notification.userInfo objectForKey:@"appState"] intValue];
    [self adaptInterfaceForAppState:appState];
}

#pragma mark - User Interface

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case kAppStateReady:
        {
            [self refreshUserProfile];
        }
            break;
            
        default:
            break;
    }
}

#pragma mark - Profile actions

- (void)userProfilePressed
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *actionTitle = (multiAccountEnabled) ? NSLocalizedString(@"Remove account", nil) : NSLocalizedString(@"Log out", nil);
    UIImage *actionImage = (multiAccountEnabled) ? [UIImage imageNamed:@"delete-action"] : [UIImage imageNamed:@"logout"];
    
    if (multiAccountEnabled) {
        UIAlertAction *addAccountAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Add account", nil)
                                           style:UIAlertActionStyleDefault
                                           handler:^void (UIAlertAction *action) {
                                                [self addNewAccount];
                                            }];
        [addAccountAction setValue:[[UIImage imageNamed:@"add-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:addAccountAction];
    }
    
    UIAlertAction *logOutAction = [UIAlertAction actionWithTitle:actionTitle
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^void (UIAlertAction *action) {
                                                       [self showLogoutConfirmationDialog];
                                                   }];
    [logOutAction setValue:[actionImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:logOutAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:[self getSectionForSettingsSection:kSettingsSectionUser]]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)addNewAccount
{
    [self dismissViewControllerAnimated:true completion:^{
        [[NCUserInterfaceController sharedInstance] presentLoginViewController];
    }];
}

- (void)showLogoutConfirmationDialog
{
    NSString *alertTitle = (multiAccountEnabled) ? NSLocalizedString(@"Remove account", nil) : NSLocalizedString(@"Log out", nil);
    NSString *alertMessage = (multiAccountEnabled) ? NSLocalizedString(@"Do you really want to remove this account?", nil) : NSLocalizedString(@"Do you really want to log out from this account?", nil);
    NSString *actionTitle = (multiAccountEnabled) ? NSLocalizedString(@"Remove", nil) : NSLocalizedString(@"Log out", nil);
    
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:alertMessage
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self logout];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)logout
{
    [[NCSettingsController sharedInstance] logoutWithCompletionBlock:^(NSError *error) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
        [[NCConnectionController sharedInstance] checkAppState];
    }];
}

#pragma mark - User Status

- (void)presentUserStatusOptions
{
    UIAlertController *userStatusActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *onlineAction = [UIAlertAction actionWithTitle:[NCUserStatus readableUserStatusFromUserStatus:kUserStatusOnline]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
                                                        [self setActiveUserStatus:kUserStatusOnline];
                                                   }];
    [onlineAction setValue:[[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusOnline ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [userStatusActionSheet addAction:onlineAction];
    
    UIAlertAction *awayAction = [UIAlertAction actionWithTitle:[NCUserStatus readableUserStatusFromUserStatus:kUserStatusAway]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                            [self setActiveUserStatus:kUserStatusAway];
                                                        }];
    [awayAction setValue:[[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusAway ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [userStatusActionSheet addAction:awayAction];
    
    UIAlertAction *dndAction = [UIAlertAction actionWithTitle:[NCUserStatus readableUserStatusFromUserStatus:kUserStatusDND]
                                                        style:UIAlertActionStyleDefault
                                                      handler:^void (UIAlertAction *action) {
                                                        [self setActiveUserStatus:kUserStatusDND];
                                                      }];
    [dndAction setValue:[[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusDND ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [userStatusActionSheet addAction:dndAction];
    
    UIAlertAction *invisibleAction = [UIAlertAction actionWithTitle:[NCUserStatus readableUserStatusFromUserStatus:kUserStatusInvisible]
                                                              style:UIAlertActionStyleDefault
                                                            handler:^void (UIAlertAction *action) {
                                                                [self setActiveUserStatus:kUserStatusInvisible];
                                                            }];
    [invisibleAction setValue:[[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusInvisible ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [userStatusActionSheet addAction:invisibleAction];
    
    
    
    [userStatusActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    userStatusActionSheet.popoverPresentationController.sourceView = self.tableView;
    userStatusActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:[self getSectionForSettingsSection:kSettingsSectionUserStatus]]];
    
    [self presentViewController:userStatusActionSheet animated:YES completion:nil];
}

- (void)setActiveUserStatus:(NSString *)userStatus
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] setUserStatus:userStatus forAccount:activeAccount withCompletionBlock:^(NSError *error) {
        [self getActiveUserStatus];
    }];
}

#pragma mark - Configuration

- (void)presentVideoResolutionsSelector
{
    NSIndexPath *videoConfIndexPath = [NSIndexPath indexPathForRow:kConfigurationSectionVideo inSection:[self getSectionForSettingsSection:kSettingsSectionConfiguration]];
    NSArray *videoResolutions = [[[NCSettingsController sharedInstance] videoSettingsModel] availableVideoResolutions];
    NSString *storedResolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Video quality", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *resolution in videoResolutions) {
        NSString *readableResolution = [[[NCSettingsController sharedInstance] videoSettingsModel] readableResolution:resolution];
        BOOL isStoredResolution = [resolution isEqualToString:storedResolution];
        UIAlertAction *action = [UIAlertAction actionWithTitle:readableResolution
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [[[NCSettingsController sharedInstance] videoSettingsModel] storeVideoResolutionSetting:resolution];
                                                           [self.tableView beginUpdates];
                                                           [self.tableView reloadRowsAtIndexPaths:@[videoConfIndexPath] withRowAnimation:UITableViewRowAnimationNone];
                                                           [self.tableView endUpdates];
                                                       }];
        if (isStoredResolution) {
            [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        }
        
        [optionsActionSheet addAction:action];
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:videoConfIndexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)presentBrowserSelector
{
    NSIndexPath *browserConfIndexPath = [NSIndexPath indexPathForRow:kConfigurationSectionBrowser inSection:[self getSectionForSettingsSection:kSettingsSectionConfiguration]];
    NSArray *supportedBrowsers = [[NCSettingsController sharedInstance] supportedBrowsers];
    NSString *defaultBrowser = [[NCSettingsController sharedInstance] defaultBrowser];
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Open links in", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *browser in supportedBrowsers) {
        BOOL isDefaultBrowser = [browser isEqualToString:defaultBrowser];
        UIAlertAction *action = [UIAlertAction actionWithTitle:browser
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [NCSettingsController sharedInstance].defaultBrowser = browser;
                                                           [self.tableView beginUpdates];
                                                           [self.tableView reloadRowsAtIndexPaths:@[browserConfIndexPath] withRowAnimation:UITableViewRowAnimationNone];
                                                           [self.tableView endUpdates];
                                                       }];
        if (isDefaultBrowser) {
            [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        }
        
        [optionsActionSheet addAction:action];
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:browserConfIndexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getSettingsSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:section] intValue];
    switch (settingsSection) {
        case kSettingsSectionUserStatus:
            return 1;
            break;
            
        case kSettingsSectionConfiguration:
        {
            NSUInteger numberOfSupportedBrowsers = [NCSettingsController sharedInstance].supportedBrowsers.count;
            return (numberOfSupportedBrowsers > 1) ? kConfigurationSectionNumber : kConfigurationSectionNumber - 1;
        }
            break;

        case kSettingsSectionLock:
            return kLockSectionNumber;
            break;
            
        case kSettingsSectionAbout:
            return kAboutSectionNumber;
            break;
            
        case kSettingsSectionAccounts:
        {
            return [[NCDatabaseManager sharedInstance] inactiveAccounts].count;
        }
            break;
            
        default:
            break;
    }
    
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:indexPath.section] intValue];
    if (settingsSection == kSettingsSectionUser) {
        return 100;
    }
    
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:section] intValue];
    switch (settingsSection) {
        case kSettingsSectionUserStatus:
            return NSLocalizedString(@"Status", nil);
            break;
            
        case kSettingsSectionAccounts:
            return NSLocalizedString(@"Accounts", nil);
            break;
            
        case kSettingsSectionConfiguration:
            return NSLocalizedString(@"Configuration", nil);
            break;
            
        case kSettingsSectionLock:
            return NSLocalizedString(@"Lock", nil);
            break;

        case kSettingsSectionAbout:
            return NSLocalizedString(@"About", nil);
            break;
            
        default:
            break;
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:section] intValue];
    if (settingsSection == kSettingsSectionAbout) {
        NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
        NSString *copyright = @"© 2020 Nextcloud GmbH";
        return [NSString stringWithFormat:@"%@ %@ %@", appName, appVersion, copyright];
    }
    if (settingsSection == kSettingsSectionUserStatus && [_activeUserStatus.status isEqualToString:kUserStatusDND]) {
        return NSLocalizedString(@"All notifications are muted", nil);
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *videoConfigurationCellIdentifier = @"VideoConfigurationCellIdentifier";
    static NSString *browserConfigurationCellIdentifier = @"BrowserConfigurationCellIdentifier";
    static NSString *privacyCellIdentifier = @"PrivacyCellIdentifier";
    static NSString *sourceCodeCellIdentifier = @"SourceCodeCellIdentifier";
    static NSString *lockOnCellIdentifier = @"LockOnCellIdentifier";
    static NSString *lockUseSimplyCellIdentifier = @"LockUseSimplyCellIdentifier";
    static NSString *userStatusCellIdentifier = @"UserStatusCellIdentifier";
    
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:indexPath.section] intValue];
    switch (settingsSection) {
        case kSettingsSectionUser:
        {
            UserSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUserSettingsCellIdentifier];
            if (!cell) {
                cell = [[UserSettingsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kUserSettingsCellIdentifier];
            }
            
            TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
            cell.userDisplayNameLabel.text = activeAccount.userDisplayName;
            NSString *accountServer = [activeAccount.server stringByReplacingOccurrencesOfString:[[NSURL URLWithString:activeAccount.server] scheme] withString:@""];
            cell.serverAddressLabel.text = [accountServer stringByReplacingOccurrencesOfString:@"://" withString:@""];
            [cell.userImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:activeAccount withSize:CGSizeMake(160, 160)]];
            return cell;
        }
            break;
        case kSettingsSectionUserStatus:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:userStatusCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:userStatusCellIdentifier];
            }
            if (_activeUserStatus) {
                cell.textLabel.text = [_activeUserStatus readableUserStatus];
                [cell.imageView setImage:[UIImage imageNamed:[_activeUserStatus userStatusImageNameOfSize:24]]];
            } else {
                cell.textLabel.text = NSLocalizedString(@"Fetching status…", nil);
            }
        }
            break;
        case kSettingsSectionAccounts:
        {
            NSArray *inactiveAccounts = [[NCDatabaseManager sharedInstance] inactiveAccounts];
            TalkAccount *account = [inactiveAccounts objectAtIndex:indexPath.row];
            AccountTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAccountCellIdentifier];
            if (!cell) {
                cell = [[AccountTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kAccountCellIdentifier];
            }
            cell.accountNameLabel.text = account.userDisplayName;
            NSString *accountServer = [account.server stringByReplacingOccurrencesOfString:[[NSURL URLWithString:account.server] scheme] withString:@""];
            cell.accountServerLabel.text = [accountServer stringByReplacingOccurrencesOfString:@"://" withString:@""];
            [cell.accountImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:account withSize:CGSizeMake(90, 90)]];
            cell.accessoryView = nil;
            if (account.unreadBadgeNumber > 0) {
                RoundedNumberView *badgeView = [[RoundedNumberView alloc] init];
                badgeView.important = YES;
                badgeView.number = account.unreadBadgeNumber;
                cell.accessoryView = badgeView;
            }
            return cell;
        }
            break;
        case kSettingsSectionConfiguration:
        {
            switch (indexPath.row) {
                case kConfigurationSectionVideo:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:videoConfigurationCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:videoConfigurationCellIdentifier];
                        cell.textLabel.text = NSLocalizedString(@"Video quality", nil);
                        [cell.imageView setImage:[UIImage imageNamed:@"videocall-settings"]];
                    }
                    NSString *resolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
                    cell.detailTextLabel.text = [[[NCSettingsController sharedInstance] videoSettingsModel] readableResolution:resolution];
                }
                    break;
                case kConfigurationSectionBrowser:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:browserConfigurationCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:browserConfigurationCellIdentifier];
                        cell.textLabel.text = NSLocalizedString(@"Open links in", nil);
                        cell.imageView.contentMode = UIViewContentModeCenter;
                        [cell.imageView setImage:[UIImage imageNamed:@"browser-settings"]];
                    }
                    cell.detailTextLabel.text = [[NCSettingsController sharedInstance] defaultBrowser];
                }
                    break;
            }
        }
            break;

        case kSettingsSectionLock:
        {
            switch (indexPath.row) {
                case kLockSectionOn:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:lockOnCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:lockOnCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Lock screen", nil);

                    if ([[[NCSettingsController sharedInstance] lockScreenPasscode] length] > 0) {
                        cell.imageView.image  = [UIImage imageNamed:@"password-settings"];
                        cell.detailTextLabel.text = NSLocalizedString(@"On", nil);
                    }
                    else {
                        cell.imageView.image  = [UIImage imageNamed:@"no-password-settings"];
                        cell.detailTextLabel.text = NSLocalizedString(@"Off", nil);
                    }
                }
                    break;
                    case kLockSectionUseSimply:
                    {
                        cell = [tableView dequeueReusableCellWithIdentifier:lockUseSimplyCellIdentifier];
                        if (!cell) {
                            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:lockUseSimplyCellIdentifier];
                            cell.textLabel.text = NSLocalizedString(@"Password type", nil);
                            cell.imageView.image  = [UIImage imageNamed:@"key"];
                        }

                        if ([[NCSettingsController sharedInstance] lockScreenPasscodeType] == NCPasscodeTypeSimple) {
                            cell.detailTextLabel.text = NSLocalizedString(@"Simple", nil);
                        } else {
                            cell.detailTextLabel.text = NSLocalizedString(@"Strong", nil);
                        }

                    }
                        break;
            }
        }
                            
            break;
        case kSettingsSectionAbout:
        {
            switch (indexPath.row) {
                case kAboutSectionPrivacy:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:privacyCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:privacyCellIdentifier];
                        cell.textLabel.text = NSLocalizedString(@"Privacy", nil);
                        [cell.imageView setImage:[UIImage imageNamed:@"privacy"]];
                    }
                }
                    break;
                case kAboutSectionSourceCode:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:sourceCodeCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sourceCodeCellIdentifier];
                        cell.textLabel.text = NSLocalizedString(@"Get source code", nil);
                        [cell.imageView setImage:[UIImage imageNamed:@"github"]];
                    }
                }
                    break;
            }
        }
            break;
    }
    
    return cell;
}

- (void)passcodeTypeOpionPressed
{
    if ([[NCSettingsController sharedInstance].lockScreenPasscode length] != 0) {
        [self changeLockScreenPassword];
    } else {
        BOOL isPasscodeTypeSimple = ([[NCSettingsController sharedInstance] lockScreenPasscodeType] == NCPasscodeTypeSimple);
        [NCSettingsController sharedInstance].lockScreenPasscodeType = isPasscodeTypeSimple ? NCPasscodeTypeStrong : NCPasscodeTypeSimple;
        NSIndexPath *passwordTypeIP = [NSIndexPath indexPathForRow:kLockSectionUseSimply inSection:[self getSectionForSettingsSection:kSettingsSectionLock]];
        [self.tableView reloadRowsAtIndexPaths:@[passwordTypeIP] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = [self getSettingsSections];
    SettingsSection settingsSection = [[sections objectAtIndex:indexPath.section] intValue];
    switch (settingsSection) {
        case kSettingsSectionUser:
        {
            [self userProfilePressed];
        }
            break;
        case kSettingsSectionUserStatus:
        {
            [self presentUserStatusOptions];
        }
            break;
        case kSettingsSectionAccounts:
        {
            NSArray *inactiveAccounts = [[NCDatabaseManager sharedInstance] inactiveAccounts];
            TalkAccount *account = [inactiveAccounts objectAtIndex:indexPath.row];
            [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:account.accountId];
        }
            break;
        case kSettingsSectionConfiguration:
        {
            switch (indexPath.row) {
                case kConfigurationSectionVideo:
                {
                    [self presentVideoResolutionsSelector];
                }
                    break;
                case kConfigurationSectionBrowser:
                {
                    [self presentBrowserSelector];
                }
                    break;
            }
        }
            break;
        case kSettingsSectionLock:
        {
            switch(indexPath.row){
                case kLockSectionOn:{
                    [self toggleLockScreenSetting];
                }
                    break;
                case kLockSectionUseSimply:{
                    [self passcodeTypeOpionPressed];
                }
                    break;
            }
        }
            break;
        case kSettingsSectionAbout:
        {
            switch (indexPath.row) {
                case kAboutSectionPrivacy:
                {
                    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://nextcloud.com/privacy"]];
                    [self presentViewController:safariVC animated:YES completion:nil];
                }
                    break;
                case kAboutSectionSourceCode:
                {
                    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://github.com/nextcloud/talk-ios"]];
                    [self presentViewController:safariVC animated:YES completion:nil];
                }
                    break;
            }
        }
            break;
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Lock screen

- (void)passcodeViewController:(CCBKPasscode *)aViewController didFinishWithPasscode:(NSString *)aPasscode
{
    [aViewController dismissViewControllerAnimated:YES completion:nil];
    
    switch (aViewController.type) {
        case BKPasscodeViewControllerNewPasscodeType:
        {
            // Store new passcode
            [NCSettingsController sharedInstance].lockScreenPasscode = aPasscode;
        }
            break;
        case BKPasscodeViewControllerCheckPasscodeType:
        {
            // Disable lock screen
            if (aViewController.fromType == CCBKPasscodeFromSettingsPasscode) {
                [NCSettingsController sharedInstance].lockScreenPasscode = nil;
            }
            // Change passcode type
            if (aViewController.fromType == CCBKPasscodeFromSimply) {
                // Remove passcode
                [NCSettingsController sharedInstance].lockScreenPasscode = nil;
                
                // Set new passcode type
                BOOL isPasscodeTypeSimple = ([[NCSettingsController sharedInstance] lockScreenPasscodeType] == NCPasscodeTypeSimple);
                [NCSettingsController sharedInstance].lockScreenPasscodeType = isPasscodeTypeSimple ? NCPasscodeTypeStrong : NCPasscodeTypeSimple;

                // Start setting new passcode
                [self toggleLockScreenSetting];
            }
        }
            break;
        default:
            break;
    }
    
    [self.tableView reloadData];
    
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController authenticatePasscode:(NSString *)aPasscode resultHandler:(void (^)(BOOL))aResultHandler
{
    if ([aPasscode isEqualToString:[NCSettingsController sharedInstance].lockScreenPasscode]) {
        aResultHandler(YES);
    } else {
        aResultHandler(NO);
    }
}

- (void)passcodeViewCloseButtonPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)changeLockScreenPassword
{
    CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
    viewController.delegate = self;
    viewController.type = BKPasscodeViewControllerCheckPasscodeType;
    viewController.fromType = CCBKPasscodeFromSimply;
    viewController.title = NSLocalizedString(@"Change password type", nil);
    
    if ([NCSettingsController sharedInstance].lockScreenPasscodeType == NCPasscodeTypeSimple) {
        viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
        viewController.passcodeInputView.maximumLength = 6;
    } else {
        viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
        viewController.passcodeInputView.maximumLength = 64;
    }
    
    BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:@"com.nextcloud.Talk"];
    touchIDManager.promptText = NSLocalizedString(@"Scan fingerprint to authenticate", nil);
    viewController.touchIDManager = touchIDManager;
    
    viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)toggleLockScreenSetting
{
    if ([[NCSettingsController sharedInstance].lockScreenPasscode length] == 0) {
        // Enable lock screen
        CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
        viewController.delegate = self;
        viewController.type = BKPasscodeViewControllerNewPasscodeType;
        viewController.fromType = CCBKPasscodeFromSettingsPasscode;
        
        if ([NCSettingsController sharedInstance].lockScreenPasscodeType == NCPasscodeTypeSimple) {
            viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 6;
        } else {
            viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 64;
        }
        
        BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:@"com.nextcloud.Talk"];
        touchIDManager.promptText = NSLocalizedString(@"Scan fingerprint to authenticate", nil);
        viewController.touchIDManager = touchIDManager;

        viewController.title = NSLocalizedString(@"Activating lock screen", nil);
        
        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
        
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];

    } else {
        // Disable lock screen
        CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
        viewController.delegate = self;
        viewController.type = BKPasscodeViewControllerCheckPasscodeType;
        viewController.fromType = CCBKPasscodeFromSettingsPasscode;

        if ([NCSettingsController sharedInstance].lockScreenPasscodeType == NCPasscodeTypeSimple) {
            viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 6;
        } else {
            viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 64;
        }

        BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:@"com.nextcloud.Talk"];
        touchIDManager.promptText = NSLocalizedString(@"Scan fingerprint to authenticate", nil);
        viewController.touchIDManager = touchIDManager;

        viewController.title = NSLocalizedString(@"Removing lock screen", nil);

        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];

        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

@end
