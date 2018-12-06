//
//  RoomCreation2TableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "RoomCreation2TableViewController.h"

#import "ContactsTableViewCell.h"
#import "RoomNameTableViewCell.h"
#import "NCUser.h"
#import "NCAPIController.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

typedef enum CreationSection {
    kCreationSectionName = 0,
    kCreationSectionParticipantsOrPassword,
    kCreationSectionNumber
} CreationSection;

NSString * const NCRoomCreatedNotification  = @"NCRoomCreatedNotification";

@interface RoomCreation2TableViewController ()

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
    
    self.navigationItem.title = (_publicRoom) ? @"New public conversation" : @"New group conversation";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    _passwordTextField = [[UITextField alloc] initWithFrame:CGRectMake(180, 10, 115, 30)];
    _passwordTextField.textAlignment = NSTextAlignmentRight;
    _passwordTextField.placeholder = @"No password";
    _passwordTextField.adjustsFontSizeToFitWidth = YES;
    _passwordTextField.textColor = [UIColor blackColor];
    _passwordTextField.secureTextEntry = YES;
    
    _creatingRoomView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _createRoomButton = [[UIBarButtonItem alloc] initWithTitle:@"Create" style:UIBarButtonItemStyleDone
                                                        target:self action:@selector(createButtonPressed)];
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
    [[NCAPIController sharedInstance] createRoomWith:nil
                                              ofType:public ? kNCRoomTypePublicCall : kNCRoomTypeGroupCall
                                             andName:roomName
                                 withCompletionBlock:^(NSString *token, NSError *error) {
                                     if (!error) {
                                         _createdRoomToken = token;
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
    [[NCAPIController sharedInstance] addParticipant:participant.userId toRoom:_createdRoomToken withCompletionBlock:^(NSError *error) {
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
    [[NCAPIController sharedInstance] setPassword:_passwordToBeSet toRoom:_createdRoomToken withCompletionBlock:^(NSError *error) {
        if (!error) {
            _passwordToBeSet = nil;
            [self checkRoomCreationCompletion];
        } else {
            NSLog(@"Error setting room password: %@", error.description);
            [self cancelRoomCreation];        }
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
                                                          userInfo:@{@"token":_createdRoomToken}];
    }];
}

- (void)cancelRoomCreation
{
    [self enableInteraction];
    [_creatingRoomView stopAnimating];
    self.navigationItem.rightBarButtonItem = _createRoomButton;
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:@"Could not create conversation"
                                 message:[NSString stringWithFormat:@"An error occurred while creating the conversation"]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:@"OK"
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
    if (section == kCreationSectionParticipantsOrPassword && !_publicRoom ) {
        if (_participants.count == 0) {
            return @"";
        } else if (_participants.count == 1) {
            return @"1 participant";
        }
        return [NSString stringWithFormat:@"%ld participants", _participants.count];
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == kCreationSectionParticipantsOrPassword && _publicRoom ) {
        return @"Anyone who knows the link to this conversation will be able to access it. You can protect it by setting a password.";
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
                [cell.roomImage setImage:[UIImage imageNamed:@"public-bg"]];
            } else {
                [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
            }
            cell.roomNameTextField.text = _roomName;
            _roomNameTextField = cell.roomNameTextField;
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
                
                cell.textLabel.text = @"Password";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryView = _passwordTextField;
                [cell.imageView setImage:[UIImage imageNamed:@"privacy"]];
                
                return cell;
            } else {
                NCUser *participant = [_participants objectAtIndex:indexPath.row];
                ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
                if (!cell) {
                    cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
                }
                
                cell.labelTitle.text = participant.name;
                // Create avatar for every contact
                [cell.contactImage setImageWithString:participant.name color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId andSize:96]
                                         placeholderImage:nil
                                                  success:nil
                                                  failure:nil];
                cell.contactImage.layer.cornerRadius = 24.0;
                cell.contactImage.layer.masksToBounds = YES;
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
