//
//  RoomInfoTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 02.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "RoomInfoTableViewController.h"


#import "ContactsTableViewCell.h"
#import "RoomNameTableViewCell.h"
#import "NCAPIController.h"
#import "NCRoomParticipant.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

typedef enum CreationSection {
    kCreationSectionName = 0,
    kCreationSectionPublic,
    kCreationSectionParticipants,
    kCreationSectionNumber
} CreationSection;

typedef enum PublicSection {
    kPublicSectionToggle = 0,
    kPublicSectionPassword
} PublicSection;

@interface RoomInfoTableViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UISwitch *publicSwtich;
@property (nonatomic, strong) UITextField *passwordTextField;

@end

@implementation RoomInfoTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (self) {
        _room = room;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = @"Conversation info";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    _roomParticipants = [[NSMutableArray alloc] init];
    
    _publicSwtich = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_publicSwtich addTarget: self action: @selector(publicValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _passwordTextField = [[UITextField alloc] initWithFrame:CGRectMake(180, 10, 115, 30)];
    _passwordTextField.textAlignment = NSTextAlignmentRight;
    _passwordTextField.placeholder = @"No password";
    _passwordTextField.adjustsFontSizeToFitWidth = YES;
    _passwordTextField.textColor = [UIColor blackColor];
    _passwordTextField.secureTextEntry = YES;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self getRoomParticipants];
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

#pragma mark - Utils

- (void)getRoomInfo
{
    [[NCAPIController sharedInstance] getRoomWithToken:_room.token withCompletionBlock:^(NCRoom *room, NSError *error) {
        _room = room;
        [self.tableView reloadData];
    }];
}

- (void)getRoomParticipants
{
    [[NCAPIController sharedInstance] getParticipantsFromRoom:_room.token withCompletionBlock:^(NSMutableArray *participants, NSError *error) {
        _roomParticipants = participants;
        [self.tableView reloadData];
    }];
}

#pragma mark - Room options

- (void)renameRoom
{
    NSString *newRoomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [[NCAPIController sharedInstance] renameRoom:_room.token withName:newRoomName andCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomInfo];
        } else {
            NSLog(@"Error renaming the room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

#pragma mark - Public switch

- (void)publicValueChanged:(id)sender
{
    BOOL isPublic = _publicSwtich.on;
    _roomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _publicSwtich.enabled = NO;
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        _publicSwtich.enabled = YES;
    }];
    [self.tableView beginUpdates];
    // Reload room name section
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    // Show/Hide password row
    NSIndexPath *passwordIP = [NSIndexPath indexPathForRow:kPublicSectionPassword inSection:kCreationSectionPublic];
    NSArray *indexArray = [NSArray arrayWithObjects:passwordIP,nil];
    if (isPublic) {
        _passwordTextField.text = @"";
        [self.tableView insertRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView deleteRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.tableView endUpdates];
    [CATransaction commit];
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (textField == _roomNameTextField) {
        [self renameRoom];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kCreationSectionNumber;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kCreationSectionPublic:
            return (_publicSwtich.on) ? 2 : 1;
            break;
            
        case kCreationSectionParticipants:
            return _roomParticipants.count;
            break;
    }
    
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section != kCreationSectionPublic) {
        return 80.0f;
    }
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kCreationSectionParticipants:
        {
            if (_roomParticipants.count == 0) {
                return @"";
            } else if (_roomParticipants.count == 1) {
                return @"1 participant";
            }
            return [NSString stringWithFormat:@"%ld participants", _roomParticipants.count];
        }
            break;
    }
    
    return nil;
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
            
            if (_publicSwtich.on) {
                [cell.roomImage setImage:[UIImage imageNamed:@"public-bg"]];
            } else {
                [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
            }
            cell.roomNameTextField.text = _room.displayName;
            _roomNameTextField = cell.roomNameTextField;
            _roomNameTextField.delegate = self;
            [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
            cell.userInteractionEnabled = YES;
            
            if (_room.type == kNCRoomTypeOneToOneCall) {
                // Create avatar for every contact
                [cell.roomImage setImageWithString:_room.name color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96]
                                      placeholderImage:nil success:nil failure:nil];
                _roomNameTextField = nil;
                cell.roomNameTextField.textColor = [UIColor grayColor];
                cell.userInteractionEnabled = NO;
            }
            
            cell.roomImage.layer.cornerRadius = 24.0;
            cell.roomImage.layer.masksToBounds = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
            break;
        case kCreationSectionPublic:
        {
            switch (indexPath.row) {
                case kPublicSectionToggle:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:publicCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:publicCellIdentifier];
                    }
                    
                    cell.textLabel.text = @"Share link";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _publicSwtich;
                    [cell.imageView setImage:[UIImage imageNamed:@"public-setting"]];
                    
                    return cell;
                }
                    break;
                    
                case kPublicSectionPassword:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:publicCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:publicCellIdentifier];
                    }
                    
                    cell.textLabel.text = @"Password";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _passwordTextField;
                    [cell.imageView setImage:[UIImage imageNamed:@"privacy"]];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kCreationSectionParticipants:
        {
            NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
            ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
            if (!cell) {
                cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
            }
            
            cell.labelTitle.text = participant.displayName;
            // Create avatar for every participant
            [cell.contactImage setImageWithString:participant.displayName color:nil circular:true];
            // Request user avatar to the server and set it if exist
            [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId andSize:96]
                                     placeholderImage:nil
                                              success:nil
                                              failure:nil];
            cell.contactImage.layer.cornerRadius = 24.0;
            cell.contactImage.layer.masksToBounds = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
            break;
    }
    
    return cell;
}

@end
