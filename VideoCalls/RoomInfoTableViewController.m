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
    kPublicSectionPassword,
    kPublicSectionSendLink
} PublicSection;

@interface RoomInfoTableViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UISwitch *publicSwtich;

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
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self getRoomParticipants];
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

- (void)showPasswordOptions
{
    NSString *alertTitle = _room.hasPassword ? @"Set new password:" : @"Set password:";
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    
    NSString *actionTitle = _room.hasPassword ? @"Change password" : @"OK";
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = [[renameDialog textFields][0] text];
        NSString *trimmedPassword = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:_room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self getRoomInfo];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    if (_room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:@"Remove password" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:_room.token withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self getRoomInfo];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    //TODO: Error handling
                }
            }];
        }];
        [renameDialog addAction:removePasswordAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [renameDialog addAction:cancelAction];
    
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)makeRoomPublic
{
    [[NCAPIController sharedInstance] makeRoomPublic:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self shareRoomLink];
            [self getRoomInfo];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            //TODO: Error handling
        }
        _publicSwtich.enabled = YES;
    }];
}

- (void)makeRoomPrivate
{
    [[NCAPIController sharedInstance] makeRoomPrivate:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomInfo];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            //TODO: Error handling
        }
        _publicSwtich.enabled = YES;
    }];
}

- (void)shareRoomLink
{
    NSString *shareMessage = [NSString stringWithFormat:@"Join the conversation at %@/index.php/call/%@",
                              [[NCAPIController sharedInstance] currentServerUrl], _room.token];
    if (_room.name && ![_room.name isEqualToString:@""]) {
        shareMessage = [NSString stringWithFormat:@"Join the conversation%@ at %@/index.php/call/%@",
                        [NSString stringWithFormat:@" \"%@\"", _room.name], [[NCAPIController sharedInstance] currentServerUrl], _room.token];
    }
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:@"%@ invitation", appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];
    
    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:kPublicSectionSendLink inSection:kCreationSectionPublic]];
    
    [self presentViewController:controller animated:YES completion:nil];
    
    controller.completionWithItemsHandler = ^(NSString *activityType,
                                              BOOL completed,
                                              NSArray *returnedItems,
                                              NSError *error) {
        if (error) {
            NSLog(@"An Error occured sharing room: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

#pragma mark - Public switch

- (void)publicValueChanged:(id)sender
{
    _publicSwtich.enabled = NO;
    if (_publicSwtich.on) {
        [self makeRoomPublic];
    } else {
        [self makeRoomPrivate];
    }
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
            return (_publicSwtich.on) ? 3 : 1;
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
    static NSString *shareLinkCellIdentifier = @"ShareLinkCellIdentifier";
    static NSString *passwordCellIdentifier = @"PasswordCellIdentifier";
    static NSString *sendLinkCellIdentifier = @"SendLinkCellIdentifier";
    
    switch (indexPath.section) {
        case kCreationSectionName:
        {
            RoomNameTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomNameCellIdentifier];
            if (!cell) {
                cell = [[RoomNameTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomNameCellIdentifier];
            }
            
            if (_room.type == kNCRoomTypeOneToOneCall) {
                // Create avatar for every contact
                [cell.roomImage setImageWithString:_room.name color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96]
                                      placeholderImage:nil success:nil failure:nil];
                _roomNameTextField = nil;
                cell.roomNameTextField.textColor = [UIColor grayColor];
                cell.userInteractionEnabled = NO;
            } else {
                if (_room.type == kNCRoomTypePublicCall) {
                    [cell.roomImage setImage:(_room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
                } else {
                    [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
                }
                cell.roomNameTextField.text = _room.displayName;
                _roomNameTextField = cell.roomNameTextField;
                _roomNameTextField.delegate = self;
                [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
                cell.userInteractionEnabled = YES;
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
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:shareLinkCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:shareLinkCellIdentifier];
                    }
                    
                    cell.textLabel.text = @"Share link";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _publicSwtich;
                    _publicSwtich.on = (_room.type == kNCRoomTypePublicCall) ? YES : NO;
                    [cell.imageView setImage:[UIImage imageNamed:@"public-setting"]];
                    
                    return cell;
                }
                    break;
                    
                case kPublicSectionPassword:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:passwordCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:passwordCellIdentifier];
                    }
                    
                    cell.textLabel.text = (_room.hasPassword) ? @"Change password" : @"Set password";
                    [cell.imageView setImage:(_room.hasPassword) ? [UIImage imageNamed:@"privacy"] : [UIImage imageNamed:@"no-password-settings"]];
                    
                    return cell;
                }
                    break;
                    
                case kPublicSectionSendLink:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sendLinkCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sendLinkCellIdentifier];
                    }
                    
                    cell.textLabel.text = @"Send conversation link";
                    [cell.imageView setImage:[UIImage imageNamed:@"share-settings"]];
                    
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
            
            return cell;
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kCreationSectionName:
            break;
        case kCreationSectionPublic:
        {
            switch (indexPath.row) {
                case kPublicSectionToggle:
                    break;
                    
                case kPublicSectionPassword:
                    [self showPasswordOptions];
                    break;
                    
                case kPublicSectionSendLink:
                    [self shareRoomLink];
                    break;
            }
        }
            break;
        case kCreationSectionParticipants:
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
