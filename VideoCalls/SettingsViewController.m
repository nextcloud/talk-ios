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
#import "UserSettingsTableViewCell.h"
#import "NCAPIController.h"
#import "NCUserInterfaceController.h"
#import "NCConnectionController.h"
#import "OpenInFirefoxControllerObjC.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import <SafariServices/SafariServices.h>

typedef enum SettingsSection {
    kSettingsSectionUser = 0,
    kSettingsSectionConfiguration,
    kSettingsSectionAbout,
    kSettingsSectionNumber
} SettingsSection;

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
    NSString *_server;
    NSString *_user;
}

@end

@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [self.tableView registerNib:[UINib nibWithNibName:kUserSettingsTableCellNibName bundle:nil] forCellReuseIdentifier:kUserSettingsCellIdentifier];
    
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
    
    _server = [[NCSettingsController sharedInstance] ncServer];
    _user = [[NCSettingsController sharedInstance] ncUser];
    
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController sharedInstance].connectionState];
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
            [self refreshUserProfile];
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

#pragma mark - Profile actions

- (void)userProfilePressed
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *logOutAction = [UIAlertAction actionWithTitle:@"Log out"
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^void (UIAlertAction *action) {
                                                       [self logout];
                                                   }];
    [logOutAction setValue:[[UIImage imageNamed:@"logout"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
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
        [[NCUserInterfaceController sharedInstance] presentConversationsViewController];
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
    return kSettingsSectionNumber;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kSettingsSectionConfiguration:
        {
            NSUInteger numberOfSupportedBrowsers = [NCSettingsController sharedInstance].supportedBrowsers.count;
            return (numberOfSupportedBrowsers > 1) ? kConfigurationSectionNumber : kConfigurationSectionNumber - 1;
        }
            break;

        case kSettingsSectionAbout:
            return kAboutSectionNumber;
            break;
    }
    
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kSettingsSectionUser) {
        return 100;
    }
    
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kSettingsSectionConfiguration:
            return @"Configuration";
            break;

        case kSettingsSectionAbout:
            return @"About";
            break;
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == kSettingsSectionAbout) {
        NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
        NSString *copyright = @"© 2018 Nextcloud GmbH";
        return [NSString stringWithFormat:@"%@ %@ %@", appName, appVersion, copyright];
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *videoConfigurationCellIdentifier = @"VideoConfigurationCellIdentifier";
    static NSString *browserConfigurationCellIdentifier = @"BrowserConfigurationCellIdentifier";
    static NSString *privacyCellIdentifier = @"PrivacyCellIdentifier";
    static NSString *sourceCodeCellIdentifier = @"SourceCodeCellIdentifier";
    
    switch (indexPath.section) {
        case kSettingsSectionUser:
        {
            UserSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUserSettingsCellIdentifier];
            if (!cell) {
                cell = [[UserSettingsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kUserSettingsCellIdentifier];
            }
            
            cell.serverAddressLabel.text = _server;
            
            if ([NCConnectionController sharedInstance].appState == kAppStateReady) {
                cell.userDisplayNameLabel.text = [NCSettingsController sharedInstance].ncUserDisplayName;
                // Create avatar for display name
                [cell.userImageView setImageWithString:[NCSettingsController sharedInstance].ncUserDisplayName color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.userImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:[NCSettingsController sharedInstance].ncUserId andSize:160]
                                          placeholderImage:nil success:nil failure:nil];
                cell.userImageView.layer.cornerRadius = 40.0;
                cell.userImageView.layer.masksToBounds = YES;
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kSettingsSectionUser:
        {
            [self userProfilePressed];
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

@end
