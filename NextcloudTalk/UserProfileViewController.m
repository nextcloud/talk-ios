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
#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "TextInputTableViewCell.h"

#define k_name_textfield_tag        99
#define k_email_textfield_tag       98
#define k_phone_textfield_tag       97
#define k_address_textfield_tag     96
#define k_website_textfield_tag     95
#define k_twitter_textfield_tag     94

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

@interface UserProfileViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate>
{
    TalkAccount *_account;
    BOOL _isEditable;
    BOOL _waitingForModification;
    UIBarButtonItem *_editButton;
    UITextField *_activeTextField;
    UIActivityIndicatorView *_modifyingProfileView;
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
    
    [self showEditButton];
    
    _modifyingProfileView = [[UIActivityIndicatorView alloc] init];
    _modifyingProfileView.color = [NCAppBranding themeTextColor];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    
    [self.tableView registerNib:[UINib nibWithNibName:kTextInputTableViewCellNibName bundle:nil] forCellReuseIdentifier:kTextInputCellIdentifier];
}

- (NSArray *)getProfileSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    if ((_account.userDisplayName && ![_account.userDisplayName isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionName]];
    }
    if ((_account.email && ![_account.email isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionEmail]];
    }
    if ((_account.phone && ![_account.phone isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionPhoneNumber]];
    }
    if ((_account.address && ![_account.address isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionAddress]];
    }
    if ((_account.website && ![_account.website isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionWebsite]];
    }
    if ((_account.twitter && ![_account.twitter isEqualToString:@""]) || _isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionTwitter]];
    }
    if (multiAccountEnabled) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionAddAccount]];
    }
    [sections addObject:[NSNumber numberWithInt:kProfileSectionRemoveAccount]];

    return [NSArray arrayWithArray:sections];
}

- (void)refreshUserProfile
{
    [[NCSettingsController sharedInstance] getUserProfileWithCompletionBlock:^(NSError *error) {
        self->_account = [[NCDatabaseManager sharedInstance] activeAccount];
        [self.tableView reloadData];
    }];
}

#pragma mark - User Interface

- (void)showEditButton
{
    _editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(editButtonPressed)];
    _editButton.accessibilityHint = NSLocalizedString(@"Double tap to edit profile", nil);
    self.navigationItem.rightBarButtonItem = _editButton;
}

- (void)showDoneButton
{
    _editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(editButtonPressed)];
    _editButton.accessibilityHint = NSLocalizedString(@"Double tap to end editing profile", nil);
    self.navigationItem.rightBarButtonItem = _editButton;
}

- (void)setModifyingProfileUI
{
    [_modifyingProfileView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_modifyingProfileView];
    self.tableView.userInteractionEnabled = NO;
}

- (void)removeModifyingProfileUI
{
    [_modifyingProfileView stopAnimating];
    if (_isEditable) {
        [self showDoneButton];
    } else {
        [self showEditButton];
    }
    self.tableView.userInteractionEnabled = YES;
}

- (void)showProfileModificationErrorForField:(NSInteger)field inTextField:(UITextField *)textField
{
    [self removeModifyingProfileUI];
    NSString *errorDescription = @"";
    // The textfield pointer might be pointing to a different textfield at this point because
    // if the user tapped the "Done" button in navigation bar (so the non-editable view is visible)
    // That's the reason why we check the field instead of textfield.tag
    switch (field) {
        case k_name_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting user name", nil);
            break;
            
        case k_email_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting email address", nil);
            break;
            
        case k_phone_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting phone number", nil);
            break;
            
        case k_address_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting address", nil);
            break;
            
        case k_website_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting website", nil);
            break;
            
        case k_twitter_textfield_tag:
            errorDescription = NSLocalizedString(@"An error occured setting twitter account", nil);
            break;
            
        default:
            break;
    }
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:errorDescription
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (self->_isEditable) {
            [textField becomeFirstResponder];
        }
    }];
    [renameDialog addAction:okAction];
    [self presentViewController:renameDialog animated:YES completion:nil];
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    // Allow click on tableview cells
    if ([touch.view isDescendantOfView:self.tableView]) {
        if (![touch.view isKindOfClass:[UITextField class]]) {
            [self dismissKeyboard];
        }
        return NO;
    }
    return YES;
}

#pragma mark - UITextField delegate

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    _activeTextField = textField;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    NSString *field = nil;
    NSString *currentValue = nil;
    NSString *newValue = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSInteger tag = textField.tag;
        
    if (tag == k_name_textfield_tag) {
        field = kUserProfileDisplayName;
        currentValue = _account.userDisplayName;
    } else if (tag == k_email_textfield_tag) {
        field = kUserProfileEmail;
        currentValue = _account.email;
    } else if (tag == k_phone_textfield_tag) {
        field = kUserProfilePhone;
        currentValue = _account.phone;
    } else if (tag == k_address_textfield_tag) {
        field = kUserProfileAddress;
        currentValue = _account.address;
    } else if (tag == k_website_textfield_tag) {
        field = kUserProfileWebsite;
        currentValue = _account.website;
    } else if (tag == k_twitter_textfield_tag) {
        field = kUserProfileTwitter;
        currentValue = _account.twitter;
    }
    
    BOOL waitForModitication = _waitingForModification;
    _waitingForModification = NO;
    _activeTextField = nil;
    
    textField.text = newValue;
    
    [self setModifyingProfileUI];
    
    if (![newValue isEqualToString:currentValue]) {
        [[NCAPIController sharedInstance] setUserProfileField:field withValue:newValue forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
            if (error) {
                [self showProfileModificationErrorForField:tag inTextField:textField];
            } else {
                if (waitForModitication) {
                    [self editButtonPressed];
                }
                [self refreshUserProfile];
            }
            
            [self removeModifyingProfileUI];
        }];
    } else {
        if (waitForModitication) {
            [self editButtonPressed];
        }
        [self removeModifyingProfileUI];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (void)dismissKeyboard
{
    [_activeTextField resignFirstResponder];
}

#pragma mark - Actions

- (void)editButtonPressed
{
    if (_activeTextField) {
        [self dismissKeyboard];
        _waitingForModification = YES;
        return;
    }
    
    if (!_isEditable) {
        _isEditable = YES;
        [self showDoneButton];
    } else {
        _isEditable = NO;
        [self showEditButton];
    }
    
    [self.tableView reloadData];
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
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    switch (profileSection) {
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
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    if (profileSection == kProfileSectionEmail) {
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
    textInputCell.textField.delegate = self;
    textInputCell.textField.userInteractionEnabled = _isEditable;
    
    NSArray *sections = [self getProfileSections];
    ProfileSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kProfileSectionName:
        {
            textInputCell.textField.text = _account.userDisplayName;
            textInputCell.textField.tag = k_name_textfield_tag;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionEmail:
        {
            textInputCell.textField.text = _account.email;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your email address", nil);
            textInputCell.textField.tag = k_email_textfield_tag;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionPhoneNumber:
        {
            textInputCell.textField.text = _account.phone;
            textInputCell.textField.keyboardType = UIKeyboardTypePhonePad;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your phone number", nil);
            textInputCell.textField.tag = k_phone_textfield_tag;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionAddress:
        {
            textInputCell.textField.text = _account.address;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your postal address", nil);
            textInputCell.textField.tag = k_address_textfield_tag;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionWebsite:
        {
            textInputCell.textField.text = _account.website;
            textInputCell.textField.placeholder = NSLocalizedString(@"Link https://…", nil);
            textInputCell.textField.tag = k_website_textfield_tag;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionTwitter:
        {
            textInputCell.textField.text = _account.twitter;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Twitter handle @…", nil);
            textInputCell.textField.tag = k_twitter_textfield_tag;
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
    NSArray *sections = [self getProfileSections];
    ProfileSection section = [[sections objectAtIndex:indexPath.section] intValue];
    if (section == kProfileSectionAddAccount) {
        [self addNewAccount];
    } else if (section == kProfileSectionRemoveAccount) {
        [self showLogoutConfirmationDialog];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
