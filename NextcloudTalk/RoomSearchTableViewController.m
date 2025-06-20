/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "RoomSearchTableViewController.h"

@import NextcloudKit;

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCRoom.h"
#import "NCSettingsController.h"
#import "PlaceholderView.h"

#import "NextcloudTalk-Swift.h"

typedef enum RoomSearchSection {
    RoomSearchSectionFiltered = 0,
    RoomSearchSectionUsers,
    RoomSearchSectionListable,
    RoomSearchSectionMessages
} RoomSearchSection;

@interface RoomSearchTableViewController ()
{
    PlaceholderView *_roomSearchBackgroundView;
}
@end

@implementation RoomSearchTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:RoomTableViewCell.nibName bundle:nil] forCellReuseIdentifier:RoomTableViewCell.identifier];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = UITableViewAutomaticDimension;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Align header's title to ContactsTableViewCell's label
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 52, 0, 0);
    self.tableView.separatorInsetReference = UITableViewSeparatorInsetFromAutomaticInsets;
    // Contacts placeholder view
    _roomSearchBackgroundView = [[PlaceholderView alloc] initForTableViewStyle:UITableViewStyleInsetGrouped];
    [_roomSearchBackgroundView setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomSearchBackgroundView.placeholderTextView setText:NSLocalizedString(@"No results found", nil)];
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
    [self reloadAndCheckSearchingIndicator];
}

- (void)setUsers:(NSArray *)users
{
    _users = users;
    [self reloadAndCheckSearchingIndicator];
}

- (void)setListableRooms:(NSArray *)listableRooms
{
    _listableRooms = listableRooms;
    [self reloadAndCheckSearchingIndicator];
}

- (void)setMessages:(NSArray *)messages
{
    _messages = messages;
    [self reloadAndCheckSearchingIndicator];
}

- (void)setSearchingMessages:(BOOL)searchingMessages
{
    _searchingMessages = searchingMessages;
    [self reloadAndCheckSearchingIndicator];
}


#pragma mark - User Interface

- (void)reloadAndCheckSearchingIndicator
{
    [self.tableView reloadData];
    
    if (_searchingMessages) {
        if ([self searchSections].count > 0) {
            [_roomSearchBackgroundView.loadingView stopAnimating];
            [_roomSearchBackgroundView.loadingView setHidden:YES];
            [self showSearchingFooterView];
        } else {
            [_roomSearchBackgroundView.loadingView startAnimating];
            [_roomSearchBackgroundView.loadingView setHidden:NO];
            [self hideSearchingFooterView];
        }
        [_roomSearchBackgroundView.placeholderView setHidden:YES];
    } else {
        [_roomSearchBackgroundView.loadingView stopAnimating];
        [_roomSearchBackgroundView.loadingView setHidden:YES];
        [_roomSearchBackgroundView.placeholderView setHidden:[self searchSections].count > 0];
    }
}

- (void)showSearchingFooterView
{
    UIActivityIndicatorView *loadingMoreView = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    loadingMoreView.color = [UIColor darkGrayColor];
    [loadingMoreView startAnimating];
    self.tableView.tableFooterView = loadingMoreView;
}

- (void)hideSearchingFooterView
{
    self.tableView.tableFooterView = nil;
}

- (void)clearSearchedResults
{
    _rooms = @[];
    _users = @[];
    _listableRooms = @[];
    _messages = @[];
    
    [self reloadAndCheckSearchingIndicator];
}


#pragma mark - Utils

- (NSArray *)searchSections
{
    NSMutableArray *sections = [NSMutableArray new];
    if (_rooms.count > 0) {
        [sections addObject:@(RoomSearchSectionFiltered)];
    }
    if (_users.count > 0) {
        [sections addObject:@(RoomSearchSectionUsers)];
    }
    if (_listableRooms.count > 0) {
        [sections addObject:@(RoomSearchSectionListable)];
    }
    if (_messages.count > 0) {
        [sections addObject:@(RoomSearchSectionMessages)];
    }
    return [NSArray arrayWithArray:sections];
}

- (NCRoom *)roomForIndexPath:(NSIndexPath *)indexPath
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:indexPath.section] integerValue];
    if (searchSection == RoomSearchSectionFiltered && indexPath.row < _rooms.count) {
        return [_rooms objectAtIndex:indexPath.row];
    } else if (searchSection == RoomSearchSectionListable && indexPath.row < _listableRooms.count) {
        return [_listableRooms objectAtIndex:indexPath.row];
    }
    
    return nil;
}

- (NKSearchEntry *)messageForIndexPath:(NSIndexPath *)indexPath
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:indexPath.section] integerValue];
    if (searchSection == RoomSearchSectionMessages && indexPath.row < _messages.count) {
        return [_messages objectAtIndex:indexPath.row];;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForMessageAtIndexPath:(NSIndexPath *)indexPath
{
    NKSearchEntry *messageEntry = [_messages objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RoomTableViewCell.identifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RoomTableViewCell.identifier];
    }
    
    cell.titleLabel.text = messageEntry.title;
    cell.subtitleLabel.text = messageEntry.subline;
    
    // Thumbnail image
    NSURL *thumbnailURL = [[NSURL alloc] initWithString:messageEntry.thumbnailURL];
    NSString *actorId = [messageEntry.attributes objectForKey:@"actorId"];
    NSString *actorType = [messageEntry.attributes objectForKey:@"actorType"];
    if (thumbnailURL && thumbnailURL.absoluteString.length > 0) {
        [cell.avatarView.avatarImageView sd_setImageWithURL:thumbnailURL placeholderImage:nil options:SDWebImageRetryFailed | SDWebImageRefreshCached];
        cell.avatarView.avatarImageView.contentMode = UIViewContentModeScaleToFill;
    } else {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        [cell.avatarView setActorAvatarForId:actorId withType:actorType withDisplayName:@"" withRoomToken:nil using:activeAccount];
    }
    
    // Clear possible content not removed by cell reuse
    cell.dateLabel.text = @"";
    [cell setUnreadWithMessages:0 mentioned:NO groupMentioned:NO];

    // Add message date (if it is included in attributes)
    NSInteger timestamp = [[messageEntry.attributes objectForKey:@"timestamp"] integerValue];
    if (timestamp > 0) {
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:timestamp];
        cell.dateLabel.text = [NCUtils readableTimeOrDateFromDate:date];
    }
    
    return cell;
}

- (NCUser *)userForIndexPath:(NSIndexPath *)indexPath
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:indexPath.section] integerValue];
    if (searchSection == RoomSearchSectionUsers && indexPath.row < _users.count) {
        return [_users objectAtIndex:indexPath.row];
    }

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForUserAtIndexPath:(NSIndexPath *)indexPath
{
    NCUser *user = [_users objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RoomTableViewCell.identifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RoomTableViewCell.identifier];
    }

    // Clear possible content not removed by cell reuse
    cell.dateLabel.text = @"";
    [cell setUnreadWithMessages:0 mentioned:NO groupMentioned:NO];

    cell.titleLabel.text = user.name;
    cell.titleOnly = YES;
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [cell.avatarView setActorAvatarForId:user.userId withType:user.source withDisplayName:user.name withRoomToken:nil using:activeAccount];

    return cell;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self searchSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:section] integerValue];
    switch (searchSection) {
        case RoomSearchSectionFiltered:
            return _rooms.count;
        case RoomSearchSectionUsers:
            return _users.count;
        case RoomSearchSectionListable:
            return _listableRooms.count;
        case RoomSearchSectionMessages:
            return _messages.count;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:section] integerValue];
    switch (searchSection) {
        case RoomSearchSectionFiltered:
            return NSLocalizedString(@"Conversations", @"");
        case RoomSearchSectionUsers:
            return NSLocalizedString(@"Users", @"");
        case RoomSearchSectionListable:
            return NSLocalizedString(@"Open conversations", @"TRANSLATORS 'Open conversations' as a type of conversation. 'Open conversations' are conversations that can be found by other users");
        case RoomSearchSectionMessages:
            return NSLocalizedString(@"Messages", @"");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger searchSection = [[[self searchSections] objectAtIndex:indexPath.section] integerValue];
    // Messages
    if (searchSection == RoomSearchSectionMessages) {
        return [self tableView:tableView cellForMessageAtIndexPath:indexPath];
    }
    // Contacts
    if (searchSection == RoomSearchSectionUsers) {
        return [self tableView:tableView cellForUserAtIndexPath:indexPath];
    }
    
    NCRoom *room = [self roomForIndexPath:indexPath];
    
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RoomTableViewCell.identifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RoomTableViewCell.identifier];
    }
    
    // Set room name
    cell.titleLabel.text = room.displayName;
    
    // Set last activity
    if (room.lastMessageId || room.lastMessageProxiedJSONString) {
        cell.titleOnly = NO;
        cell.subtitleLabel.attributedText = room.lastMessageString;
    } else {
        cell.titleOnly = YES;
        cell.subtitleLabel.text = @"";
    }
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastActivity];
    cell.dateLabel.text = [NCUtils readableTimeOrDateFromDate:date];

    // Open conversations
    if (searchSection == RoomSearchSectionListable) {
        cell.titleOnly = NO;
        cell.subtitleLabel.text = room.roomDescription;
        cell.dateLabel.text = @"";
    }

    // Set unread messages
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag]) {
        BOOL mentioned = room.unreadMentionDirect || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        BOOL groupMentioned = room.unreadMention && !room.unreadMentionDirect;
        [cell setUnreadWithMessages:room.unreadMessages mentioned:mentioned groupMentioned:groupMentioned];
    } else {
        BOOL mentioned = room.unreadMention || room.type == kNCRoomTypeOneToOne || room.type == kNCRoomTypeFormerOneToOne;
        [cell setUnreadWithMessages:room.unreadMessages mentioned:mentioned groupMentioned:NO];
    }

    if (room.unreadMessages > 0) {
        // When there are unread messages, we need to show the subtitle at the moment
        cell.titleOnly = NO;
    }

    [cell.avatarView setAvatarFor:room];

    // Set favorite or call image
    if (room.hasCall) {
        [cell.avatarView.favoriteImageView setTintColor:[UIColor systemRedColor]];
        [cell.avatarView.favoriteImageView setImage:[UIImage systemImageNamed:@"video.fill"]];
    } else if (room.isFavorite) {
        [cell.avatarView.favoriteImageView setTintColor:[UIColor systemYellowColor]];
        [cell.avatarView.favoriteImageView setImage:[UIImage systemImageNamed:@"star.fill"]];
    }
    
    return cell;
}

@end
