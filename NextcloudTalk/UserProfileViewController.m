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

#import <AVFoundation/AVFoundation.h>
#import <TOCropViewController/TOCropViewController.h>

#import "AvatarHeaderView.h"
#import "DetailedOptionsSelectorTableViewController.h"
#import "HeaderWithButton.h"
#import "NBPhoneNumberUtil.h"
#import "NCAppBranding.h"
#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCNavigationController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "TextInputTableViewCell.h"

#define k_name_textfield_tag        99
#define k_email_textfield_tag       98
#define k_phone_textfield_tag       97
#define k_address_textfield_tag     96
#define k_website_textfield_tag     95
#define k_twitter_textfield_tag     94
#define k_avatar_scope_button_tag   93

typedef enum ProfileSection {
    kProfileSectionName = 0,
    kProfileSectionEmail,
    kProfileSectionPhoneNumber,
    kProfileSectionAddress,
    kProfileSectionWebsite,
    kProfileSectionTwitter,
    kProfileSectionSummary,
    kProfileSectionAddAccount,
    kProfileSectionRemoveAccount
} ProfileSection;

typedef enum SummaryRow {
    kSummaryRowEmail = 0,
    kSummaryRowPhoneNumber,
    kSummaryRowAddress,
    kSummaryRowWebsite,
    kSummaryRowTwitter
} SummaryRow;

@interface UserProfileViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, TOCropViewControllerDelegate, DetailedOptionsSelectorTableViewControllerDelegate>
{
    TalkAccount *_account;
    BOOL _isEditable;
    BOOL _waitingForModification;
    UIBarButtonItem *_editButton;
    UITextField *_activeTextField;
    UIActivityIndicatorView *_modifyingProfileView;
    UIButton *_editAvatarButton;
    UIImagePickerController *_imagePicker;
    UIAlertAction *_setPhoneAction;
    NBPhoneNumberUtil *_phoneUtil;
    NSArray *_editableFields;
    BOOL _showScopes;
}

@end

@implementation UserProfileViewController

- (instancetype)initWithAccount:(TalkAccount *)account
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    _account = account;
    _phoneUtil = [[NBPhoneNumberUtil alloc] init];
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
    
    self.tableView.tableHeaderView = [self avatarHeaderView];
    
    [self showEditButton];
    [self getUserProfileEditableFields];
    
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:_account.accountId];
    if (serverCapabilities) {
       _showScopes = serverCapabilities.accountPropertyScopesVersion2;
    }
    
    _modifyingProfileView = [[UIActivityIndicatorView alloc] init];
    _modifyingProfileView.color = [NCAppBranding themeTextColor];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    
    [self.tableView registerNib:[UINib nibWithNibName:kTextInputTableViewCellNibName bundle:nil] forCellReuseIdentifier:kTextInputCellIdentifier];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userProfileImageUpdated:) name:NCUserProfileImageUpdatedNotification object:nil];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    // Workaround to fix name label width
    AvatarHeaderView *headerView = (AvatarHeaderView *)self.tableView.tableHeaderView;
    CGRect labelFrame = headerView.nameLabel.frame;
    CGFloat padding = 16;
    labelFrame.origin.x = padding;
    labelFrame.size.width = self.tableView.bounds.size.width - padding * 2;
    headerView.nameLabel.frame = labelFrame;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray *)getProfileSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    
    if (_isEditable) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionName]];
        [sections addObject:[NSNumber numberWithInt:kProfileSectionEmail]];
        [sections addObject:[NSNumber numberWithInt:kProfileSectionPhoneNumber]];
        [sections addObject:[NSNumber numberWithInt:kProfileSectionAddress]];
        [sections addObject:[NSNumber numberWithInt:kProfileSectionWebsite]];
        [sections addObject:[NSNumber numberWithInt:kProfileSectionTwitter]];
    } else if ([self rowsInSummarySection].count > 0){
        [sections addObject:[NSNumber numberWithInt:kProfileSectionSummary]];
    }
    
    if (multiAccountEnabled) {
        [sections addObject:[NSNumber numberWithInt:kProfileSectionAddAccount]];
    }
    
    [sections addObject:[NSNumber numberWithInt:kProfileSectionRemoveAccount]];

    return [NSArray arrayWithArray:sections];
}

- (NSArray *)rowsInSummarySection
{
    NSMutableArray *rows = [[NSMutableArray alloc] init];
    
    if ((_account.email && ![_account.email isEqualToString:@""])) {
        [rows addObject:[NSNumber numberWithInt:kSummaryRowEmail]];
    }
    if ((_account.phone && ![_account.phone isEqualToString:@""])) {
        [rows addObject:[NSNumber numberWithInt:kSummaryRowPhoneNumber]];
    }
    if ((_account.address && ![_account.address isEqualToString:@""])) {
        [rows addObject:[NSNumber numberWithInt:kSummaryRowAddress]];
    }
    if ((_account.website && ![_account.website isEqualToString:@""])) {
        [rows addObject:[NSNumber numberWithInt:kSummaryRowWebsite]];
    }
    if ((_account.twitter && ![_account.twitter isEqualToString:@""])) {
        [rows addObject:[NSNumber numberWithInt:kSummaryRowTwitter]];
    }
    
    return [NSArray arrayWithArray:rows];
}

- (void)getUserProfileEditableFields
{
    _editButton.enabled = NO;
    [[NCAPIController sharedInstance] getUserProfileEditableFieldsForAccount:_account withCompletionBlock:^(NSArray *userProfileEditableFields, NSError *error) {
        if (!error) {
            self->_editableFields = userProfileEditableFields;
            self->_editButton.enabled = YES;
        }
    }];
}

- (void)refreshUserProfile
{
    [[NCSettingsController sharedInstance] getUserProfileWithCompletionBlock:^(NSError *error) {
        self->_account = [[NCDatabaseManager sharedInstance] activeAccount];
        [self refreshProfileTableView];
    }];
}

#pragma mark - Notifications

- (void)userProfileImageUpdated:(NSNotification *)notification
{
    self->_account = [[NCDatabaseManager sharedInstance] activeAccount];
    [self refreshProfileTableView];
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

- (void)refreshProfileTableView
{
    self.tableView.tableHeaderView = [self avatarHeaderView];
    [self.tableView.tableHeaderView setNeedsDisplay];
    [self.tableView reloadData];
}

- (UIView *)avatarHeaderView
{
    AvatarHeaderView *headerView = [[AvatarHeaderView alloc] init];
    headerView.frame = CGRectMake(0, 0, 200, 150);
    
    headerView.avatarImageView.layer.cornerRadius = 40.0;
    headerView.avatarImageView.layer.masksToBounds = YES;
    [headerView.avatarImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:_account withSize:CGSizeMake(160, 160)]];
    
    headerView.nameLabel.text = _account.userDisplayName;
    headerView.nameLabel.hidden = _isEditable;
    
    headerView.scopeButton.tag = k_avatar_scope_button_tag;
    [headerView.scopeButton setImage:[self imageForScope:_account.avatarScope] forState:UIControlStateNormal];
    [headerView.scopeButton addTarget:self action:@selector(showScopeSelectionDialog:) forControlEvents:UIControlEventTouchUpInside];
    headerView.scopeButton.hidden = !(_isEditable && _showScopes);
    
    headerView.editButton.hidden = !(_isEditable && [[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityTempUserAvatarAPI forAccountId:_account.accountId]);
    [headerView.editButton setTitle:NSLocalizedString(@"Edit", nil) forState:UIControlStateNormal];
    [headerView.editButton addTarget:self action:@selector(showAvatarOptions) forControlEvents:UIControlEventTouchUpInside];
    _editAvatarButton = headerView.editButton;
    
    return headerView;
}

- (void)showAvatarOptions
{
    UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                                message:nil
                                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self checkAndPresentCamera];
    }];
    [cameraAction setValue:[[UIImage imageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *photoLibraryAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photo Library", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self presentPhotoLibrary];
    }];
    [photoLibraryAction setValue:[[UIImage imageNamed:@"photos"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *removeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Remove", nil)
                                                                 style:UIAlertActionStyleDestructive
                                                               handler:^void (UIAlertAction *action) {
        [self removeUserProfileImage];
    }];
    [removeAction setValue:[[UIImage imageNamed:@"delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        [optionsActionSheet addAction:cameraAction];
    }
    [optionsActionSheet addAction:photoLibraryAction];
    if (_account.hasCustomAvatar) {
        [optionsActionSheet addAction:removeAction];
    }
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = _editAvatarButton;
    optionsActionSheet.popoverPresentationController.sourceRect = _editAvatarButton.frame;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)checkAndPresentCamera
{
    // https://stackoverflow.com/a/20464727/2512312
    NSString *mediaType = AVMediaTypeVideo;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    
    if(authStatus == AVAuthorizationStatusAuthorized) {
        [self presentCamera];
        return;
    } else if(authStatus == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            if(granted){
                [self presentCamera];
            }
        }];
        return;
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access camera", nil)
                                 message:NSLocalizedString(@"Camera access is not allowed. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

- (void)presentCamera
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_imagePicker = [[UIImagePickerController alloc] init];
        self->_imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        self->_imagePicker.delegate = self;
        [self presentViewController:self->_imagePicker animated:YES completion:nil];
    });
}

- (void)presentPhotoLibrary
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_imagePicker = [[UIImagePickerController alloc] init];
        self->_imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        self->_imagePicker.delegate = self;
        [self presentViewController:self->_imagePicker animated:YES completion:nil];
    });
}

- (void)sendUserProfileImage:(UIImage *)image
{
    [[NCAPIController sharedInstance] setUserProfileImage:image forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (!error) {
            [self refreshUserProfile];
        } else {
            [self showProfileImageError:YES];
            NSLog(@"Error sending profile image: %@", error.description);
        }
    }];
}

- (void)removeUserProfileImage
{
    [[NCAPIController sharedInstance] removeUserProfileImageForAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (!error) {
            [self refreshUserProfile];
        } else {
            [self showProfileImageError:NO];
            NSLog(@"Error removing profile image: %@", error.description);
        }
    }];
}

- (void)showProfileModificationErrorForField:(NSInteger)field inTextField:(UITextField *)textField
{
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
    
    UIAlertController *errorDialog =
    [UIAlertController alertControllerWithTitle:errorDescription
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (self->_isEditable) {
            [textField becomeFirstResponder];
        }
    }];
    [errorDialog addAction:okAction];
    [self presentViewController:errorDialog animated:YES completion:nil];
}

- (void)showProfileImageError:(BOOL)setting
{
    NSString *reason = setting ? NSLocalizedString(@"An error occured setting profile image", nil) : NSLocalizedString(@"An error occured removing profile image", nil);
    UIAlertController *errorDialog =
    [UIAlertController alertControllerWithTitle:reason
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [errorDialog addAction:okAction];
    [self presentViewController:errorDialog animated:YES completion:nil];
}

- (UIImage *)imageForScope:(NSString *)scope
{
    if ([scope isEqualToString:kUserProfileScopePrivate]) {
        return [[UIImage imageNamed:@"mobile-phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else if ([scope isEqualToString:kUserProfileScopeLocal]) {
        return [[UIImage imageNamed:@"password-settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else if ([scope isEqualToString:kUserProfileScopeFederated]) {
        return [[UIImage imageNamed:@"group"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else if ([scope isEqualToString:kUserProfileScopePublished]) {
        return [[UIImage imageNamed:@"browser-settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    
    return nil;
}

- (void)showScopeSelectionDialog:(UIButton *)sender
{
    NSString *field = nil;
    NSString *currentValue = nil;
    NSString *title = nil;
    
    if (sender.tag == k_name_textfield_tag) {
        field = kUserProfileDisplayNameScope;
        currentValue = _account.userDisplayNameScope;
        title = NSLocalizedString(@"Full name", nil);
    } else if (sender.tag == k_email_textfield_tag) {
        field = kUserProfileEmailScope;
        currentValue = _account.emailScope;
        title = NSLocalizedString(@"Email", nil);
    } else if (sender.tag == k_phone_textfield_tag) {
        field = kUserProfilePhoneScope;
        currentValue = _account.phoneScope;
        title = NSLocalizedString(@"Phone number", nil);
    } else if (sender.tag == k_address_textfield_tag) {
        field = kUserProfileAddressScope;
        currentValue = _account.addressScope;
        title = NSLocalizedString(@"Address", nil);
    } else if (sender.tag == k_website_textfield_tag) {
        field = kUserProfileWebsiteScope;
        currentValue = _account.websiteScope;
        title = NSLocalizedString(@"Website", nil);
    } else if (sender.tag == k_twitter_textfield_tag) {
        field = kUserProfileTwitterScope;
        currentValue = _account.twitterScope;
        title = NSLocalizedString(@"Twitter", nil);
    } else if (sender.tag == k_avatar_scope_button_tag) {
        field = kUserProfileAvatarScope;
        currentValue = _account.avatarScope;
        title = NSLocalizedString(@"Profile picture", nil);
    }
    
    NSMutableArray *options = [NSMutableArray new];
    
    DetailedOption *privateOption = [[DetailedOption alloc] init];
    privateOption.identifier = kUserProfileScopePrivate;
    privateOption.image = [[UIImage imageNamed:@"mobile-phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    privateOption.title = NSLocalizedString(@"Private", nil);
    privateOption.subtitle = NSLocalizedString(@"Only visible to people matched via phone number integration", nil);
    privateOption.selected = [currentValue isEqualToString:kUserProfileScopePrivate];
    
    DetailedOption *localOption = [[DetailedOption alloc] init];
    localOption.identifier = kUserProfileScopeLocal;
    localOption.image = [[UIImage imageNamed:@"password-settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    localOption.title = NSLocalizedString(@"Local", nil);
    localOption.subtitle = NSLocalizedString(@"Only visible to people on this instance and guests", nil);
    localOption.selected = [currentValue isEqualToString:kUserProfileScopeLocal];
    
    DetailedOption *federatedOption = [[DetailedOption alloc] init];
    federatedOption.identifier = kUserProfileScopeFederated;
    federatedOption.image = [[UIImage imageNamed:@"group"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    federatedOption.title = NSLocalizedString(@"Federated", nil);
    federatedOption.subtitle = NSLocalizedString(@"Only synchronize to trusted servers", nil);
    federatedOption.selected = [currentValue isEqualToString:kUserProfileScopeFederated];
    
    DetailedOption *publishedOption = [[DetailedOption alloc] init];
    publishedOption.identifier = kUserProfileScopePrivate;
    publishedOption.image = [[UIImage imageNamed:@"browser-settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    publishedOption.title = NSLocalizedString(@"Published", nil);
    publishedOption.subtitle = NSLocalizedString(@"Synchronize to trusted servers and the global and public address book", nil);
    publishedOption.selected = [currentValue isEqualToString:kUserProfileScopePublished];
    
    if (field != kUserProfileDisplayNameScope && field != kUserProfileEmailScope) {
        [options addObject:privateOption];
    }
    
    [options addObject:localOption];
    
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:_account.accountId];
    if (serverCapabilities.accountPropertyScopesFederationEnabled) {
        [options addObject:federatedOption];
        [options addObject:publishedOption];
    }
    
    DetailedOptionsSelectorTableViewController *optionSelectorVC = [[DetailedOptionsSelectorTableViewController alloc] initWithOptions:options forSenderIdentifier:field andTitle:title];
    optionSelectorVC.delegate = self;
    NCNavigationController *optionSelectorNC = [[NCNavigationController alloc] initWithRootViewController:optionSelectorVC];
    [self presentViewController:optionSelectorNC animated:YES completion:nil];
}

- (void)setUserProfileField:(NSString *)field scopeValue:(NSString *)scope
{
    [self setModifyingProfileUI];
    
    [[NCAPIController sharedInstance] setUserProfileField:field withValue:scope forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (error) {
            [self showScopeModificationError];
        } else {
            [self refreshUserProfile];
        }
        
        [self removeModifyingProfileUI];
    }];
}

- (void)showScopeModificationError
{
    UIAlertController *errorDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"An error occured changing privacy setting", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [errorDialog addAction:okAction];
    [self presentViewController:errorDialog animated:YES completion:nil];
}

#pragma mark - DetailedOptionSelector Delegate

- (void)detailedOptionsSelector:(DetailedOptionsSelectorTableViewController *)viewController didSelectOptionWithIdentifier:(DetailedOption *)option
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (!option.selected) {
            [self setUserProfileField:viewController.senderId scopeValue:option.identifier];
        }
    }];
}

- (void)detailedOptionsSelectorWasCancelled:(DetailedOptionsSelectorTableViewController *)viewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIImagePickerController Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
        [self dismissViewControllerAnimated:YES completion:^{
            TOCropViewController *cropViewController = [[TOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular image:image];
            cropViewController.delegate = self;
            [self presentViewController:cropViewController animated:YES completion:nil];
        }];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - TOCropViewController Delegate

- (void)cropViewController:(TOCropViewController *)cropViewController didCropToImage:(UIImage *)image withRect:(CGRect)cropRect angle:(NSInteger)angle
{
    [self sendUserProfileImage:image];

    // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
    cropViewController.transitioningDelegate = nil;
    [cropViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)cropViewController:(TOCropViewController *)cropViewController didFinishCancelled:(BOOL)cancelled
{
    // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
    cropViewController.transitioningDelegate = nil;
    [cropViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    // Allow click on tableview cells
    if ([touch.view isDescendantOfView:self.tableView]) {
        if (![touch.view isDescendantOfView:_activeTextField]) {
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
    
    BOOL waitForModitication = _waitingForModification;
    _waitingForModification = NO;
    _activeTextField = nil;
        
    if (tag == k_name_textfield_tag) {
        field = kUserProfileDisplayName;
        currentValue = _account.userDisplayName;
    } else if (tag == k_email_textfield_tag) {
        field = kUserProfileEmail;
        currentValue = _account.email;
    } else if (tag == k_phone_textfield_tag) {
        return;
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

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (textField.tag == k_phone_textfield_tag) {
        NSString *inputPhoneNumber = [textField.text stringByReplacingCharactersInRange:range withString:string];
        NBPhoneNumber *phoneNumber = [_phoneUtil parse:inputPhoneNumber defaultRegion:nil error:nil];
        _setPhoneAction.enabled = [_phoneUtil isValidNumber:phoneNumber] && ![_account.phone isEqualToString:inputPhoneNumber];
    }
    return YES;
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
    
    [self refreshProfileTableView];
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

- (void)presentSetPhoneNumberDialog
{
    UIAlertController *setPhoneNumberDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Phone number", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    BOOL hasPhone = _account.phone && ![_account.phone isEqualToString:@""];
    
    __weak typeof(self) weakSelf = self;
    [setPhoneNumberDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        NSString *location = [[NSLocale currentLocale] countryCode];
        textField.text = [NSString stringWithFormat:@"+%@", [self->_phoneUtil getCountryCodeForRegion:location]];
        if (hasPhone) {
            textField.text = self->_account.phone;
        }
        NBPhoneNumber *exampleNumber = [self->_phoneUtil getExampleNumber:location error:nil];
        textField.placeholder = [self->_phoneUtil format:exampleNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:nil];
        textField.keyboardType = UIKeyboardTypePhonePad;
        textField.delegate = weakSelf;
        textField.tag = k_phone_textfield_tag;
    }];
    
    _setPhoneAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Set", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *phoneNumber = [[setPhoneNumberDialog textFields][0] text];
        [self setPhoneNumber:phoneNumber];
    }];
    _setPhoneAction.enabled = NO;
    [setPhoneNumberDialog addAction:_setPhoneAction];
    
    if (hasPhone) {
        UIAlertAction *removeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Remove", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self setPhoneNumber:@""];
        }];
        [setPhoneNumberDialog addAction:removeAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [setPhoneNumberDialog addAction:cancelAction];
    
    [self presentViewController:setPhoneNumberDialog animated:YES completion:nil];
}

- (void)setPhoneNumber:(NSString *)phoneNumber
{
    [self setModifyingProfileUI];
    
    [[NCAPIController sharedInstance] setUserProfileField:kUserProfilePhone withValue:phoneNumber forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (error) {
            [self showProfileModificationErrorForField:k_phone_textfield_tag inTextField:nil];
        } else {
            [self refreshUserProfile];
        }
        
        [self removeModifyingProfileUI];
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getProfileSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    if (profileSection == kProfileSectionSummary) {
        return [self rowsInSummarySection].count;
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    switch (profileSection) {
        case kProfileSectionName:
        case kProfileSectionEmail:
        case kProfileSectionPhoneNumber:
        case kProfileSectionAddress:
        case kProfileSectionWebsite:
        case kProfileSectionTwitter:
        case kProfileSectionAddAccount:
            return 40;
        case kProfileSectionSummary:
            return 20;
        default:
            return 0;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    switch (profileSection) {
        case kProfileSectionEmail:
            return 30;
        default:
            return 0;
    }
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    HeaderWithButton *headerView = [[HeaderWithButton alloc] init];
    CGSize imageSize = CGSizeMake(20, 20);
    CGFloat topInset = (headerView.button.frame.size.height - imageSize.height) / 2;
    CGFloat rightInset = 5;
    CGFloat leftInset = (headerView.button.frame.size.width - imageSize.width - rightInset);
    headerView.button.imageEdgeInsets = UIEdgeInsetsMake(topInset, leftInset, topInset, rightInset);
    [headerView.button addTarget:self action:@selector(showScopeSelectionDialog:) forControlEvents:UIControlEventTouchUpInside];
    
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:_account.accountId];
    BOOL shouldEnableNameAndEmailScopeButton = serverCapabilities.accountPropertyScopesFederationEnabled;
    
    NSArray *sections = [self getProfileSections];
    ProfileSection profileSection = [[sections objectAtIndex:section] intValue];
    switch (profileSection) {
        case kProfileSectionName:
        {
            headerView.label.text = [NSLocalizedString(@"Full name", nil) uppercaseString];
            headerView.button.tag = k_name_textfield_tag;
            headerView.button.enabled = shouldEnableNameAndEmailScopeButton;
            [headerView.button setImage:[self imageForScope:_account.userDisplayNameScope] forState:UIControlStateNormal];
        }
            break;
            
        case kProfileSectionEmail:
        {
            headerView.label.text = [NSLocalizedString(@"Email", nil) uppercaseString];
            headerView.button.tag = k_email_textfield_tag;
            headerView.button.enabled = shouldEnableNameAndEmailScopeButton;
            [headerView.button setImage:[self imageForScope:_account.emailScope] forState:UIControlStateNormal];
        }
            break;
            
        case kProfileSectionPhoneNumber:
        {
            headerView.label.text = [NSLocalizedString(@"Phone number", nil) uppercaseString];
            headerView.button.tag = k_phone_textfield_tag;
            [headerView.button setImage:[self imageForScope:_account.phoneScope] forState:UIControlStateNormal];
        }
            break;
            
        case kProfileSectionAddress:
        {
            headerView.label.text = [NSLocalizedString(@"Address", nil) uppercaseString];
            headerView.button.tag = k_address_textfield_tag;
            [headerView.button setImage:[self imageForScope:_account.addressScope] forState:UIControlStateNormal];
        }
            break;
            
        case kProfileSectionWebsite:
        {
            headerView.label.text = [NSLocalizedString(@"Website", nil) uppercaseString];
            headerView.button.tag = k_website_textfield_tag;
            [headerView.button setImage:[self imageForScope:_account.websiteScope] forState:UIControlStateNormal];
        }
            break;
            
        case kProfileSectionTwitter:
        {
            headerView.label.text = [NSLocalizedString(@"Twitter", nil) uppercaseString];
            headerView.button.tag = k_twitter_textfield_tag;
            [headerView.button setImage:[self imageForScope:_account.twitterScope] forState:UIControlStateNormal];
        }
            break;
            
        default:
            break;
    }
    
    if (headerView.button.tag) {
        return headerView;
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
    static NSString *summaryCellIdentifier = @"SummaryCellIdentifier";
    static NSString *addAccountCellIdentifier = @"AddAccountCellIdentifier";
    static NSString *removeAccountCellIdentifier = @"RemoveAccountCellIdentifier";
    
    UITableViewCell *cell = nil;
    
    TextInputTableViewCell *textInputCell = [tableView dequeueReusableCellWithIdentifier:kTextInputCellIdentifier];
    if (!textInputCell) {
        textInputCell = [[TextInputTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kTextInputCellIdentifier];
    }
    textInputCell.textField.delegate = self;
    textInputCell.textField.keyboardType = UIKeyboardTypeDefault;
    textInputCell.textField.placeholder = nil;
    textInputCell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    
    ProfileSection section = [[[self getProfileSections] objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kProfileSectionName:
        {
            textInputCell.textField.text = _account.userDisplayName;
            textInputCell.textField.tag = k_name_textfield_tag;
            textInputCell.textField.userInteractionEnabled = [_editableFields containsObject:kUserProfileDisplayName];
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionEmail:
        {
            textInputCell.textField.text = _account.email;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your email address", nil);
            textInputCell.textField.tag = k_email_textfield_tag;
            textInputCell.textField.userInteractionEnabled = [_editableFields containsObject:kUserProfileEmail];
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionPhoneNumber:
        {
            NBPhoneNumber *phoneNumber = [_phoneUtil parse:_account.phone defaultRegion:nil error:nil];
            textInputCell.textField.text = phoneNumber ? [_phoneUtil format:phoneNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:nil] : nil;
            textInputCell.textField.keyboardType = UIKeyboardTypePhonePad;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your phone number", nil);
            textInputCell.textField.tag = k_phone_textfield_tag;
            textInputCell.textField.userInteractionEnabled = NO;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionAddress:
        {
            textInputCell.textField.text = _account.address;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your postal address", nil);
            textInputCell.textField.tag = k_address_textfield_tag;
            textInputCell.textField.userInteractionEnabled = [_editableFields containsObject:kUserProfileAddress];
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionWebsite:
        {
            textInputCell.textField.text = _account.website;
            textInputCell.textField.keyboardType = UIKeyboardTypeURL;
            textInputCell.textField.placeholder = NSLocalizedString(@"Link https://…", nil);
            textInputCell.textField.tag = k_website_textfield_tag;
            textInputCell.textField.userInteractionEnabled = [_editableFields containsObject:kUserProfileWebsite];
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionTwitter:
        {
            textInputCell.textField.text = _account.twitter;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Twitter handle @…", nil);
            textInputCell.textField.tag = k_twitter_textfield_tag;
            textInputCell.textField.userInteractionEnabled = [_editableFields containsObject:kUserProfileTwitter];
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionSummary:
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:summaryCellIdentifier];
            UIImage *scopeImage = nil;
            SummaryRow summaryRow = [[[self rowsInSummarySection] objectAtIndex:indexPath.row] intValue];
            switch (summaryRow) {
                case kSummaryRowEmail:
                    cell.textLabel.text = _account.email;
                    [cell.imageView setImage:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    scopeImage = [self imageForScope:_account.emailScope];
                    break;
                    
                case kSummaryRowPhoneNumber:
                {
                    NBPhoneNumber *phoneNumber = [_phoneUtil parse:_account.phone defaultRegion:nil error:nil];
                    cell.textLabel.text = phoneNumber ? [_phoneUtil format:phoneNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:nil] : nil;
                    [cell.imageView setImage:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    scopeImage = [self imageForScope:_account.phoneScope];
                }
                    break;
                    
                case kSummaryRowAddress:
                    cell.textLabel.text = _account.address;
                    [cell.imageView setImage:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    scopeImage = [self imageForScope:_account.addressScope];
                    break;
                    
                case kSummaryRowWebsite:
                    cell.textLabel.text = _account.website;
                    [cell.imageView setImage:[[UIImage imageNamed:@"website"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    scopeImage = [self imageForScope:_account.websiteScope];
                    break;
                    
                case kSummaryRowTwitter:
                    cell.textLabel.text = _account.twitter;
                    [cell.imageView setImage:[[UIImage imageNamed:@"twitter"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    scopeImage = [self imageForScope:_account.websiteScope];
                    break;
            }
            cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
            if (_showScopes) {
                UIImageView *scopeImageView = [[UIImageView alloc] initWithImage:scopeImage];
                scopeImageView.frame = CGRectMake(0, 0, 20, 20);
                scopeImageView.tintColor = [NCAppBranding placeholderColor];
//                cell.accessoryView = scopeImageView;
            }
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
    } else if (section == kProfileSectionPhoneNumber) {
        [self presentSetPhoneNumberDialog];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
