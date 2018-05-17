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
#import "DateHeaderView.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCChatMention.h"
#import "NCMessageTextView.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NSDate+DateTools.h"
#import "UIImageView+Letters.h"
#import "UIImageView+AFNetworking.h"

@interface NCChatViewController ()

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NSMutableDictionary *messages;
@property (nonatomic, strong) NSMutableArray *dateSections;
@property (nonatomic, strong) NSMutableArray *mentions;
@property (nonatomic, strong) NSMutableArray *autocompletionUsers;

@end

@implementation NCChatViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.title = room.displayName;
        self.hidesBottomBarWhenPushed = YES;
        // Register a SLKTextView subclass, if you need any special appearance and/or behavior customisation.
        [self registerClassForTextView:[NCMessageTextView class]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatMessages:) name:NCRoomsManagerDidReceiveChatMessagesNotification object:nil];
    }
    
    return self;
}
    
- (void)dealloc
{
    [[NCRoomsManager sharedInstance] leaveRoom:_room];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NCRoomsManager sharedInstance] joinRoom:_room];
    [self configureActionItems];
    
    self.messages = [[NSMutableDictionary alloc] init];
    self.mentions = [[NSMutableArray alloc] init];
    self.dateSections = [[NSMutableArray alloc] init];
    
    self.bounces = NO;
    self.shakeToClearEnabled = YES;
    self.keyboardPanningEnabled = YES;
    self.shouldScrollToBottomAfterKeyboardShows = YES;
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
    [self.autoCompletionView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:AutoCompletionCellIdentifier];
    [self registerPrefixesForAutoCompletion:@[@"@"]];
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

#pragma mark - Utils

- (NSString *)getTimeFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm"];
    return [formatter stringFromDate:date];
}

- (NSString *)getHeaderStringFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)createSendingMessage:(NSString *)text
{
    NSString *sendingMessage = [text copy];
    for (NCChatMention *mention in _mentions) {
        sendingMessage = [sendingMessage stringByReplacingOccurrencesOfString:mention.name withString:mention.userId];
    }
    _mentions = [[NSMutableArray alloc] init];
    return sendingMessage;
}

#pragma mark - Action Methods

- (void)videoCallButtonPressed:(id)sender
{
    [[NCRoomsManager sharedInstance] startCall:YES inRoom:_room];
}

- (void)voiceCallButtonPressed:(id)sender
{
    [[NCRoomsManager sharedInstance] startCall:NO inRoom:_room];
}

- (void)didPressRightButton:(id)sender
{
    NSString *sendingText = [self createSendingMessage:self.textView.text];
    [[NCRoomsManager sharedInstance] sendChatMessage:sendingText toRoom:_room];
    [super didPressRightButton:sender];
}

#pragma mark - UITextViewDelegate Methods

- (BOOL)textView:(SLKTextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@""]) {
        UITextRange *selectedRange = [textView selectedTextRange];
        NSInteger cursorOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:selectedRange.start];
        NSString *text = textView.text;
        NSString *substring = [text substringToIndex:cursorOffset];
        NSMutableString *lastPossibleMention = [[[substring componentsSeparatedByString:@"@"] lastObject] mutableCopy];
        [lastPossibleMention insertString:@"@" atIndex:0];
        for (NCChatMention *mention in _mentions) {
            if ([lastPossibleMention isEqualToString:mention.name]) {
                // Delete mention
                textView.text =  [[self.textView text] stringByReplacingOccurrencesOfString:lastPossibleMention withString:@""];
                [_mentions removeObject:mention];
                return NO;
            }
        }
    }
    
    return [super textView:textView shouldChangeTextInRange:range replacementText:text];
}

#pragma mark - Room Manager notifications

- (void)didReceiveChatMessages:(NSNotification *)notification
{
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    NSInteger lastSectionBeforeUpdate = _dateSections.count - 1;
    BOOL singleMessage = (messages.count == 1);
    if (messages.count > 1) {
        [self sortNewMessages:messages];
        [self.tableView reloadData];
    } else if (singleMessage) {
        [self.tableView beginUpdates];
        NSMutableArray *indexPaths = [self sortNewMessages:messages];
        NSIndexPath *newMessageIndexPath = [indexPaths objectAtIndex:0];
        BOOL newSection = lastSectionBeforeUpdate != newMessageIndexPath.section;
        if (newSection) {
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:newMessageIndexPath.section] withRowAnimation:UITableViewRowAnimationNone];
        } else {
            [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
        }
        [self.tableView endUpdates];
    } else {
        // No new messages received
        return;
    }
    
    NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
    NCChatMessage *lastMessage = [messagesForLastDate lastObject];
    [self.tableView scrollToRowAtIndexPath:lastMessage.indexPath atScrollPosition:UITableViewScrollPositionNone animated:singleMessage];
}

- (NSDate *)getDictKeyForDate:(NSDate *)date
{
    NSDate *keyDate = nil;
    for (NSDate *key in _messages.allKeys) {
        if ([[NSCalendar currentCalendar] isDate:date inSameDayAsDate:key]) {
            keyDate = key;
        }
    }
    return keyDate;
}

- (NSMutableArray *)sortNewMessages:(NSMutableArray *)newMessages
{
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:newMessages.count];
    
    for (NCChatMessage *newMessage in newMessages) {
        NSDate *newMessageDate = [NSDate dateWithTimeIntervalSince1970: newMessage.timestamp];
        NSDate *keyDate = [self getDictKeyForDate:newMessageDate];
        NSMutableArray *messagesForDate = [_messages objectForKey:keyDate];
        if (messagesForDate) {
            NCChatMessage *lastMessage = [messagesForDate lastObject];
            if ([self shouldGroupMessage:newMessage withMessage:lastMessage]) {
                newMessage.groupMessage = YES;
                newMessage.groupMessageNumber = lastMessage.groupMessageNumber + 1;
            }
            newMessage.indexPath = [NSIndexPath indexPathForRow:lastMessage.indexPath.row + 1 inSection:[_dateSections indexOfObject:keyDate]];
            [messagesForDate addObject:newMessage];
        } else {
            NSMutableArray *newMessagesInDate = [NSMutableArray new];
            [_messages setObject:newMessagesInDate forKey:newMessageDate];
            [self sortDateSections];
            newMessage.indexPath = [NSIndexPath indexPathForRow:0 inSection:[_dateSections indexOfObject:newMessageDate]];
            [newMessagesInDate addObject:newMessage];
        }
        
        [indexPaths addObject:newMessage.indexPath];
    }
    
    [indexPaths sortUsingSelector:@selector(compare:)];
    return indexPaths;
}

- (void)sortDateSections
{
    _dateSections = [NSMutableArray arrayWithArray:_messages.allKeys];
    [_dateSections sortUsingSelector:@selector(compare:)];
}

- (BOOL)shouldGroupMessage:(NCChatMessage *)newMessage withMessage:(NCChatMessage *)lastMessage
{
    BOOL sameActor = [newMessage.actorId isEqualToString:lastMessage.actorId];
    BOOL timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference;
    BOOL notMaxGroup = lastMessage.groupMessageNumber < kChatMessageMaxGroupNumber;
    
    return sameActor & timeDiff & notMaxGroup;
}

#pragma mark - Autocompletion

- (void)didChangeAutoCompletionPrefix:(NSString *)prefix andWord:(NSString *)word
{
    if ([prefix isEqualToString:@"@"]) {
        [self showSuggestionsForString:word];
    }
}

- (CGFloat)heightForAutoCompletionView
{
    return kChatMessageCellMinimumHeight * self.autocompletionUsers.count;
}

- (void)showSuggestionsForString:(NSString *)string
{
    self.autocompletionUsers = nil;
    [[NCAPIController sharedInstance] getMentionSuggestionsInRoom:_room.token forString:string withCompletionBlock:^(NSMutableArray *mentions, NSError *error) {
        if (!error) {
            self.autocompletionUsers = [[NSMutableArray alloc] initWithArray:mentions];
            BOOL show = (self.autocompletionUsers.count > 0);
            // Check if the '@' is still there
            [self.textView lookForPrefixes:self.registeredPrefixes completion:^(NSString *prefix, NSString *word, NSRange wordRange) {
                if (prefix.length > 0 && word.length > 0) {
                    [self showAutoCompletionView:show];
                } else {
                    [self cancelAutoCompletion];
                }
            }];
        }
    }];
}

#pragma mark - UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return 1;
    }
    
    return _dateSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return _autocompletionUsers.count;
    }
    
    NSDate *date = [_dateSections objectAtIndex:section];
    NSMutableArray *messages = [_messages objectForKey:date];
    return messages.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return nil;
    }
    
    NSDate *date = [_dateSections objectAtIndex:section];
    return [self getHeaderStringFromDate:date];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return 0;
    }
    
    return kDateHeaderViewHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return nil;
    }
    
    DateHeaderView *headerView = [[DateHeaderView alloc] init];
    headerView.dateLabel.text = [self tableView:tableView titleForHeaderInSection:section];
    headerView.dateLabel.layer.cornerRadius = 12;
    headerView.dateLabel.clipsToBounds = YES;
    
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        NSDictionary *suggestion = [_autocompletionUsers objectAtIndex:indexPath.row];
        NSString *suggestionId = [suggestion objectForKey:@"id"];
        NSString *suggestionName = [suggestion objectForKey:@"label"];
        ChatMessageTableViewCell *suggestionCell = (ChatMessageTableViewCell *)[self.autoCompletionView dequeueReusableCellWithIdentifier:AutoCompletionCellIdentifier];
        suggestionCell.titleLabel.text = suggestionName;
        // Request user avatar to the server and set it if exist
        [suggestionCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:suggestionId andSize:96]
                                     placeholderImage:nil success:nil failure:nil];
        return suggestionCell;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    
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
        normalCell.dateLabel.text = [self getTimeFromDate:date];
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
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        NCChatMention *mention = [[NCChatMention alloc] init];
        mention.userId = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        mention.name = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"label"]];
        [_mentions addObject:mention];
        
        NSMutableString *mentionString = [[self.autocompletionUsers[indexPath.row] objectForKey:@"label"] mutableCopy];
        [mentionString appendString:@" "];
        [self acceptAutoCompletionWithString:mentionString keepPrefix:YES];
    }
}

@end
