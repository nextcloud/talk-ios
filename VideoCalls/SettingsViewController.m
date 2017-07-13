//
//  SettingsViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 05.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "SettingsViewController.h"

#import "NCSettingsController.h"

typedef enum SettingsSection {
    kSettingsSectionServer = 0,
    kSettingsSectionUser,
    kSettingsSectionLogout
} SettingsSection;

@interface SettingsViewController ()
{
    NSString *_server;
    NSString *_user;
    NSArray *_settingsSections;
}

@end

@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    _server = [[NCSettingsController sharedInstance] ncServer];
    _user = [[NCSettingsController sharedInstance] ncUser];
    
    _settingsSections = @[@"Server", @"User", @"Logout"];
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
    return [_settingsSections count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [_settingsSections objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *ServerCellIdentifier = @"ServerCellIdentifier";
    static NSString *UserCellIdentifier = @"UserCellIdentifier";
    static NSString *LogoutCellIdentifier = @"LogoutCellIdentifier";
    
    switch (indexPath.section) {
        case kSettingsSectionServer:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:ServerCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ServerCellIdentifier];
                cell.textLabel.text = _server;
            }
        }
            break;
        case kSettingsSectionUser:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:UserCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:UserCellIdentifier];
                cell.textLabel.text = _user;
            }
        }
            break;
        case kSettingsSectionLogout:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:LogoutCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:LogoutCellIdentifier];
                cell.textLabel.text = @"Sign off";
            }
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSettingsSectionLogout) {
        [[NCSettingsController sharedInstance] cleanAllStoredValues];
        [self dismissViewControllerAnimated:true completion:nil];
    }
}

@end
