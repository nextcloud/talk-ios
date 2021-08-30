//
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

#import "UserStatusTableViewController.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"

typedef enum UserStatusSection {
    kUserStatusSectionOnlineStatus = 0,
    kUserStatusSectionStatusMessage,
    kUserStatusSectionCount
} UserStatusSection;

@interface UserStatusTableViewController ()
{
    NCUserStatus *_userStatus;
}
@end

@implementation UserStatusTableViewController

- (instancetype)initWithUserStatus:(NCUserStatus *)userStatus
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _userStatus = userStatus;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.translucent = NO;
    
    self.navigationItem.title = NSLocalizedString(@"Status", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
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
    userStatusActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:kUserStatusSectionOnlineStatus]];
    
    [self presentViewController:userStatusActionSheet animated:YES completion:nil];
}

- (void)setActiveUserStatus:(NSString *)userStatus
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] setUserStatus:userStatus forAccount:activeAccount withCompletionBlock:^(NSError *error) {
        [self getActiveUserStatus];
    }];
}

- (void)getActiveUserStatus
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getUserStatusForAccount:activeAccount withCompletionBlock:^(NSDictionary *userStatus, NSError *error) {
        if (!error && userStatus) {
            _userStatus = [NCUserStatus userStatusWithDictionary:userStatus];
            [self.tableView reloadData];
        }
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kUserStatusSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kUserStatusSectionOnlineStatus:
            return NSLocalizedString(@"Online status", nil);
            break;
            
        case kUserStatusSectionStatusMessage:
            return NSLocalizedString(@"Status message", nil);
            break;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *kOnlineStatusCellIdentifier = @"OnlineStatusCellIdentifier";
    static NSString *kStatusMessageCellIdentifier = @"StatusMessageCellIdentifier";
    
    switch (indexPath.section) {
        case kUserStatusSectionOnlineStatus:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:kOnlineStatusCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kOnlineStatusCellIdentifier];
            }
            
            if (_userStatus) {
                cell.textLabel.text = [_userStatus readableUserStatus];
                NSString *statusImage = [_userStatus userStatusImageNameOfSize:24];
                if (statusImage) {
                    [cell.imageView setImage:[UIImage imageNamed:statusImage]];
                } else {
                    cell.imageView.image = nil;
                }
            } else {
                cell.textLabel.text = NSLocalizedString(@"Fetching status …", nil);
            }
        }
            break;
        case kUserStatusSectionStatusMessage:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:kStatusMessageCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kStatusMessageCellIdentifier];
            }
            
            cell.textLabel.text = NSLocalizedString(@"What's your status?", nil);
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kUserStatusSectionOnlineStatus:
        {
            [self presentUserStatusOptions];
        }
            break;
        case kUserStatusSectionStatusMessage:
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
