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
    kCreationSectionPublic,
    kCreationSectionParticipants,
    kCreationSectionNumber
} CreationSection;

typedef enum PublicSection {
    kPublicSectionToggle = 0,
    kPublicSectionPassword
} PublicSection;

@interface RoomCreation2TableViewController ()

@property (nonatomic, strong) NSMutableArray *participants;
@property (nonatomic, strong) UISwitch *publicSwtich;
@property (nonatomic, strong) UITextField *passwordTextField;

@end

@implementation RoomCreation2TableViewController

- (instancetype)initWithParticipants:(NSMutableArray *)participants
{
    self = [super init];
    if (self) {
        _participants = participants;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = @"New conversation";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    _publicSwtich = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_publicSwtich addTarget: self action: @selector(publicValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _passwordTextField = [[UITextField alloc] initWithFrame:CGRectMake(180, 10, 115, 30)];
    _passwordTextField.textAlignment = NSTextAlignmentRight;
    _passwordTextField.placeholder = @"No password";
    _passwordTextField.adjustsFontSizeToFitWidth = YES;
    _passwordTextField.textColor = [UIColor blackColor];
    _passwordTextField.secureTextEntry = YES;
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Video disabled switch

- (void)publicValueChanged:(id)sender
{
    BOOL isPublic = _publicSwtich.on;
    [self.tableView beginUpdates];
    // Reload room name section
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    // Show/Hide password row
    NSIndexPath *passwordIP = [NSIndexPath indexPathForRow:kPublicSectionPassword inSection:kCreationSectionPublic];
    NSArray *indexArray = [NSArray arrayWithObjects:passwordIP,nil];
    if (isPublic) {
        [self.tableView insertRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView deleteRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.tableView endUpdates];
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
            return _participants.count;
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
            return [NSString stringWithFormat:@"%ld participants", _participants.count];
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
            
            cell.userInteractionEnabled = YES;
            if (_publicSwtich.on) {
                [cell.roomImage setImage:[UIImage imageNamed:@"public-bg"]];
            } else {
                [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
            }
            
            if (_participants.count == 1) {
                NCUser *participant = [_participants objectAtIndex:indexPath.row];
                cell.roomNameTextField.text = participant.name;
                // Create avatar for every contact
                [cell.roomImage setImageWithString:participant.name color:nil circular:true];
                // Request user avatar to the server and set it if exist
                [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.userId andSize:96]
                                         placeholderImage:nil
                                                  success:nil
                                                  failure:nil];
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
                        
                        cell.textLabel.text = @"Public conversation";
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                        cell.accessoryView = _publicSwtich;
                        
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
                        
                        return cell;
                    }
                    break;
            }
        }
            break;
        case kCreationSectionParticipants:
        {
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
            
            return cell;
        }
            break;
    }
    
    return cell;
}

@end
