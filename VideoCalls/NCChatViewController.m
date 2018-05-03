//
//  NCChatViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatViewController.h"

#import "ChatMessageTableViewCell.h"
#import "GroupedChatMessageTableViewCell.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCMessageTextView.h"
#import "NCRoomController.h"
#import "NCSettingsController.h"
#import "NSDate+DateTools.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

@interface NCChatViewController () <NCRoomControllerDelegate>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NCRoomController *roomController;
@property (nonatomic, strong) NSMutableArray *messages;

@end

@implementation NCChatViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.title = room.displayName;
        self.roomController = [[NCRoomController alloc] initWithDelegate:self inRoom:room];
        self.hidesBottomBarWhenPushed = YES;
        // Register a SLKTextView subclass, if you need any special appearance and/or behavior customisation.
        [self registerClassForTextView:[NCMessageTextView class]];
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [_roomController joinRoomWithCompletionBlock:nil];
    [self configureActionItems];
    
    self.bounces = NO;
    self.shakeToClearEnabled = YES;
    self.keyboardPanningEnabled = YES;
    self.shouldScrollToBottomAfterKeyboardShows = NO;
    self.inverted = NO;
    
    [self.rightButton setTitle:NSLocalizedString(@"Send", nil) forState:UIControlStateNormal];
    
    self.textInputbar.autoHideRightButton = YES;
    self.textInputbar.maxCharCount = 256;
    self.textInputbar.counterStyle = SLKCounterStyleSplit;
    self.textInputbar.counterPosition = SLKCounterPositionTop;
    self.textInputbar.translucent = NO;
    self.textInputbar.backgroundColor = [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1.0]; //f9f9f9
    
    [self.textInputbar.editorTitle setTextColor:[UIColor darkGrayColor]];
    [self.textInputbar.editorLeftButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    [self.textInputbar.editorRightButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ChatMessageCellIdentifier];
    [self.tableView registerClass:[GroupedChatMessageTableViewCell class] forCellReuseIdentifier:GroupedChatMessageCellIdentifier];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_roomController leaveRoomWithCompletionBlock:nil];
}

#pragma mark - Configuration

- (void)configureActionItems
{
    UIBarButtonItem *videoCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"videocall-action"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(videoCallButtonPressed:)];
    
    UIBarButtonItem *voiceCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"call-action"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(voiceCallButtonPressed:)];
    
    self.navigationItem.rightBarButtonItems = @[videoCallButton, voiceCallButton];
}

#pragma mark - Action Methods

- (void)videoCallButtonPressed:(id)sender
{
    
}

- (void)voiceCallButtonPressed:(id)sender
{
    
}

- (void)didPressRightButton:(id)sender
{
    // This little trick validates any pending auto-correction or auto-spelling just after hitting the 'Send' button
    [self.textView refreshFirstResponder];
    [_roomController sendChatMessage:[self.textView.text copy]];
    [super didPressRightButton:sender];
}

#pragma mark - Room Controller Delegate

- (void)roomController:(NCRoomController *)roomController didReceiveChatMessages:(NSMutableArray *)messages
{
    if (messages.count > 0) {
        if (!_messages) {
            _messages = [[NSMutableArray alloc] init];
        }
        
        NSMutableArray *sortedMessages = [self sortMessages:messages];
        NSMutableArray *indexPaths = [self createIndexPathArrayForMessages:sortedMessages];
        
        [self.tableView beginUpdates];
        [_messages addObjectsFromArray:sortedMessages];
        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationBottom];
        [self.tableView endUpdates];
        
        [self.tableView scrollToRowAtIndexPath:[indexPaths lastObject] atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }
}

- (NSMutableArray *)sortMessages:(NSMutableArray *)messages
{
    NSMutableArray *sortedMessages = [[NSMutableArray alloc] initWithArray:messages];
    
    NCChatMessage *firstMessage = [sortedMessages objectAtIndex:0];
    if (_messages.count > 0) {
        NCChatMessage *lastMessage = [_messages lastObject];
        if ([self shouldGroupMessage:firstMessage withMessage:lastMessage]) {
            firstMessage.groupMessage = YES;
            firstMessage.groupMessageNumber = lastMessage.groupMessageNumber + 1;
        }
        firstMessage.indexPath = [NSIndexPath indexPathForRow:lastMessage.indexPath.row + 1 inSection:0];
    } else {
        firstMessage.groupMessage = NO;
        firstMessage.groupMessageNumber = 0;
        firstMessage.indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    }
    
    for (int i = 1; i < messages.count; i++) {
        NCChatMessage *newMessage = [sortedMessages objectAtIndex:i];
        NCChatMessage *beforeMessage = [sortedMessages objectAtIndex:i -1];
        if ([self shouldGroupMessage:newMessage withMessage:beforeMessage]) {
            newMessage.groupMessage = YES;
            newMessage.groupMessageNumber = beforeMessage.groupMessageNumber + 1;
        }
        newMessage.indexPath = [NSIndexPath indexPathForRow:beforeMessage.indexPath.row + 1 inSection:0];
    }
    
    return sortedMessages;
}

- (NSMutableArray *)createIndexPathArrayForMessages:(NSMutableArray *)messages
{
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:messages.count];
    for (NCChatMessage *message in messages) {
        [indexPaths addObject:message.indexPath];
    }
    return indexPaths;
}

- (BOOL)shouldGroupMessage:(NCChatMessage *)newMessage withMessage:(NCChatMessage *)lastMessage
{
    BOOL sameActor = [newMessage.actorId isEqualToString:lastMessage.actorId];
    BOOL timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference;
    BOOL notMaxGroup = lastMessage.groupMessageNumber < kChatMessageMaxGroupNumber;
    
    // Check day change
    NSInteger lastMessageDay = [[NSCalendar currentCalendar] component:NSCalendarUnitDay fromDate:[NSDate dateWithTimeIntervalSince1970: lastMessage.timestamp]];
    NSInteger newMessageDay = [[NSCalendar currentCalendar] component:NSCalendarUnitDay fromDate:[NSDate dateWithTimeIntervalSince1970: newMessage.timestamp]];
    BOOL sameDay = lastMessageDay == newMessageDay;
    
    return sameActor & timeDiff & notMaxGroup & sameDay;
}

#pragma mark - UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCChatMessage *message = self.messages[indexPath.row];
    UITableViewCell *cell = [UITableViewCell new];
    
    if (message.groupMessage) {
        GroupedChatMessageTableViewCell *groupedCell = (GroupedChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:GroupedChatMessageCellIdentifier];
        groupedCell.bodyLabel.attributedText = message.parsedMessage;
        return groupedCell;
    } else {
        ChatMessageTableViewCell *normalCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ChatMessageCellIdentifier];
        normalCell.titleLabel.text = message.actorDisplayName;
        normalCell.bodyLabel.attributedText = message.parsedMessage;
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        normalCell.dateLabel.text = [date timeAgoSinceNow];
        // Request user avatar to the server and set it if exist
        [normalCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96]
                                     placeholderImage:nil success:nil failure:nil];
        return normalCell;
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.tableView]) {
        NCChatMessage *message = self.messages[indexPath.row];
        
        NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        paragraphStyle.alignment = NSTextAlignmentLeft;
        
        CGFloat pointSize = [ChatMessageTableViewCell defaultFontSize];
        
        NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:pointSize],
                                     NSParagraphStyleAttributeName: paragraphStyle};
        
        CGFloat width = CGRectGetWidth(tableView.frame) - kChatMessageCellAvatarHeight;
        width -= 25.0;
        
        CGRect titleBounds = [message.actorDisplayName boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
        CGRect bodyBounds = [message.message boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
        
        if (message.message.length == 0) {
            return 0.0;
        }
        
        CGFloat height = CGRectGetHeight(titleBounds);
        height += CGRectGetHeight(bodyBounds);
        height += 40.0;
        
        if (height < kChatMessageCellMinimumHeight) {
            height = kChatMessageCellMinimumHeight;
        }
        
        if (message.groupMessage) {
            height = CGRectGetHeight(bodyBounds) + 20;
            
            if (height < kGroupedChatMessageCellMinimumHeight) {
                height = kGroupedChatMessageCellMinimumHeight;
            }
        }
        
        return height;
    }
    else {
        return kChatMessageCellMinimumHeight;
    }
}

@end
