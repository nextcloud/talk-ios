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
#import "NCRoomsManager.h"
#import "NCRoomParticipant.h"
#import "NCSettingsController.h"
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

typedef enum ModificationError {
    kModificationErrorRename = 0,
    kModificationErrorShare,
    kModificationErrorPassword,
    kModificationErrorModeration,
    kModificationErrorRemove
} ModificationError;

@interface RoomInfoTableViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UISwitch *publicSwtich;
@property (nonatomic, strong) UIActivityIndicatorView *modifyingRoomView;

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
    
    _modifyingRoomView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Utils

- (void)getRoomParticipants
{
    [[NCAPIController sharedInstance] getParticipantsFromRoom:_room.token withCompletionBlock:^(NSMutableArray *participants, NSError *error) {
        _roomParticipants = participants;
        [self.tableView reloadData];
        [self removeModifyingRoomUI];
    }];
}

- (BOOL)isAppUser:(NCRoomParticipant *)participant
{
    if ([participant.userId isEqualToString:[NCSettingsController sharedInstance].ncUser]) {
        return YES;
    }
    return NO;
}

- (void)setModifyingRoomUI
{
    [_modifyingRoomView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_modifyingRoomView];
    self.tableView.userInteractionEnabled = NO;
}

- (void)removeModifyingRoomUI
{
    [_modifyingRoomView stopAnimating];
    self.navigationItem.rightBarButtonItem = nil;
    self.tableView.userInteractionEnabled = YES;
}

- (void)showRoomModificationError:(ModificationError)error
{
    [self removeModifyingRoomUI];
    NSString *errorDescription = @"";
    switch (error) {
        case kModificationErrorRename:
            errorDescription = @"Could not rename the conversation";
            break;
            
        case kModificationErrorShare:
            errorDescription = @"Could not change sharing permissions of the conversation";
            break;
            
        case kModificationErrorPassword:
            errorDescription = @"Could not change password protection settings";
            break;
            
        case kModificationErrorModeration:
            errorDescription = @"Could not change moderation permissions of the participant";
            break;
            
        case kModificationErrorRemove:
            errorDescription = @"Could not remove participant";
            break;
            
        default:
            break;
    }
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:errorDescription
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [renameDialog addAction:okAction];
    [self presentViewController:renameDialog animated:YES completion:nil];
}

#pragma mark - Room Manager notifications

- (void)didUpdateRoom:(NSNotification *)notification
{
    [self removeModifyingRoomUI];
    
    NCRoom *room = [notification.userInfo objectForKey:@"room"];
    if (!room || ![room.token isEqualToString:_room.token]) {
        return;
    }
    
    _room = room;
    [self.tableView reloadData];
}

#pragma mark - Room options

- (void)renameRoom
{
    [self setModifyingRoomUI];
    NSString *newRoomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [[NCAPIController sharedInstance] renameRoom:_room.token withName:newRoomName andCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:_room.token];
        } else {
            NSLog(@"Error renaming the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorRename];
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
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:_room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [[NCRoomsManager sharedInstance] updateRoom:_room.token];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                [self showRoomModificationError:kModificationErrorPassword];
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    if (_room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:@"Remove password" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:_room.token withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [[NCRoomsManager sharedInstance] updateRoom:_room.token];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    [self showRoomModificationError:kModificationErrorPassword];
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
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPublic:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self shareRoomLink];
            [[NCRoomsManager sharedInstance] updateRoom:_room.token];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorShare];
        }
        _publicSwtich.enabled = YES;
    }];
}

- (void)makeRoomPrivate
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPrivate:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:_room.token];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorShare];
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

#pragma mark - Participant options

- (void)showModerationOptionsForParticipantAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:participant.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (participant.participantType == kNCParticipantTypeModerator) {
        UIAlertAction *demoteFromModerator = [UIAlertAction actionWithTitle:@"Demote from moderator"
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self demoteFromModerator:participant];
                                                                    }];
        [demoteFromModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:demoteFromModerator];
    } else if (participant.participantType == kNCParticipantTypeUser) {
        UIAlertAction *promoteToModerator = [UIAlertAction actionWithTitle:@"Promote to moderator"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self promoteToModerator:participant];
                                                                   }];
        [promoteToModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:promoteToModerator];
    }
    
    // Remove participant
    UIAlertAction *removeParticipant = [UIAlertAction actionWithTitle:@"Remove participant"
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^void (UIAlertAction *action) {
                                                                  [self removeParticipant:participant];
                                                              }];
    [removeParticipant setValue:[[UIImage imageNamed:@"delete-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:removeParticipant];
    
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)promoteToModerator:(NCRoomParticipant *)participant
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] promoteParticipant:participant.participantId toModeratorOfRoom:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomParticipants];
        } else {
            NSLog(@"Error promoting participant to moderator: %@", error.description);
            [self showRoomModificationError:kModificationErrorModeration];
        }
    }];
}

- (void)demoteFromModerator:(NCRoomParticipant *)participant
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] demoteModerator:participant.participantId toParticipantOfRoom:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomParticipants];
        } else {
            NSLog(@"Error demoting participant from moderator: %@", error.description);
            [self showRoomModificationError:kModificationErrorModeration];
        }
    }];
}

- (void)removeParticipant:(NCRoomParticipant *)participant
{
    if (participant.participantType == kNCParticipantTypeGuest) {
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] removeGuest:participant.participantId fromRoom:_room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self getRoomParticipants];
            } else {
                NSLog(@"Error removing guest from room: %@", error.description);
                [self showRoomModificationError:kModificationErrorRemove];
            }
        }];
    } else {
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] removeParticipant:participant.participantId fromRoom:_room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self getRoomParticipants];
            } else {
                NSLog(@"Error removing participant from room: %@", error.description);
                [self showRoomModificationError:kModificationErrorRemove];
            }
        }];
    }
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
            return (_room.isPublic && _room.canModerate) ? 3 : 1;
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
            
            switch (_room.type) {
                case kNCRoomTypeOneToOneCall:
                {
                    // Create avatar for every OneToOne call
                    [cell.roomImage setImageWithString:_room.displayName color:nil circular:true];
                    // Request user avatar to the server and set it if exist
                    [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96]
                                          placeholderImage:nil success:nil failure:nil];
                }
                    break;
                    
                case kNCRoomTypeGroupCall:
                    [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
                    break;
                    
                case kNCRoomTypePublicCall:
                    [cell.roomImage setImage:(_room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
                    break;
                    
                default:
                    break;
            }
            
            cell.roomNameTextField.text = _room.displayName;
            
            if (_room.canModerate && _room.type != kNCRoomTypeOneToOneCall) {
                _roomNameTextField = cell.roomNameTextField;
                _roomNameTextField.delegate = self;
                [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
                cell.userInteractionEnabled = YES;
            } else {
                _roomNameTextField = nil;
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
            if (_room.canModerate) {
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
            } else {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sendLinkCellIdentifier];
                if (!cell) {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sendLinkCellIdentifier];
                }
                
                cell.textLabel.text = @"Send conversation link";
                [cell.imageView setImage:[UIImage imageNamed:@"share-settings"]];
                
                return cell;
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
            
            // Display name
            cell.labelTitle.text = participant.displayName;
            
            // Avatar
            if (participant.participantType == kNCParticipantTypeGuest) {
                UIColor *guestAvatarColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
                NSString *avatarName = ([participant.displayName isEqualToString:@""]) ? @"?" : participant.displayName;
                NSString *guestName = ([participant.displayName isEqualToString:@""]) ? @"Guest" : participant.displayName;
                cell.labelTitle.text = guestName;
                [cell.contactImage setImageWithString:avatarName color:guestAvatarColor circular:true];
            } else {
                // Create avatar for every participant
                [cell.contactImage setImageWithString:participant.displayName color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId andSize:96]
                                         placeholderImage:nil
                                                  success:nil
                                                  failure:nil];
                cell.contactImage.layer.cornerRadius = 24.0;
                cell.contactImage.layer.masksToBounds = YES;
            }
            
            // Online status
            if (participant.isOffline) {
                cell.contactImage.alpha = 0.5;
                cell.labelTitle.alpha = 0.5;
            } else {
                cell.contactImage.alpha = 1;
                cell.labelTitle.alpha = 1;
            }
            
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
            if (_room.canModerate) {
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
            } else {
                [self shareRoomLink];
            }
        }
            break;
        case kCreationSectionParticipants:
        {
            NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
            if (participant.participantType != kNCParticipantTypeOwner && ![self isAppUser:participant] && _room.canModerate) {
                [self showModerationOptionsForParticipantAtIndexPath:indexPath];
            }
        }
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
