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

#import "RoomCreation2TableViewController.h"

#import "UIImageView+AFNetworking.h"

#import "ContactsTableViewCell.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCUser.h"
#import "RoomNameTableViewCell.h"

typedef enum CreationSection {
    kCreationSectionName = 0,
    kCreationSectionParticipantsOrPassword,
    kCreationSectionNumber
} CreationSection;

NSString * const NCRoomCreatedNotification  = @"NCRoomCreatedNotification";

@interface RoomCreation2TableViewController () <UITextFieldDelegate>

@property (nonatomic, assign) BOOL publicRoom;
@property (nonatomic, strong) NSMutableArray *participants;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UITextField *passwordTextField;
@property (nonatomic, strong) UIBarButtonItem *createRoomButton;
@property (nonatomic, strong) UIActivityIndicatorView *creatingRoomView;
@property (nonatomic, assign) NSInteger participantsToBeAdded;
@property (nonatomic, strong) NSString *passwordToBeSet;
@property (nonatomic, strong) NSString *createdRoomToken;
@property (nonatomic, assign) BOOL didFocusRoomNameOnce;

@end

@implementation RoomCreation2TableViewController

- (instancetype)initForGroupRoomWithParticipants:(NSMutableArray *)participants
{
    self = [super init];
    if (self) {
        _publicRoom = NO;
        _participants = participants;
    }
    return self;
}

- (instancetype)initForPublicRoom
{
    self = [super init];
    if (self) {
        _publicRoom = YES;
        _participants = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = (_publicRoom) ? NSLocalizedString(@"New public conversation", nil) : NSLocalizedString(@"New group conversation", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    
    _passwordTextField = [[UITextField alloc] initWithFrame:CGRectMake(180, 10, 115, 30)];
    _passwordTextField.textAlignment = NSTextAlignmentRight;
    _passwordTextField.placeholder = NSLocalizedString(@"No password", nil);
    _passwordTextField.adjustsFontSizeToFitWidth = YES;
    _passwordTextField.secureTextEntry = YES;
    _passwordTextField.accessibilityLabel = NSLocalizedString(@"Password field for public conversation", nil);
    
    _creatingRoomView = [[UIActivityIndicatorView alloc] init];
    _creatingRoomView.color = [NCAppBranding themeTextColor];
    _createRoomButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Create", nil) style:UIBarButtonItemStyleDone
                                                        target:self action:@selector(createButtonPressed)];
    _createRoomButton.enabled = NO;
    _createRoomButton.accessibilityHint = NSLocalizedString(@"Double tap to create the conversation", nil);
    self.navigationItem.rightBarButtonItem = _createRoomButton;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
}

- (void)createButtonPressed
{
    [self startRoomCreation];
}

- (void)dismissKeyboard
{
    [_roomNameTextField resignFirstResponder];
    [_passwordTextField resignFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Room creation

- (void)startRoomCreation
{
    [self disableInteraction];
    [_creatingRoomView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_creatingRoomView];
    self.navigationController.navigationBar.userInteractionEnabled = NO;
    
    NSString *roomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *password = [_passwordTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![password isEqualToString:@""] && _publicRoom) {
        _passwordToBeSet = password;
    }
    _participantsToBeAdded = _participants.count;
    [self createGroupRoomWithName:roomName public:_publicRoom];
}

- (void)createGroupRoomWithName:(NSString *)roomName public:(BOOL)public
{
    [[NCAPIController sharedInstance] createRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] with:nil
                                              ofType:public ? kNCRoomTypePublic : kNCRoomTypeGroup
                                             andName:roomName
                                 withCompletionBlock:^(NSString *token, NSError *error) {
                                     if (!error) {
                                         self->_createdRoomToken = token;
                                         [self checkRoomCreationCompletion];
                                     } else {
                                         NSLog(@"Error creating new room: %@", error.description);
                                         [self cancelRoomCreation];
                                     }
                                 }];
}

- (void)addParticipants
{
    for (NCUser *participant in _participants) {
        [self addParticipant:participant];
    }
}

- (void)addParticipant:(NCUser *)participant
{
    [[NCAPIController sharedInstance] addParticipant:participant.userId ofType:participant.source toRoom:_createdRoomToken forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self participantHasBeenAdded];
        } else {
            NSLog(@"Error creating new room: %@", error.description);
            [self cancelRoomCreation];
        }
    }];
}

- (void)participantHasBeenAdded
{
    _participantsToBeAdded --;
    if (_participantsToBeAdded == 0) {
        [self checkRoomCreationCompletion];
    }
}

- (void)setPassword
{
    [[NCAPIController sharedInstance] setPassword:_passwordToBeSet toRoom:_createdRoomToken forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error, NSString *errorDescription) {
        if (!error) {
            self->_passwordToBeSet = nil;
            [self checkRoomCreationCompletion];
        } else {
            NSLog(@"Error setting room password: %@", error.description);
            [self cancelRoomCreationWithMessage:errorDescription];
        }
    }];
}

- (void)checkRoomCreationCompletion
{
    if (_participantsToBeAdded > 0) {
        [self addParticipants];
    } else if (_passwordToBeSet) {
        [self setPassword];
    } else {
        [self finishRoomCreation];
    }
}

- (void)finishRoomCreation
{
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomCreatedNotification
                                                            object:self
                                                          userInfo:@{@"token":self->_createdRoomToken}];
    }];
}

- (void)cancelRoomCreation
{
    [self cancelRoomCreationWithMessage:nil];
}

- (void)cancelRoomCreationWithMessage:(NSString *)message
{
    [self enableInteraction];
    [_creatingRoomView stopAnimating];
    self.navigationItem.rightBarButtonItem = _createRoomButton;
    
    if (message == nil) {
        message = NSLocalizedString(@"An error occurred while creating the conversation", nil);
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not create conversation", nil)
                                 message:message
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    [alert addAction:okButton];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

- (void)enableInteraction
{
    self.navigationController.navigationBar.userInteractionEnabled = YES;
    _roomNameTextField.enabled = YES;
    _passwordTextField.enabled = YES;
}

- (void)disableInteraction
{
    self.navigationController.navigationBar.userInteractionEnabled = NO;
    _roomNameTextField.enabled = NO;
    _passwordTextField.enabled = NO;
}

#pragma mark - UITextField delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == _roomNameTextField) {
        // Prevent crashing undo bug
        // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
        if (range.length + range.location > textField.text.length) {
            return NO;
        }
        // Set maximum character length
        NSUInteger newLength = [textField.text length] + [string length] - range.length;
        BOOL hasAllowedLength = newLength <= 200;
        // Enable/Disable create button
        if (hasAllowedLength) {
            NSString *roomName = [[textField.text stringByReplacingCharactersInRange:range withString:string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            _createRoomButton.enabled = roomName.length > 0;
        }
        return hasAllowedLength;
    }
    return YES;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kCreationSectionNumber;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kCreationSectionParticipantsOrPassword && !_publicRoom) {
        return _participants.count;
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    if (indexPath.section == kCreationSectionName) {
        return 80.0f;
    } else if (indexPath.section == kCreationSectionParticipantsOrPassword && !_publicRoom) {
        return kContactsTableCellHeight;
    }
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == kCreationSectionParticipantsOrPassword && !_publicRoom && _participants.count > 0) {
        return [NSString localizedStringWithFormat:NSLocalizedString(@"%ld participants", nil), _participants.count];
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == kCreationSectionName) {
        return NSLocalizedString(@"Please, set a name for this conversation.", nil);
    } else if (section == kCreationSectionParticipantsOrPassword && _publicRoom ) {
        return NSLocalizedString(@"Anyone who knows the link to this conversation will be able to access it. You can protect it by setting a password.", nil);
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(nonnull UITableViewCell *)cell forRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    BOOL isRoomNameCell = indexPath.row == 0 && indexPath.section == kCreationSectionName;
    if (isRoomNameCell && !_didFocusRoomNameOnce) {
        RoomNameTableViewCell *roomNameCell = (RoomNameTableViewCell *)cell;
        [roomNameCell.roomNameTextField becomeFirstResponder];
        _didFocusRoomNameOnce = YES;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *publicCellIdentifier = @"PublicConversationCellIdentifier";
    
    switch (indexPath.section) {
        case kCreationSectionName:
        {
            RoomNameTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomNameCellIdentifier];
            if (!cell) {
                cell = [[RoomNameTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomNameCellIdentifier];
            }
            
            if (_publicRoom) {
                [cell.roomImage setImage:[UIImage imageNamed:@"public"]];
            } else {
                [cell.roomImage setImage:[UIImage imageNamed:@"group"]];
            }
            cell.roomNameTextField.text = _roomName;
            _roomNameTextField = cell.roomNameTextField;
            _roomNameTextField.delegate = self;
            [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
            cell.userInteractionEnabled = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
            break;
        case kCreationSectionParticipantsOrPassword:
        {
            if (_publicRoom) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:publicCellIdentifier];
                if (!cell) {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:publicCellIdentifier];
                }
                
                cell.textLabel.text = NSLocalizedString(@"Password", nil);
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryView = _passwordTextField;
                [cell.imageView setImage:[UIImage imageNamed:@"password-settings"]];
                
                return cell;
            } else {
                NCUser *participant = [_participants objectAtIndex:indexPath.row];
                ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
                if (!cell) {
                    cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
                }
                
                cell.labelTitle.text = participant.name;
                
                if ([participant.source isEqualToString:kParticipantTypeUser]) {
                    [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                             placeholderImage:nil success:nil failure:nil];
                    [cell.contactImage setContentMode:UIViewContentModeScaleToFill];
                } else if ([participant.source isEqualToString:kParticipantTypeEmail]) {
                    [cell.contactImage setImage:[UIImage imageNamed:@"mail"]];
                } else {
                    [cell.contactImage setImage:[UIImage imageNamed:@"group"]];
                }
                
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.layoutMargins = UIEdgeInsetsMake(0, 72, 0, 0);
                
                return cell;
            }
        }
            break;
    }
    
    return cell;
}

@end
