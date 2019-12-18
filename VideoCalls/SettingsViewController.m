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
#import "NCConnectionController.h"
#import "OpenInFirefoxControllerObjC.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "CCBKPasscode.h"
#import <SafariServices/SafariServices.h>

typedef enum SettingsSection {
    kSettingsSectionUser = 0,
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

@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = @"Profile";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
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
    // Accounts section
    if (multiAccountEnabled) {
        [sections addObject:[NSNumber numberWithInt:kSettingsSectionAccounts]];
    }
    // Configuration section
    [sections addObject:[NSNumber numberWithInt:kSettingsSectionConfiguration]];
    // Lock section
    [sections addObject:[NSNumber numberWithInt:kSettingsSectionLock]];
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
    
    NSString *actionTitle = (multiAccountEnabled) ? @"Remove account" : @"Log out";
    UIImage *actionImage = (multiAccountEnabled) ? [UIImage imageNamed:@"delete-action"] : [UIImage imageNamed:@"logout"];
    
    UIAlertAction *logOutAction = [UIAlertAction actionWithTitle:actionTitle
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^void (UIAlertAction *action) {
                                                       [self logout];
                                                   }];
    [logOutAction setValue:[actionImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:logOutAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:kSettingsSectionUser]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:^{
        [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:kSettingsSectionUser] animated:YES];
    }];
}

- (void)logout
{
    [[NCSettingsController sharedInstance] logoutWithCompletionBlock:^(NSError *error) {
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
        [[NCConnectionController sharedInstance] checkAppState];
    }];
}

#pragma mark - Configuration

- (void)presentVideoResolutionsSelector
{
    NSIndexPath *videoConfIndexPath = [NSIndexPath indexPathForRow:kConfigurationSectionVideo inSection:kSettingsSectionConfiguration];
    NSArray *videoResolutions = [[[NCSettingsController sharedInstance] videoSettingsModel] availableVideoResolutions];
    NSString *storedResolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:@"Video quality"
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
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:videoConfIndexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)presentBrowserSelector
{
    NSIndexPath *browserConfIndexPath = [NSIndexPath indexPathForRow:kConfigurationSectionBrowser inSection:kSettingsSectionConfiguration];
    NSArray *supportedBrowsers = [[NCSettingsController sharedInstance] supportedBrowsers];
    NSString *defaultBrowser = [[NCSettingsController sharedInstance] defaultBrowser];
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:@"Open links in"
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
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
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
            return [[NCDatabaseManager sharedInstance] nonActiveAccounts].count + 1;
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
        case kSettingsSectionAccounts:
            return @"Accounts";
            break;
            
        case kSettingsSectionConfiguration:
            return @"Configuration";
            break;
            
        case kSettingsSectionLock:
            return @"Lock";
            break;

        case kSettingsSectionAbout:
            return @"About";
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
        NSString *copyright = @"© 2019 Nextcloud GmbH";
        return [NSString stringWithFormat:@"%@ %@ %@", appName, appVersion, copyright];
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *addAccountCellIdentifier = @"AddAccountCellIdentifier";
    static NSString *videoConfigurationCellIdentifier = @"VideoConfigurationCellIdentifier";
    static NSString *browserConfigurationCellIdentifier = @"BrowserConfigurationCellIdentifier";
    static NSString *privacyCellIdentifier = @"PrivacyCellIdentifier";
    static NSString *sourceCodeCellIdentifier = @"SourceCodeCellIdentifier";
    static NSString *lockOnCellIdentifier = @"LockOnCellIdentifier";
    static NSString *lockUseSimplyCellIdentifier = @"LockUseSimplyCellIdentifier";
    
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
            cell.serverAddressLabel.text = activeAccount.server;
            [cell.userImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:activeAccount withSize:CGSizeMake(160, 160)]];
            return cell;
        }
            break;
        case kSettingsSectionAccounts:
        {
            RLMResults *nonActiveAccount = [[NCDatabaseManager sharedInstance] nonActiveAccounts];
            if (indexPath.row < nonActiveAccount.count) {
                TalkAccount *account = [nonActiveAccount objectAtIndex:indexPath.row];
                AccountTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAccountCellIdentifier];
                if (!cell) {
                    cell = [[AccountTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kAccountCellIdentifier];
                }
                cell.textLabel.text = account.userDisplayName;
                [cell.accountImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:account withSize:CGSizeMake(90, 90)]];
                return cell;
            } else {
                cell = [tableView dequeueReusableCellWithIdentifier:addAccountCellIdentifier];
                if (!cell) {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:addAccountCellIdentifier];
                    cell.textLabel.text = @"Add account";
                    [cell.imageView setImage:[UIImage imageNamed:@"add-settings"]];
                }
            }
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
                        cell.textLabel.text = @"Video quality";
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
                        cell.textLabel.text = @"Open links in";
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
                    
                    cell.textLabel.text = @"Lock screen";

                    if ([[[NCSettingsController sharedInstance] lockScreenPasscode] length] > 0) {
                        cell.imageView.image  = [UIImage imageNamed:@"password-settings"];
                        cell.detailTextLabel.text = @"On";
                    }
                    else {
                        cell.imageView.image  = [UIImage imageNamed:@"no-password-settings"];
                        cell.detailTextLabel.text = @"Off";
                    }
                }
                    break;
                    case kLockSectionUseSimply:
                    {
                        cell = [tableView dequeueReusableCellWithIdentifier:lockUseSimplyCellIdentifier];
                        if (!cell) {
                            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:lockUseSimplyCellIdentifier];
                            cell.textLabel.text = @"Password type";
                            cell.imageView.image  = [UIImage imageNamed:@"key"];
                        }

                        if ([[NCSettingsController sharedInstance] lockScreenPasscodeType] == NCPasscodeTypeSimple) {
                            cell.detailTextLabel.text = @"Simple";
                        } else {
                            cell.detailTextLabel.text = @"Strong";
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
                        cell.textLabel.text = @"Privacy";
                        [cell.imageView setImage:[UIImage imageNamed:@"privacy"]];
                    }
                }
                    break;
                case kAboutSectionSourceCode:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:sourceCodeCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sourceCodeCellIdentifier];
                        cell.textLabel.text = @"Get source code";
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
        case kSettingsSectionAccounts:
        {
            RLMResults *nonActiveAccount = [[NCDatabaseManager sharedInstance] nonActiveAccounts];
            if (indexPath.row < nonActiveAccount.count) {
                TalkAccount *account = [nonActiveAccount objectAtIndex:indexPath.row];
                [[NCSettingsController sharedInstance] setAccountActive:account.accountId];
                
            } else {
                [self dismissViewControllerAnimated:true completion:^{
                    [[NCUserInterfaceController sharedInstance] presentLoginViewController];
                }];
            }
            
            [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        }
            break;
        case kSettingsSectionConfiguration:
        {
            switch (indexPath.row) {
                case kConfigurationSectionVideo:
                {
                    [self presentVideoResolutionsSelector];
                    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                }
                    break;
                case kConfigurationSectionBrowser:
                {
                    [self presentBrowserSelector];
                    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
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
                    [self presentViewController:safariVC animated:YES completion:^{
                        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                    }];
                }
                    break;
                case kAboutSectionSourceCode:
                {
                    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://github.com/nextcloud/talk-ios"]];
                    [self presentViewController:safariVC animated:YES completion:^{
                        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                    }];
                }
                    break;
            }
        }
            break;
    }
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
        touchIDManager.promptText = @"Scan fingerprint to authenticate";
        viewController.touchIDManager = touchIDManager;

        viewController.title = @"Activating lock screen";
        
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
        touchIDManager.promptText = @"Scan fingerprint to authenticate";
        viewController.touchIDManager = touchIDManager;

        viewController.title = @"Removing lock screen";

        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];

        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

@end
