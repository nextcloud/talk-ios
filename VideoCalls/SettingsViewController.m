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

typedef enum SettingsSection {
    kSettingsSectionUser = 0,
    kSettingsSectionLogout,
    kSettingsSectionNumber
} SettingsSection;

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

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSettingsSectionNumber;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kSettingsSectionUser) {
        return 100;
    }
    
    return 48;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *LogoutCellIdentifier = @"LogoutCellIdentifier";
    
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
        case kSettingsSectionLogout:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:LogoutCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:LogoutCellIdentifier];
                cell.textLabel.text = @"Log out";
                cell.textLabel.textColor = [UIColor redColor];
                [cell.imageView setImage:[UIImage imageNamed:@"logout"]];
            }
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSettingsSectionLogout) {
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
}

@end
