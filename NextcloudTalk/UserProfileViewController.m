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

#import "NBPhoneNumberUtil.h"
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

@interface UserProfileViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, TOCropViewControllerDelegate>
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
    
    self.tableView.tableHeaderView = [self avatarHeaderView];
    
    [self showEditButton];
    
    _modifyingProfileView = [[UIActivityIndicatorView alloc] init];
    _modifyingProfileView.color = [NCAppBranding themeTextColor];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    
    [self.tableView registerNib:[UINib nibWithNibName:kTextInputTableViewCellNibName bundle:nil] forCellReuseIdentifier:kTextInputCellIdentifier];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userProfileImageUpdated:) name:NCUserProfileImageUpdatedNotification object:nil];
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
    } else {
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
    BOOL shouldShowEditAvatarButton = _isEditable && [[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityTempUserAvatarAPI forAccountId:_account.accountId];
    
    CGFloat headerViewHeight = (shouldShowEditAvatarButton) ? 140 : 160;
    UIView *avatarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, headerViewHeight)];
    [avatarView setAutoresizingMask:UIViewAutoresizingNone];
    avatarView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    UIImageView *avatarImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 20, 80, 80)];
    avatarImageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    avatarImageView.layer.cornerRadius = 40.0;
    avatarImageView.layer.masksToBounds = YES;
    [avatarImageView setImage:[[NCAPIController sharedInstance] userProfileImageForAccount:_account withSize:CGSizeMake(160, 160)]];
    [avatarView addSubview:avatarImageView];
    
    if (!_isEditable) {
        UILabel *displayNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 110, 80, 30)];
        displayNameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        displayNameLabel.font = [UIFont systemFontOfSize:26];
        displayNameLabel.textAlignment = NSTextAlignmentCenter;
        displayNameLabel.minimumScaleFactor = 0.6f;
        displayNameLabel.numberOfLines = 1;
        displayNameLabel.adjustsFontSizeToFitWidth = YES;
        displayNameLabel.text = _account.userDisplayName;
        [avatarView addSubview:displayNameLabel];
    }
    
    _editAvatarButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 110, 160, 24)];
    [_editAvatarButton setTitle:NSLocalizedString(@"Edit", nil) forState:UIControlStateNormal];
    [_editAvatarButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    _editAvatarButton.titleLabel.font = [UIFont systemFontOfSize:15];
    _editAvatarButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _editAvatarButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _editAvatarButton.titleLabel.minimumScaleFactor = 0.9f;
    _editAvatarButton.titleLabel.numberOfLines = 1;
    _editAvatarButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _editAvatarButton.hidden = !shouldShowEditAvatarButton;
    [_editAvatarButton addTarget:self action:@selector(showAvatarOptions) forControlEvents:UIControlEventTouchUpInside];
    [avatarView addSubview:_editAvatarButton];
    
    return avatarView;
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
    
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        [optionsActionSheet addAction:cameraAction];
    }
    [optionsActionSheet addAction:photoLibraryAction];
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
            [self showSetProfileImageError];
            NSLog(@"Error sending profile image: %@", error.description);
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

- (void)showSetProfileImageError
{
    UIAlertController *errorDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"An error occured setting profile image", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [errorDialog addAction:okAction];
    [self presentViewController:errorDialog animated:YES completion:nil];
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
        NBPhoneNumberUtil *phoneUtil = [[NBPhoneNumberUtil alloc] init];
        NSError *error = nil;
        NSString *inputPhoneNumber = [textField.text stringByReplacingCharactersInRange:range withString:string];
        NBPhoneNumber *phoneNumber = [phoneUtil parse:inputPhoneNumber defaultRegion:nil error:&error];
        _setPhoneAction.enabled = [phoneUtil isValidNumber:phoneNumber] && ![_account.phone isEqualToString:inputPhoneNumber];
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
        NBPhoneNumberUtil *phoneUtil = [[NBPhoneNumberUtil alloc] init];
        NSError *error = nil;
        textField.text = [NSString stringWithFormat:@"+%@", [phoneUtil getCountryCodeForRegion:location]];
        if (hasPhone) {
            textField.text = self->_account.phone;
        }
        NBPhoneNumber *exampleNumber = [phoneUtil getExampleNumber:location error:&error];
        textField.placeholder = [phoneUtil format:exampleNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:&error];
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
    return 40;
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
    static NSString *summaryCellIdentifier = @"SummaryCellIdentifier";
    static NSString *addAccountCellIdentifier = @"AddAccountCellIdentifier";
    static NSString *removeAccountCellIdentifier = @"RemoveAccountCellIdentifier";
    
    UITableViewCell *cell = nil;
    
    TextInputTableViewCell *textInputCell = [tableView dequeueReusableCellWithIdentifier:kTextInputCellIdentifier];
    if (!textInputCell) {
        textInputCell = [[TextInputTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kTextInputCellIdentifier];
    }
    textInputCell.textField.delegate = self;
    
    ProfileSection section = [[[self getProfileSections] objectAtIndex:indexPath.section] intValue];
    SummaryRow summaryRow = [[[self rowsInSummarySection] objectAtIndex:indexPath.row] intValue];
    switch (section) {
        case kProfileSectionName:
        {
            textInputCell.textField.text = _account.userDisplayName;
            textInputCell.textField.tag = k_name_textfield_tag;
            textInputCell.textField.userInteractionEnabled = _isEditable;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionEmail:
        {
            textInputCell.textField.text = _account.email;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Your email address", nil);
            textInputCell.textField.tag = k_email_textfield_tag;
            textInputCell.textField.userInteractionEnabled = _isEditable;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionPhoneNumber:
        {
            NBPhoneNumberUtil *phoneUtil = [[NBPhoneNumberUtil alloc] init];
            NSError *error = nil;
            NBPhoneNumber *phoneNumber = [phoneUtil parse:_account.phone defaultRegion:nil error:&error];
            textInputCell.textField.text = phoneNumber ? [phoneUtil format:phoneNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:&error] : nil;
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
            textInputCell.textField.userInteractionEnabled = _isEditable;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionWebsite:
        {
            textInputCell.textField.text = _account.website;
            textInputCell.textField.placeholder = NSLocalizedString(@"Link https://…", nil);
            textInputCell.textField.tag = k_website_textfield_tag;
            textInputCell.textField.userInteractionEnabled = _isEditable;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionTwitter:
        {
            textInputCell.textField.text = _account.twitter;
            textInputCell.textField.keyboardType = UIKeyboardTypeEmailAddress;
            textInputCell.textField.placeholder = NSLocalizedString(@"Twitter handle @…", nil);
            textInputCell.textField.tag = k_twitter_textfield_tag;
            textInputCell.textField.userInteractionEnabled = _isEditable;
            cell = textInputCell;
        }
            break;
            
        case kProfileSectionSummary:
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:summaryCellIdentifier];
            switch (summaryRow) {
                case kSummaryRowEmail:
                    cell.textLabel.text = _account.email;
                    [cell.imageView setImage:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    break;
                    
                case kSummaryRowPhoneNumber:
                {
                    NBPhoneNumberUtil *phoneUtil = [[NBPhoneNumberUtil alloc] init];
                    NSError *error = nil;
                    NBPhoneNumber *phoneNumber = [phoneUtil parse:_account.phone defaultRegion:nil error:&error];
                    cell.textLabel.text = phoneNumber ? [phoneUtil format:phoneNumber numberFormat:NBEPhoneNumberFormatINTERNATIONAL error:&error] : nil;
                    [cell.imageView setImage:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                }
                    break;
                    
                case kSummaryRowAddress:
                    cell.textLabel.text = _account.address;
                    [cell.imageView setImage:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    break;
                    
                case kSummaryRowWebsite:
                    cell.textLabel.text = _account.website;
                    [cell.imageView setImage:[[UIImage imageNamed:@"browser-settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    break;
                    
                case kSummaryRowTwitter:
                    cell.textLabel.text = _account.twitter;
                    [cell.imageView setImage:[[UIImage imageNamed:@"twitter"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    break;
            }
            cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
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
