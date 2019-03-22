//
//  RoomSearchTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 01.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "RoomSearchTableViewController.h"

#import "NCAPIController.h"
#import "NCRoom.h"
#import "NCSettingsController.h"
#import "NSDate+DateTools.h"
#import "PlaceholderView.h"
#import "RoomTableViewCell.h"
#import "UIImageView+AFNetworking.h"

@interface RoomSearchTableViewController ()
{
    PlaceholderView *_roomSearchBackgroundView;
}
@end

@implementation RoomSearchTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomCellIdentifier];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Contacts placeholder view
    _roomSearchBackgroundView = [[PlaceholderView alloc] init];
    [_roomSearchBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomSearchBackgroundView.placeholderText setText:@"No results found."];
    [_roomSearchBackgroundView.placeholderView setHidden:YES];
    [_roomSearchBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _roomSearchBackgroundView;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setRooms:(NSArray *)rooms
{
    _rooms = rooms;
    [_roomSearchBackgroundView.loadingView stopAnimating];
    [_roomSearchBackgroundView.loadingView setHidden:YES];
    [_roomSearchBackgroundView.placeholderView setHidden:(rooms.count > 0)];
}

#pragma mark - Utils

- (NSString *)getDateLabelStringForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    if ([date isToday]) {
        [formatter setDateFormat:@"HH:mm"];
    } else if ([date isYesterday]) {
        return @"Yesterday";
    } else {
        [formatter setDateFormat:@"dd/MM/yy"];
    }
    return [formatter stringFromDate:date];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rooms.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kRoomTableCellHeight;
}

//- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
//{
//    return [_indexes objectAtIndex:section];
//}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomCellIdentifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomCellIdentifier];
    }
    
    // Set room name
    cell.titleLabel.text = room.displayName;
    
    if ([[NCSettingsController sharedInstance]serverHasTalkCapability:kCapabilityLastRoomActivity]) {
        // Set last activity
        NCChatMessage *lastMessage = room.lastMessage;
        if (lastMessage) {
            cell.titleOnly = NO;
            cell.subtitleLabel.attributedText = room.lastMessageString;
        } else {
            cell.titleOnly = YES;
        }
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastActivity];
        cell.dateLabel.text = [self getDateLabelStringForDate:date];
    } else {
        // Set last ping
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastPing];
        cell.subtitleLabel.text = [date timeAgoSinceNow];
        if (room.lastPing == 0) {
            cell.subtitleLabel.text = @"Never joined";
        }
    }
    
    // Set unread messages
    BOOL mentioned = NO;
    if ([[NCSettingsController sharedInstance]serverHasTalkCapability:kCapabilityMentionFlag]) {
        mentioned = room.unreadMention ? YES : NO;
    }
    [cell setUnreadMessages:room.unreadMessages mentioned:mentioned];
    
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOneCall:
            [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name andSize:96]
                                  placeholderImage:nil success:nil failure:nil];
            break;
            
        case kNCRoomTypeGroupCall:
            [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
            break;
            
        case kNCRoomTypePublicCall:
            [cell.roomImage setImage:(room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
            break;
            
        default:
            break;
    }
    
    // Set objectType image
    if ([room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [cell.roomImage setImage:[UIImage imageNamed:@"file-bg"]];
    } else if ([room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [cell.roomImage setImage:[UIImage imageNamed:@"password-bg"]];
    }
    
    // Set favorite image
    if (room.isFavorite) {
        [cell.favoriteImage setImage:[UIImage imageNamed:@"favorite-room"]];
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

@end
