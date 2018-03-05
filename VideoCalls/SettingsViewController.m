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
#import "UIImageView+AFNetworking.h"
#import <SafariServices/SafariServices.h>

typedef enum SettingsSection {
    kSettingsSectionUser = 0,
    kSettingsSectionAbout,
    kSettingsSectionNumber
} SettingsSection;

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
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    _server = [[NCSettingsController sharedInstance] ncServer];
    _user = [[NCSettingsController sharedInstance] ncUser];
    
    [self refreshUserProfile];
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

#pragma mark - Profile actions

- (void)userProfilePressed
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Log out"
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^void (UIAlertAction *action) {
                                                             [self logout];
                                                         }]];
    
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
    if ([[NCSettingsController sharedInstance] ncDeviceIdentifier]) {
        [[NCAPIController sharedInstance] unsubscribeToNextcloudServer:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from NC server!!!");
            } else {
                NSLog(@"Error while unsubscribing from NC server.");
            }
        }];
        [[NCAPIController sharedInstance] unsubscribeToPushServer:^(NSError *error) {
            if (!error) {
                NSLog(@"Unsubscribed from Push Notification server!!!");
            } else {
                NSLog(@"Error while unsubscribing from Push Notification server.");
            }
        }];
    }
    
    [[NCSettingsController sharedInstance] cleanUserAndServerStoredValues];
    [self.tabBarController setSelectedIndex:0];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kSettingsSectionNumber;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kSettingsSectionAbout) {
        return kAboutSectionNumber;
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
    if (section == kSettingsSectionAbout) {
        return @"About";
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
    static NSString *privacyCellIdentifier = @"PrivacyCellIdentifier";
    static NSString *sourceCodeCellIdentifier = @"SourceCodeCellIdentifier";
    
    switch (indexPath.section) {
        case kSettingsSectionUser:
        {
            UserSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUserSettingsCellIdentifier];
            if (!cell) {
                cell = [[UserSettingsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kUserSettingsCellIdentifier];
            }
            
            cell.userDisplayNameLabel.text = [NCSettingsController sharedInstance].ncUserDisplayName;
            cell.serverAddressLabel.text = _server;
            [cell.userImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:[NCSettingsController sharedInstance].ncUserId andSize:160]
                                     placeholderImage:nil
                                              success:nil
                                              failure:nil];
            cell.userImageView.layer.cornerRadius = 40.0;
            cell.userImageView.layer.masksToBounds = YES;
            return cell;
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
                    }
                }
                    break;
                case kAboutSectionSourceCode:
                {
                    cell = [tableView dequeueReusableCellWithIdentifier:sourceCodeCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sourceCodeCellIdentifier];
                        cell.textLabel.text = @"Get source code";
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
