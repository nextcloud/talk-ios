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

#import "DetailedOptionsSelectorTableViewController.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCNavigationController.h"
#import "NextcloudTalk-Swift.h"

typedef enum UserStatusSection {
    kUserStatusSectionOnlineStatus = 0,
    kUserStatusSectionStatusMessage,
    kUserStatusSectionCount
} UserStatusSection;

@interface UserStatusTableViewController () <DetailedOptionsSelectorTableViewControllerDelegate, UserStatusMessageViewControllerDelegate>
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
    NSMutableArray *options = [NSMutableArray new];
    
    DetailedOption *onlineOption = [[DetailedOption alloc] init];
    onlineOption.identifier = kUserStatusOnline;
    onlineOption.image = [[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusOnline ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    onlineOption.title = [NCUserStatus readableUserStatusFromUserStatus:kUserStatusOnline];
    onlineOption.selected = [_userStatus.status isEqualToString:kUserStatusOnline];
    
    DetailedOption *awayOption = [[DetailedOption alloc] init];
    awayOption.identifier = kUserStatusAway;
    awayOption.image = [[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusAway ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    awayOption.title = [NCUserStatus readableUserStatusFromUserStatus:kUserStatusAway];
    awayOption.selected = [_userStatus.status isEqualToString:kUserStatusAway];
    
    DetailedOption *dndOption = [[DetailedOption alloc] init];
    dndOption.identifier = kUserStatusDND;
    dndOption.image = [[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusDND ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    dndOption.title = [NCUserStatus readableUserStatusFromUserStatus:kUserStatusDND];
    dndOption.subtitle = NSLocalizedString(@"Mute all notifications", nil);
    dndOption.selected = [_userStatus.status isEqualToString:kUserStatusDND];
    
    DetailedOption *invisibleOption = [[DetailedOption alloc] init];
    invisibleOption.identifier = kUserStatusInvisible;
    invisibleOption.image = [[UIImage imageNamed:[NCUserStatus userStatusImageNameForStatus:kUserStatusInvisible ofSize:24]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    invisibleOption.title = [NCUserStatus readableUserStatusFromUserStatus:kUserStatusInvisible];
    invisibleOption.subtitle = NSLocalizedString(@"Appear offline", nil);
    invisibleOption.selected = [_userStatus.status isEqualToString:kUserStatusInvisible];
    
    [options addObject:onlineOption];
    [options addObject:awayOption];
    [options addObject:dndOption];
    [options addObject:invisibleOption];
    
    DetailedOptionsSelectorTableViewController *optionSelectorVC = [[DetailedOptionsSelectorTableViewController alloc] initWithOptions:options forSenderIdentifier:nil andTitle:NSLocalizedString(@"Online status", nil)];
    optionSelectorVC.delegate = self;
    NCNavigationController *optionSelectorNC = [[NCNavigationController alloc] initWithRootViewController:optionSelectorVC];
    [self presentViewController:optionSelectorNC animated:YES completion:nil];
}

- (void)presentUserStatusMessageOptions
{
    UserStatusMessageViewController *userStatusMessageVC = [[UserStatusMessageViewController alloc] initWithUserStatus:_userStatus];
    userStatusMessageVC.delegate = self;
    NCNavigationController *userStatusMessageNC = [[NCNavigationController alloc] initWithRootViewController:userStatusMessageVC];
    [self presentViewController:userStatusMessageNC animated:YES completion:nil];
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

#pragma mark - DetailedOptionSelector Delegate

- (void)detailedOptionsSelector:(DetailedOptionsSelectorTableViewController *)viewController didSelectOptionWithIdentifier:(DetailedOption *)option
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (!option.selected) {
            [self setActiveUserStatus:option.identifier];
        }
    }];
}

- (void)detailedOptionsSelectorWasCancelled:(DetailedOptionsSelectorTableViewController *)viewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UserStatusMessageViewController Delegate

- (void)didClearStatusMessage
{
    _userStatus.icon = @"";
    _userStatus.message = @"";
    _userStatus.clearAt = 0;
    [self.tableView reloadData];
}

- (void)didSetStatusMessageWithIcon:(NSString *)icon message:(NSString *)message clearAt:(NSDate *)clearAt
{
    _userStatus.icon = icon;
    _userStatus.message = message;
    _userStatus.clearAt = clearAt.timeIntervalSince1970;
    [self.tableView reloadData];
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
            
            NSString *statusMessge = [_userStatus readableUserStatusMessage];
            if (statusMessge) {
                cell.textLabel.text = statusMessge;
            } else {
                cell.textLabel.text = NSLocalizedString(@"What's your status?", nil);
            }
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
        {
            [self presentUserStatusMessageOptions];
        }
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
