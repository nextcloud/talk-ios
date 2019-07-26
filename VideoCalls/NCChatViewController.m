//
//  NCChatViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatViewController.h"

#import "AFImageDownloader.h"
#import "CallKitManager.h"
#import "ChatMessageTableViewCell.h"
#import "DirectoryTableViewController.h"
#import "GroupedChatMessageTableViewCell.h"
#import "FileMessageTableViewCell.h"
#import "SystemMessageTableViewCell.h"
#import "DateHeaderView.h"
#import "PlaceholderView.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCMessageParameter.h"
#import "NCChatTitleView.h"
#import "NCMessageTextView.h"
#import "NCFilePreviewSessionManager.h"
#import "NCRoomsManager.h"
#import "NCRoomController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "NSDate+DateTools.h"
#import "RoomInfoTableViewController.h"
#import "UIImageView+AFNetworking.h"

@interface NCChatViewController ()

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NCRoomController *roomController;
@property (nonatomic, strong) NCChatTitleView *titleView;
@property (nonatomic, strong) PlaceholderView *chatBackgroundView;
@property (nonatomic, strong) NSMutableDictionary *messages;
@property (nonatomic, strong) NSMutableArray *dateSections;
@property (nonatomic, strong) NSMutableArray *mentions;
@property (nonatomic, strong) NSMutableArray *autocompletionUsers;
@property (nonatomic, assign) BOOL hasReceiveInitialHistory;
@property (nonatomic, assign) BOOL retrievingHistory;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) BOOL hasJoinedRoom;
@property (nonatomic, strong) UIActivityIndicatorView *loadingHistoryView;
@property (nonatomic, assign) NSIndexPath *firstUnreadMessageIP;
@property (nonatomic, strong) UIButton *unreadMessageButton;
@property (nonatomic, strong) UIBarButtonItem *videoCallButton;
@property (nonatomic, strong) UIBarButtonItem *voiceCallButton;
@property (nonatomic, strong) NSTimer *lobbyCheckTimer;

@end

@implementation NCChatViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.hidesBottomBarWhenPushed = YES;
        // Fixes problem with tableView contentSize on iOS 11
        self.tableView.estimatedRowHeight = 0;
        self.tableView.estimatedSectionHeaderHeight = 0;
        // Register a SLKTextView subclass, if you need any special appearance and/or behavior customisation.
        [self registerClassForTextView:[NCMessageTextView class]];
        // Set image downloader to file preview imageviews.
        AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                              initWithSessionManager:[NCFilePreviewSessionManager sharedInstance]
                                              downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                              maximumActiveDownloads:4
                                              imageCache:[[AFAutoPurgingImageCache alloc] init]];
        [FilePreviewImageView setSharedImageDownloader:imageDownloader];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveInitialChatHistory:) name:NCRoomControllerDidReceiveInitialChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatHistory:) name:NCRoomControllerDidReceiveChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatMessages:) name:NCRoomControllerDidReceiveChatMessagesNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSendChatMessage:) name:NCRoomControllerDidSendChatMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatBlocked:) name:NCRoomControllerDidReceiveChatBlockedNotification object:nil];
    }
    
    return self;
}
    
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.titleView = [[NCChatTitleView alloc] init];
    self.titleView.frame = CGRectMake(0, 0, 800, 30);
    self.titleView.autoresizingMask=UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.titleView.title addTarget:self action:@selector(titleButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.titleView = _titleView;
    [self setTitleView];
    [self configureActionItems];
    
    // Disable room info and call buttons until joining the room
    _titleView.userInteractionEnabled = NO;
    [_videoCallButton setEnabled:NO];
    [_voiceCallButton setEnabled:NO];
    
    self.messages = [[NSMutableDictionary alloc] init];
    self.mentions = [[NSMutableArray alloc] init];
    self.dateSections = [[NSMutableArray alloc] init];
    
    self.bounces = NO;
    self.shakeToClearEnabled = YES;
    self.keyboardPanningEnabled = YES;
    self.shouldScrollToBottomAfterKeyboardShows = YES;
    self.inverted = NO;
    
    [self.rightButton setTitle:@"" forState:UIControlStateNormal];
    [self.rightButton setImage:[UIImage imageNamed:@"send"] forState:UIControlStateNormal];
    [self.leftButton setImage:[UIImage imageNamed:@"add"] forState:UIControlStateNormal];
    
    self.textInputbar.autoHideRightButton = NO;
    NSInteger chatMaxLength = [[NCSettingsController sharedInstance] chatMaxLengthConfigCapability];
    self.textInputbar.maxCharCount = chatMaxLength;
    self.textInputbar.counterStyle = SLKCounterStyleLimitExceeded;
    self.textInputbar.counterPosition = SLKCounterPositionTop;
    // Only show char counter when chat is limited to 1000 chars
    if (chatMaxLength == kDefaultChatMaxLength) {
        self.textInputbar.counterStyle = SLKCounterStyleCountdownReversed;
    }
    self.textInputbar.translucent = NO;
    self.textInputbar.backgroundColor = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0]; //Default color
    
    [self.textInputbar.editorTitle setTextColor:[UIColor darkGrayColor]];
    [self.textInputbar.editorLeftButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    [self.textInputbar.editorRightButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ChatMessageCellIdentifier];
    [self.tableView registerClass:[GroupedChatMessageTableViewCell class] forCellReuseIdentifier:GroupedChatMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:FileMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:GroupedFileMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:SystemMessageCellIdentifier];
    [self.autoCompletionView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:AutoCompletionCellIdentifier];
    [self registerPrefixesForAutoCompletion:@[@"@"]];
    
    // Chat placeholder view
    _chatBackgroundView = [[PlaceholderView alloc] init];
    [_chatBackgroundView.placeholderView setHidden:YES];
    [_chatBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _chatBackgroundView;
    
    // Unread messages indicator
    _firstUnreadMessageIP = nil;
    _unreadMessageButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 126, 24)];
    _unreadMessageButton.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1]; //#0082C9
    _unreadMessageButton.titleLabel.font = [UIFont systemFontOfSize:12];
    _unreadMessageButton.layer.cornerRadius = 12;
    _unreadMessageButton.clipsToBounds = YES;
    _unreadMessageButton.hidden = YES;
    _unreadMessageButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_unreadMessageButton addTarget:self action:@selector(unreadMessagesButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_unreadMessageButton setTitle:@"↓ New messages" forState:UIControlStateNormal];
    
    [self.view addSubview:_unreadMessageButton];
    
    NSDictionary *views = @{@"unreadMessagesButton": _unreadMessageButton,
                            @"textInputbar": self.textInputbar};
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[unreadMessagesButton(24)]-5-[textInputbar]" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[unreadMessagesButton(126)]-(>=0)-|" options:0 metrics:nil views:views]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual
                                                             toItem:_unreadMessageButton attribute:NSLayoutAttributeCenterX multiplier:1.f constant:0.f]];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self checkRoomControlsAvailability];
    
    _isVisible = YES;
    
    [[NCRoomsManager sharedInstance] joinRoom:_room.token];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    _isVisible = NO;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // Leave chat when the view controller has been removed from its parent view.
    if (self.isMovingFromParentViewController) {
        [_lobbyCheckTimer invalidate];
        [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
    }
}

#pragma mark - Configuration

- (void)setTitleView
{
    [_titleView.title setTitle:_room.displayName forState:UIControlStateNormal];
    
    // Set room image
    switch (_room.type) {
        case kNCRoomTypeOneToOne:
        {
            // Request user avatar to the server and set it if exist
            [_titleView.image setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96]
                                    placeholderImage:nil success:nil failure:nil];
        }
            break;
        case kNCRoomTypeGroup:
            [_titleView.image setImage:[UIImage imageNamed:@"group-bg"]];
            break;
        case kNCRoomTypePublic:
            [_titleView.image setImage:(_room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
            break;
        case kNCRoomTypeChangelog:
            [_titleView.image setImage:[UIImage imageNamed:@"changelog"]];
            break;
        default:
            break;
    }
    
    // Set objectType image
    if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [_titleView.image setImage:[UIImage imageNamed:@"file-bg"]];
    } else if ([_room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [_titleView.image setImage:[UIImage imageNamed:@"password-bg"]];
    }
}

- (void)configureActionItems
{
    _videoCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"videocall-action"]
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(videoCallButtonPressed:)];
    
    _voiceCallButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"call-action"]
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(voiceCallButtonPressed:)];
    
    self.navigationItem.rightBarButtonItems = @[_videoCallButton, _voiceCallButton];
}

#pragma mark - User Interface

- (void)checkRoomControlsAvailability
{
    if (_hasJoinedRoom) {
        // Enable room info and call buttons
        _titleView.userInteractionEnabled = YES;
        [_videoCallButton setEnabled:YES];
        [_voiceCallButton setEnabled:YES];
    }
    
    if (_room.readOnlyState == NCRoomReadOnlyStateReadOnly || [self shouldPresentLobbyView]) {
        // Hide text input
        self.textInputbarHidden = YES;
        // Disable call buttons
        [_videoCallButton setEnabled:NO];
        [_voiceCallButton setEnabled:NO];
    } else if ([self isTextInputbarHidden]) {
        // Show text input if it was hidden in a previous state
        [self setTextInputbarHidden:NO animated:YES];
    }
}

- (void)checkLobbyState
{
    if ([self shouldPresentLobbyView]) {
        [_chatBackgroundView.placeholderText setText:@"You are currently waiting in the lobby."];
        [_chatBackgroundView.placeholderView setHidden:NO];
        [_chatBackgroundView.loadingView stopAnimating];
        [_chatBackgroundView.loadingView setHidden:YES];
        // Clear current chat since chat history will be retrieve when lobby is disabled
        _messages = [[NSMutableDictionary alloc] init];
        _dateSections = [[NSMutableArray alloc] init];
        _hasReceiveInitialHistory = NO;
        [self hideNewMessagesView];
        [self.tableView reloadData];
    } else {
        [_chatBackgroundView.placeholderText setText:@"No messages yet, start the conversation!"];
        [_chatBackgroundView.placeholderView setHidden:YES];
        [_chatBackgroundView.loadingView startAnimating];
        [_chatBackgroundView.loadingView setHidden:NO];
        // Stop checking lobby flag
        [_lobbyCheckTimer invalidate];
        // Retrieve initial chat history
        if (!_hasReceiveInitialHistory) {
            [_roomController getInitialChatHistory];
        }
    }
    [self checkRoomControlsAvailability];
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
    formatter.doesRelativeDateFormatting = YES;
    return [formatter stringFromDate:date];
}

- (NSString *)createSendingMessage:(NSString *)text
{
    NSString *sendingMessage = [text copy];
    for (NCMessageParameter *mention in _mentions) {
        sendingMessage = [sendingMessage stringByReplacingOccurrencesOfString:mention.name withString:mention.parameterId];
    }
    _mentions = [[NSMutableArray alloc] init];
    return sendingMessage;
}

- (void)presentJoinRoomError
{
    NSString *alertTitle = [NSString stringWithFormat:@"Could not join %@", _room.displayName];
    if (_room.type == kNCRoomTypeOneToOne) {
        alertTitle = [NSString stringWithFormat:@"Could not join conversation with %@", _room.displayName];
    }
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                    message:@"An error occurred while joining the conversation"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okButton = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
                                                         [self.navigationController popViewControllerAnimated:YES];
                                                     }];
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

#pragma mark - Action Methods

- (void)titleButtonPressed:(id)sender
{
    RoomInfoTableViewController *roomInfoVC = [[RoomInfoTableViewController alloc] initForRoom:_room];
    [self.navigationController pushViewController:roomInfoVC animated:YES];
}

- (void)unreadMessagesButtonPressed:(id)sender
{
    if (_firstUnreadMessageIP) {
        [self.tableView scrollToRowAtIndexPath:_firstUnreadMessageIP atScrollPosition:UITableViewScrollPositionNone animated:YES];
    }
}

- (void)videoCallButtonPressed:(id)sender
{
    [[CallKitManager sharedInstance] startCall:_room.token withVideoEnabled:YES andDisplayName:_room.displayName];
}

- (void)voiceCallButtonPressed:(id)sender
{
    [[CallKitManager sharedInstance] startCall:_room.token withVideoEnabled:NO andDisplayName:_room.displayName];
}

- (void)didPressRightButton:(id)sender
{
    NSString *sendingText = [self createSendingMessage:self.textView.text];
    [[NCRoomsManager sharedInstance] sendChatMessage:sendingText toRoom:_room];
    [super didPressRightButton:sender];
}

- (void)didPressLeftButton:(id)sender
{
    DirectoryTableViewController *directoryVC = [[DirectoryTableViewController alloc] initWithPath:@"" inRoom:_room.token];
    UINavigationController *fileSharingNC = [[UINavigationController alloc] initWithRootViewController:directoryVC];
    [self presentViewController:fileSharingNC animated:YES completion:nil];
    [super didPressLeftButton:sender];
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if ([scrollView isEqual:self.tableView] && scrollView.contentOffset.y < 0) {
        if ([self shouldRetireveHistory]) {
            _retrievingHistory = YES;
            [self showLoadingHistoryView];
            NSDate *dateSection = [_dateSections objectAtIndex:0];
            NCChatMessage *firstMessage = [[_messages objectForKey:dateSection] objectAtIndex:0];
            [_roomController getChatHistoryFromMessagesId:firstMessage.messageId];
        }
    }
    
    if (_firstUnreadMessageIP) {
        [self checkUnreadMessagesVisibility];
    }
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
        for (NCMessageParameter *mention in _mentions) {
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

- (void)didUpdateRoom:(NSNotification *)notification
{
    NCRoom *room = [notification.userInfo objectForKey:@"room"];
    if (!room || ![room.token isEqualToString:_room.token]) {
        return;
    }
    
    _room = room;
    [self setTitleView];
    [self checkLobbyState];
}

- (void)didJoinRoom:(NSNotification *)notification
{
    NSString *token = [notification.userInfo objectForKey:@"token"];
    if (![token isEqualToString:_room.token]) {
        return;
    }
    
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (error && _isVisible) {
        [self presentJoinRoomError];
        return;
    }
    
    _hasJoinedRoom = YES;
    [self checkRoomControlsAvailability];
    
    NCRoomController *roomController = [notification.userInfo objectForKey:@"roomController"];
    if (!_roomController) {
        _roomController = roomController;
        [_roomController getInitialChatHistory];
    }
}

- (void)didReceiveInitialChatHistory:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    _hasReceiveInitialHistory = YES;
    [_chatBackgroundView.loadingView stopAnimating];
    [_chatBackgroundView.loadingView setHidden:YES];
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages) {
        [self sortMessages:messages inDictionary:_messages];
        [self.tableView reloadData];
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
    } else {
        [_chatBackgroundView.placeholderView setHidden:NO];
    }
}

- (void)didReceiveChatHistory:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages) {
        NSIndexPath *lastHistoryMessageIP = [self sortHistoryMessages:messages];
        [self.tableView reloadData];
        [self.tableView scrollToRowAtIndexPath:lastHistoryMessageIP atScrollPosition:UITableViewScrollPositionNone animated:NO];
    }
    
    _retrievingHistory = NO;
    [self hideLoadingHistoryView];
}

- (void)didReceiveChatMessages:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages.count > 0) {
        NSInteger lastSectionBeforeUpdate = _dateSections.count - 1;
        [self sortMessages:messages inDictionary:_messages];
        
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        
        if (messages.count > 1) {
            [self.tableView reloadData];
        } else if (messages.count == 1) {
            [self.tableView beginUpdates];
            NSInteger newLastSection = _dateSections.count - 1;
            BOOL newSection = lastSectionBeforeUpdate != newLastSection;
            if (newSection) {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:newLastSection] withRowAnimation:UITableViewRowAnimationNone];
            } else {
                [self.tableView insertRowsAtIndexPaths:@[lastMessageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
            [self.tableView endUpdates];
        }
        
        if ([self shouldScrollOnNewMessages]) {
            [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
        } else if (!_firstUnreadMessageIP) {
            [self showNewMessagesViewUntilIndexPath:lastMessageIndexPath];
        }
    }
    
}

- (void)didSendChatMessage:(NSNotification *)notification
{
    NSError *error = [notification.userInfo objectForKey:@"error"];
    NSString *message = [notification.userInfo objectForKey:@"message"];
    if (error) {
        self.textView.text = message;
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:@"Could not send the message"
                                     message:@"An error occurred while sending the message"
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* okButton = [UIAlertAction
                                   actionWithTitle:@"OK"
                                   style:UIAlertActionStyleDefault
                                   handler:nil];
        
        [alert addAction:okButton];
        
        [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
    }
}

- (void)didReceiveChatBlocked:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    [self startObservingRoomLobbyFlag];
}

#pragma mark - Lobby functions

- (void)startObservingRoomLobbyFlag
{
    [self updateRoomInformation];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_lobbyCheckTimer invalidate];
        _lobbyCheckTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(updateRoomInformation) userInfo:nil repeats:YES];
    });
}

- (void)updateRoomInformation
{
    [[NCRoomsManager sharedInstance] updateRoom:_room.token];
}

- (BOOL)shouldPresentLobbyView
{
    return _room.lobbyState == NCRoomLobbyStateModeratorsOnly && !_room.canModerate;
}

#pragma mark - Chat functions

- (NSDate *)getKeyForDate:(NSDate *)date inDictionary:(NSDictionary *)dictionary
{
    NSDate *keyDate = nil;
    for (NSDate *key in dictionary.allKeys) {
        if ([[NSCalendar currentCalendar] isDate:date inSameDayAsDate:key]) {
            keyDate = key;
        }
    }
    return keyDate;
}

- (NSIndexPath *)sortHistoryMessages:(NSMutableArray *)historyMessages
{
    NSMutableDictionary *historyDict = [[NSMutableDictionary alloc] init];
    [self sortMessages:historyMessages inDictionary:historyDict];
    
    NSDate *chatSection = nil;
    NSMutableArray *historyMessagesForSection = nil;
    // Sort history sections
    NSMutableArray *historySections = [NSMutableArray arrayWithArray:historyDict.allKeys];
    [historySections sortUsingSelector:@selector(compare:)];
    
    for (NSDate *historySection in historySections) {
        historyMessagesForSection = [historyDict objectForKey:historySection];
        chatSection = [self getKeyForDate:historySection inDictionary:_messages];
        if (!chatSection) {
            [_messages setObject:historyMessagesForSection forKey:historySection];
        }
    }
    
    [self sortDateSections];
    
    NSMutableArray *lastHistoryMessages = [historyDict objectForKey:[historySections lastObject]];
    NSIndexPath *lastHistoryMessageIP = [NSIndexPath indexPathForRow:lastHistoryMessages.count - 1 inSection:historySections.count - 1];
    
    if (chatSection) {
        NSMutableArray *chatMessages = [_messages objectForKey:chatSection];
        NCChatMessage *lastHistoryMessage = [historyMessagesForSection lastObject];
        NCChatMessage *firstChatMessage = [chatMessages firstObject];
        
        BOOL canGroup = [self shouldGroupMessage:firstChatMessage withMessage:lastHistoryMessage];
        if (canGroup) {
            firstChatMessage.groupMessage = YES;
            firstChatMessage.groupMessageNumber = lastHistoryMessage.groupMessageNumber + 1;
            for (int i = 1; i < chatMessages.count; i++) {
                NCChatMessage *currentMessage = chatMessages[i];
                NCChatMessage *messageBefore = chatMessages[i-1];
                if ([self shouldGroupMessage:currentMessage withMessage:messageBefore]) {
                    currentMessage.groupMessage = YES;
                    currentMessage.groupMessageNumber = messageBefore.groupMessageNumber + 1;
                } else if ([currentMessage.actorId isEqualToString:messageBefore.actorId] &&
                           (currentMessage.timestamp - messageBefore.timestamp) < kChatMessageGroupTimeDifference &&
                           messageBefore.groupMessageNumber == kChatMessageMaxGroupNumber) {
                    // Check if message groups need to be changed
                    currentMessage.groupMessage = NO;
                    currentMessage.groupMessageNumber = 0;
                } else {
                    break;
                }
            }
        }
        
        [historyMessagesForSection addObjectsFromArray:chatMessages];
        [_messages setObject:historyMessagesForSection forKey:chatSection];
    }
    
    return lastHistoryMessageIP;
}

- (void)sortMessages:(NSMutableArray *)messages inDictionary:(NSMutableDictionary *)dictionary
{
    for (NCChatMessage *newMessage in messages) {
        NSDate *newMessageDate = [NSDate dateWithTimeIntervalSince1970: newMessage.timestamp];
        NSDate *keyDate = [self getKeyForDate:newMessageDate inDictionary:dictionary];
        NSMutableArray *messagesForDate = [dictionary objectForKey:keyDate];
        if (messagesForDate) {
            NCChatMessage *lastMessage = [messagesForDate lastObject];
            if ([self shouldGroupMessage:newMessage withMessage:lastMessage]) {
                newMessage.groupMessage = YES;
                newMessage.groupMessageNumber = lastMessage.groupMessageNumber + 1;
            }
            [messagesForDate addObject:newMessage];
        } else {
            NSMutableArray *newMessagesInDate = [NSMutableArray new];
            [dictionary setObject:newMessagesInDate forKey:newMessageDate];
            [newMessagesInDate addObject:newMessage];
        }
    }
    
    [self sortDateSections];
}

- (void)sortDateSections
{
    _dateSections = [NSMutableArray arrayWithArray:_messages.allKeys];
    [_dateSections sortUsingSelector:@selector(compare:)];
}

- (BOOL)shouldGroupMessage:(NCChatMessage *)newMessage withMessage:(NCChatMessage *)lastMessage
{
    BOOL sameActor = [newMessage.actorId isEqualToString:lastMessage.actorId];
    BOOL sameType = ([newMessage isSystemMessage] == [lastMessage isSystemMessage]);
    BOOL timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference;
    BOOL notMaxGroup = lastMessage.groupMessageNumber < kChatMessageMaxGroupNumber;
    
    return sameActor & sameType & timeDiff & notMaxGroup;
}

- (BOOL)shouldRetireveHistory
{
    return _hasReceiveInitialHistory && !_retrievingHistory && [_roomController hasHistory] && _dateSections.count > 0;
}

- (void)showLoadingHistoryView
{
    _loadingHistoryView = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    _loadingHistoryView.color = [UIColor darkGrayColor];
    [_loadingHistoryView startAnimating];
    self.tableView.tableHeaderView = _loadingHistoryView;
}

- (void)hideLoadingHistoryView
{
    _loadingHistoryView = nil;
    self.tableView.tableHeaderView = nil;
}

- (BOOL)shouldScrollOnNewMessages
{
    // Scroll if table view is at the bottom (or 80px up) and chat view is visible
    CGFloat minimumOffset = (self.tableView.contentSize.height - self.tableView.frame.size.height) - 80;
    if (self.tableView.contentOffset.y >= minimumOffset && _isVisible) {
        return YES;
    }
    
    return NO;
}

- (void)showNewMessagesViewUntilIndexPath:(NSIndexPath *)messageIP
{
    _firstUnreadMessageIP = messageIP;
    _unreadMessageButton.hidden = NO;
}

- (void)hideNewMessagesView
{
    _firstUnreadMessageIP = nil;
    _unreadMessageButton.hidden = YES;
}

- (void)checkUnreadMessagesVisibility
{
    NSArray* visibleCellsIPs = [self.tableView indexPathsForVisibleRows];
    NSIndexPath *lastVisibleIndexPath = [visibleCellsIPs objectAtIndex:visibleCellsIPs.count -1];
    if (lastVisibleIndexPath == _firstUnreadMessageIP) {
         [self hideNewMessagesView];
    }
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
    
    if ([tableView isEqual:self.tableView] && _dateSections.count > 0) {
        self.tableView.backgroundView = nil;
    } else {
        self.tableView.backgroundView = _chatBackgroundView;
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
        if ([suggestionId isEqualToString:@"all"]) {
            [suggestionCell.avatarView setImage:[UIImage imageNamed:@"group-bg"]];
        } else {
            [suggestionCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:suggestionId andSize:96]
                                             placeholderImage:nil success:nil failure:nil];
        }
        return suggestionCell;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    UITableViewCell *cell = [UITableViewCell new];
    if (message.isSystemMessage) {
        SystemMessageTableViewCell *systemCell = (SystemMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:SystemMessageCellIdentifier];
        systemCell.bodyTextView.attributedText = message.systemMessageFormat;
        systemCell.messageId = message.messageId;
        if (!message.groupMessage) {
            NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
            systemCell.dateLabel.text = [self getTimeFromDate:date];
        }
        return systemCell;
    }
    if (message.file) {
        NSString *fileCellIdentifier = (message.groupMessage) ? GroupedFileMessageCellIdentifier : FileMessageCellIdentifier;
        FileMessageTableViewCell *fileCell = (FileMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:fileCellIdentifier];
        fileCell.titleLabel.text = message.actorDisplayName;
        fileCell.bodyTextView.attributedText = message.parsedMessage;
        fileCell.messageId = message.messageId;
        fileCell.fileLink = message.file.link;
        fileCell.filePath = message.file.path;
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        fileCell.dateLabel.text = [self getTimeFromDate:date];
        [fileCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96]
                                   placeholderImage:nil success:nil failure:nil];
        NSString *imageName = [[NCUtils previewImageForFileMIMEType:message.file.mimetype] stringByAppendingString:@"-chat-preview"];
        UIImage *filePreviewImage = [UIImage imageNamed:imageName];
        __weak FilePreviewImageView *weakPreviewImageView = fileCell.previewImageView;
        [fileCell.previewImageView setImageWithURLRequest:[[NCFilePreviewSessionManager sharedInstance] createPreviewRequestForFile:message.file.parameterId width:120 height:120]
                                         placeholderImage:filePreviewImage success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                             [weakPreviewImageView setImage:image];
                                             weakPreviewImageView.layer.borderColor = [[UIColor colorWithWhite:0.9 alpha:1.0] CGColor];
                                             weakPreviewImageView.layer.borderWidth = 1.0f;
                                         } failure:nil];
        return fileCell;
    }
    if (message.groupMessage) {
        GroupedChatMessageTableViewCell *groupedCell = (GroupedChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:GroupedChatMessageCellIdentifier];
        groupedCell.bodyTextView.attributedText = message.parsedMessage;
        groupedCell.messageId = message.messageId;
        return groupedCell;
    } else {
        ChatMessageTableViewCell *normalCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ChatMessageCellIdentifier];
        normalCell.titleLabel.text = message.actorDisplayName;
        normalCell.bodyTextView.attributedText = message.parsedMessage;
        normalCell.messageId = message.messageId;
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        normalCell.dateLabel.text = [self getTimeFromDate:date];
        
        if ([message.actorType isEqualToString:@"guests"]) {
            normalCell.titleLabel.text = ([message.actorDisplayName isEqualToString:@""]) ? @"Guest" : message.actorDisplayName;
            [normalCell setGuestAvatar:message.actorDisplayName];
        } else if ([message.actorType isEqualToString:@"bots"]) {
            if ([message.actorId isEqualToString:@"changelog"]) {
                [normalCell setChangelogAvatar];
            } else {
                [normalCell setBotAvatar];
            }
        } else {
            [normalCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96]
                                         placeholderImage:nil success:nil failure:nil];
        }
        
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
        if (@available(iOS 11.0, *)) {
            width -= tableView.safeAreaInsets.left + tableView.safeAreaInsets.right;
        }
        width -= (message.isSystemMessage)? 80.0 : 30.0; // 4*right(10) + dateLabel(40) : 3*right(10)
        
        CGRect titleBounds = [message.actorDisplayName boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
        CGRect bodyBounds = [message.parsedMessage boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading) context:NULL];
        
        if (message.message.length == 0) {
            return 0.0;
        }
        
        CGFloat height = CGRectGetHeight(titleBounds);
        height += CGRectGetHeight(bodyBounds);
        height += 40.0;
        
        if (height < kChatMessageCellMinimumHeight) {
            height = kChatMessageCellMinimumHeight;
        }
        
        if (message.groupMessage || message.isSystemMessage) {
            height = CGRectGetHeight(bodyBounds) + 20;
            
            if (height < kGroupedChatMessageCellMinimumHeight) {
                height = kGroupedChatMessageCellMinimumHeight;
            }
        }
        
        if (message.file) {
            height += kFileMessageCellFilePreviewHeight + 15;
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
        NCMessageParameter *mention = [[NCMessageParameter alloc] init];
        mention.parameterId = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        mention.name = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"label"]];
        [_mentions addObject:mention];
        
        NSMutableString *mentionString = [[self.autocompletionUsers[indexPath.row] objectForKey:@"label"] mutableCopy];
        [mentionString appendString:@" "];
        [self acceptAutoCompletionWithString:mentionString keepPrefix:YES];
    }
}

@end
