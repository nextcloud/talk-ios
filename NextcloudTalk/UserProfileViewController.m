/**
 * @copyright Copyright (c) 2021 Ivan Sein <ivan@nextcloud.com>
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

#import "UserProfileViewController.h"

#import "NCAppBranding.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "TextInputTableViewCell.h"

typedef enum ProfileSection {
    kProfileSectionName = 0,
    kProfileSectionEmail,
    kProfileSectionPhoneNumber,
    kProfileSectionAddress,
    kProfileSectionWebsite,
    kProfileSectionTwitter,
    kProfileSectionAddAccount,
    kProfileSectionRemoveAccount
} ProfileSection;

@interface UserProfileViewController ()
{
    TalkAccount *_account;
    BOOL _isEditable;
}

@end

@implementation UserProfileViewController

- (instancetype)initWithAccount:(TalkAccount *)account
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    _account = account;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Profile", nil);
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
    
    [self.tableView registerNib:[UINib nibWithNibName:kTextInputTableViewCellNibName bundle:nil] forCellReuseIdentifier:kTextInputCellIdentifier];
}

- (NSArray *)getProfileSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionName]];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionEmail]];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionPhoneNumber]];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionAddress]];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionWebsite]];
    [sections addObject:[NSNumber numberWithInt:kProfileSectionTwitter]];
    if (multiAccountEnabled) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionAddAccount]];
    }
    [sections addObject:[NSNumber numberWithInt:kProfileSectionRemoveAccount]];

    return [NSArray arrayWithArray:sections];
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

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getProfileSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kProfileSectionName:
            return NSLocalizedString(@"Full name", nil);
            break;
            
        case kProfileSectionEmail:
            return NSLocalizedString(@"Email", nil);
            break;
            
        case kProfileSectionPhoneNumber:
            return NSLocalizedString(@"Phone number", nil);
            break;
            
        case kProfileSectionAddress:
            return NSLocalizedString(@"Address", nil);
            break;
            
        case kProfileSectionWebsite:
            return NSLocalizedString(@"Website", nil);
            break;
            
        case kProfileSectionTwitter:
            return NSLocalizedString(@"Twitter", nil);
            break;
            
        default:
            break;
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == kProfileSectionEmail) {
        return NSLocalizedString(@"For password reset and notifications", nil);;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *addAccountCellIdentifier = @"AddAccountCellIdentifier";
    static NSString *removeAccountCellIdentifier = @"RemoveAccountCellIdentifier";
    
    UITableViewCell *cell = nil;
    
    TextInputTableViewCell *textInputCell = [tableView dequeueReusableCellWithIdentifier:kTextInputCellIdentifier];
    if (!textInputCell) {
        textInputCell = [[TextInputTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kTextInputCellIdentifier];
    }
    textInputCell.textField.userInteractionEnabled = _isEditable;
    
    NSArray *sections = [self getProfileSections];
    ProfileSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kProfileSectionName:
        {
            textInputCell.textField.text = _account.userDisplayName;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionEmail:
        {
            textInputCell.textField.text = _account.email;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your email address", nil);
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionPhoneNumber:
        {
            textInputCell.textField.text = _account.phone;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your phone number", nil);
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionAddress:
        {
            textInputCell.textField.text = _account.address;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your postal address", nil);
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionWebsite:
        {
            textInputCell.textField.text = _account.website;
            textInputCell.textField.placeholder = NSLocalizedString(@"Link https://…", nil);
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionTwitter:
        {
            textInputCell.textField.text = _account.twitter;
            textInputCell.textField.placeholder = NSLocalizedString(@"Twitter handle @…", nil);
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionAddAccount:
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:addAccountCellIdentifier];
            cell.textLabel.text = NSLocalizedString(@"Add account", nil);
            cell.textLabel.textColor = [UIColor systemBlueColor];
            [cell.imageView setImage:[[UIImage imageNamed:@"add-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            [cell.imageView setTintColor:[UIColor systemBlueColor]];
        }
            break;
            
        case kProfileSectionRemoveAccount:
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:removeAccountCellIdentifier];
            NSString *actionTitle = (multiAccountEnabled) ? NSLocalizedString(@"Remove account", nil) : NSLocalizedString(@"Log out", nil);
            UIImage *actionImage = (multiAccountEnabled) ? [UIImage imageNamed:@"delete-action"] : [UIImage imageNamed:@"logout"];
            cell.textLabel.text = actionTitle;
            cell.textLabel.textColor = [UIColor systemRedColor];
            [cell.imageView setImage:[actionImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            [cell.imageView setTintColor:[UIColor systemRedColor]];
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kProfileSectionAddAccount) {
        [self addNewAccount];
    } else if (indexPath.section == kProfileSectionRemoveAccount) {
        [self showLogoutConfirmationDialog];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
