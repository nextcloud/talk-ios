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
#import "FTPopOverMenu.h"
#import "SystemMessageTableViewCell.h"
#import "MessageSeparatorTableViewCell.h"
#import "DateHeaderView.h"
#import "PlaceholderView.h"
#import "NCAPIController.h"
#import "NCChatController.h"
#import "NCChatMessage.h"
#import "NCDatabaseManager.h"
#import "NCMessageParameter.h"
#import "NCChatTitleView.h"
#import "NCMessageTextView.h"
#import "NCImageSessionManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "NSDate+DateTools.h"
#import "ReplyMessageView.h"
#import "QuotedMessageView.h"
#import "RoomInfoTableViewController.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

typedef enum NCChatMessageAction {
    kNCChatMessageActionReply = 1,
    kNCChatMessageActionCopy
} NCChatMessageAction;

@interface NCChatViewController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) NCChatController *chatController;
@property (nonatomic, strong) NCChatTitleView *titleView;
@property (nonatomic, strong) PlaceholderView *chatBackgroundView;
@property (nonatomic, strong) NSMutableDictionary *messages;
@property (nonatomic, strong) NSMutableArray *dateSections;
@property (nonatomic, strong) NSMutableArray *mentions;
@property (nonatomic, strong) NSMutableArray *autocompletionUsers;
@property (nonatomic, assign) BOOL hasReceiveInitialHistory;
@property (nonatomic, assign) BOOL hasReceiveNewMessages;
@property (nonatomic, assign) BOOL retrievingHistory;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) BOOL hasJoinedRoom;
@property (nonatomic, assign) BOOL leftChatWithVisibleChatVC;
@property (nonatomic, assign) NSInteger lastReadMessage;
@property (nonatomic, strong) NCChatMessage *unreadMessagesSeparator;
@property (nonatomic, strong) NSIndexPath *unreadMessagesSeparatorIP;
@property (nonatomic, assign) NSInteger chatViewPresentedTimestamp;
@property (nonatomic, strong) UIActivityIndicatorView *loadingHistoryView;
@property (nonatomic, assign) NSIndexPath *firstUnreadMessageIP;
@property (nonatomic, strong) UIButton *unreadMessageButton;
@property (nonatomic, strong) UIBarButtonItem *videoCallButton;
@property (nonatomic, strong) UIBarButtonItem *voiceCallButton;
@property (nonatomic, strong) NSTimer *lobbyCheckTimer;
@property (nonatomic, strong) ReplyMessageView *replyMessageView;

@end

@implementation NCChatViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.chatController = [[NCRoomsManager sharedInstance] chatContollerForRoom:room];
        self.hidesBottomBarWhenPushed = YES;
        // Fixes problem with tableView contentSize on iOS 11
        self.tableView.estimatedRowHeight = 0;
        self.tableView.estimatedSectionHeaderHeight = 0;
        // Register a SLKTextView subclass, if you need any special appearance and/or behavior customisation.
        [self registerClassForTextView:[NCMessageTextView class]];
        // Register ReplyMessageView class, conforming to SLKTypingIndicatorProtocol, as a custom typing indicator view.
        [self registerClassForTypingIndicatorView:[ReplyMessageView class]];
        // Set image downloader to file preview imageviews.
        [FilePreviewImageView setSharedImageDownloader:[[NCAPIController sharedInstance] imageDownloader]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveInitialChatHistory:) name:NCChatControllerDidReceiveInitialChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatHistory:) name:NCChatControllerDidReceiveChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatMessages:) name:NCChatControllerDidReceiveChatMessagesNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSendChatMessage:) name:NCChatControllerDidSendChatMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatBlocked:) name:NCChatControllerDidReceiveChatBlockedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
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
    
    // Disable room info, input bar and call buttons until joining the room
    _titleView.userInteractionEnabled = NO;
    [_videoCallButton setEnabled:NO];
    [_voiceCallButton setEnabled:NO];
    self.textInputbar.userInteractionEnabled = NO;
    
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
    self.textInputbar.backgroundColor = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0]; //Default toolbar color
    
    [self.textInputbar.editorTitle setTextColor:[UIColor darkGrayColor]];
    [self.textInputbar.editorLeftButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    [self.textInputbar.editorRightButton setTintColor:[UIColor colorWithRed:0.0/255.0 green:122.0/255.0 blue:255.0/255.0 alpha:1.0]];
    
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    
    // Add long press gesture recognizer
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGesture.delegate = self;
    [self.tableView addGestureRecognizer:longPressGesture];
    self.longPressGesture = longPressGesture;
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ChatMessageCellIdentifier];
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ReplyMessageCellIdentifier];
    [self.tableView registerClass:[GroupedChatMessageTableViewCell class] forCellReuseIdentifier:GroupedChatMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:FileMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:GroupedFileMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:SystemMessageCellIdentifier];
    [self.tableView registerClass:[MessageSeparatorTableViewCell class] forCellReuseIdentifier:MessageSeparatorCellIdentifier];
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
    
    // Unread messages separator
    _unreadMessagesSeparator = [[NCChatMessage alloc] init];
    _unreadMessagesSeparator.messageId = kMessageSeparatorIdentifier;
    
    [self.view addSubview:_unreadMessageButton];
    _chatViewPresentedTimestamp = [[NSDate date] timeIntervalSince1970];
    _lastReadMessage = _room.lastReadMessage;
    
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
    
    if (!_hasReceiveInitialHistory) {
        [_chatController getInitialChatHistory];
    }
    
    _isVisible = YES;
    
    [[NCRoomsManager sharedInstance] joinRoom:_room.token];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Just in case the initial history was loaded from the DB
    [self.tableView slk_scrollToBottomAnimated:NO];
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
        if ([[NCRoomsManager sharedInstance].chatViewController.room.token isEqualToString:_room.token]) {
            [NCRoomsManager sharedInstance].chatViewController = nil;
        }
        [self leaveChat];
    }
}

- (void)leaveChat
{
    [_lobbyCheckTimer invalidate];
    [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
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
            [_titleView.image setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
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
        // Enable room info, input bar and call buttons
        _titleView.userInteractionEnabled = YES;
        [_videoCallButton setEnabled:YES];
        [_voiceCallButton setEnabled:YES];
        self.textInputbar.userInteractionEnabled = YES;
    }
    
    if (![_room userCanStartCall] && !_room.hasCall) {
        // Disable call buttons
        [_videoCallButton setEnabled:NO];
        [_voiceCallButton setEnabled:NO];
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
        [_chatBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"lobby-placeholder"]];
        if (_room.lobbyTimer > 0) {
            NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
            NSString *meetingStart = [NCUtils readableDateFromDate:date];
            NSString *placeHolderText = [NSString stringWithFormat:@"You are currently waiting in the lobby.\nThis meeting is scheduled for\n%@", meetingStart];
            [_chatBackgroundView.placeholderText setText:placeHolderText];
            [_chatBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"lobby-placeholder"]];
        }
        [_chatBackgroundView.placeholderView setHidden:NO];
        [_chatBackgroundView.loadingView stopAnimating];
        [_chatBackgroundView.loadingView setHidden:YES];
        // Clear current chat since chat history will be retrieve when lobby is disabled
        [self cleanChat];
    } else {
        [_chatBackgroundView.placeholderText setText:@"No messages yet, start the conversation!"];
        [_chatBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"chat-placeholder"]];
        [_chatBackgroundView.placeholderView setHidden:YES];
        [_chatBackgroundView.loadingView startAnimating];
        [_chatBackgroundView.loadingView setHidden:NO];
        // Stop checking lobby flag
        [_lobbyCheckTimer invalidate];
        // Retrieve initial chat history
        if (!_hasReceiveInitialHistory) {
            [_chatController getInitialChatHistory];
        }
    }
    [self checkRoomControlsAvailability];
}

#pragma mark - Utils

- (NSInteger)getLastReadMessage
{
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker]) {
        return _lastReadMessage;
    }
    return 0;
}

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
                                                     handler:nil];
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

#pragma mark - Action Methods

- (void)titleButtonPressed:(id)sender
{
    RoomInfoTableViewController *roomInfoVC = [[RoomInfoTableViewController alloc] initForRoom:_room fromChatViewController:self];
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
    NSInteger replyTo = (_replyMessageView.isVisible) ? _replyMessageView.message.messageId : -1;
    
    [[NCRoomsManager sharedInstance] sendChatMessage:sendingText replyTo:replyTo toRoom:_room];
    [_replyMessageView dismiss];
    [super didPressRightButton:sender];
}

- (void)didPressLeftButton:(id)sender
{
    DirectoryTableViewController *directoryVC = [[DirectoryTableViewController alloc] initWithPath:@"" inRoom:_room.token];
    UINavigationController *fileSharingNC = [[UINavigationController alloc] initWithRootViewController:directoryVC];
    [self presentViewController:fileSharingNC animated:YES completion:nil];
    [super didPressLeftButton:sender];
}

#pragma mark - Gesture recognizer

-(void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    CGPoint point = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath != nil && gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        if (!message.isSystemMessage) {
            // Select cell
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
            
            // Create menu
            FTPopOverMenuConfiguration *menuConfiguration = [[FTPopOverMenuConfiguration alloc] init];
            menuConfiguration.menuIconMargin = 12;
            menuConfiguration.menuTextMargin = 12;
            menuConfiguration.imageSize = CGSizeMake(20, 20);
            menuConfiguration.separatorInset = UIEdgeInsetsMake(0, 44, 0, 0);
            menuConfiguration.menuRowHeight = 44;
            menuConfiguration.autoMenuWidth = YES;
            menuConfiguration.textFont = [UIFont systemFontOfSize:15];
            menuConfiguration.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
            menuConfiguration.borderWidth = 0;
            menuConfiguration.shadowOpacity = 0;
            menuConfiguration.roundedImage = NO;
            menuConfiguration.defaultSelection = YES;
            
            NSMutableArray *menuArray = [NSMutableArray new];
            // Reply option
            if (message.isReplyable) {
                NSDictionary *replyInfo = [NSDictionary dictionaryWithObject:@(kNCChatMessageActionReply) forKey:@"action"];
                FTPopOverMenuModel *replyModel = [[FTPopOverMenuModel alloc] initWithTitle:@"Reply" image:[UIImage imageNamed:@"reply"] userInfo:replyInfo];
                [menuArray addObject:replyModel];
            }
            // Copy option
            NSDictionary *copyInfo = [NSDictionary dictionaryWithObject:@(kNCChatMessageActionCopy) forKey:@"action"];
            FTPopOverMenuModel *copyModel = [[FTPopOverMenuModel alloc] initWithTitle:@"Copy" image:[UIImage imageNamed:@"clippy"] userInfo:copyInfo];
            [menuArray addObject:copyModel];
            
            CGRect frame = [self.tableView rectForRowAtIndexPath:indexPath];
            CGPoint yOffset = self.tableView.contentOffset;
            CGRect cellRect = CGRectMake(frame.origin.x, (frame.origin.y - yOffset.y), frame.size.width, frame.size.height);
            
            __weak NCChatViewController *weakSelf = self;
            [FTPopOverMenu showFromSenderFrame:cellRect withMenuArray:menuArray imageArray:nil configuration:menuConfiguration doneBlock:^(NSInteger selectedIndex) {
                [weakSelf.tableView deselectRowAtIndexPath:indexPath animated:YES];
                FTPopOverMenuModel *model = [menuArray objectAtIndex:selectedIndex];
                NCChatMessageAction action = (NCChatMessageAction)[[model.userInfo objectForKey:@"action"] integerValue];
                switch (action) {
                    case kNCChatMessageActionReply:
                    {
                        weakSelf.replyMessageView = (ReplyMessageView *)weakSelf.typingIndicatorProxyView;
                        [weakSelf.replyMessageView dismiss];
                        [weakSelf.replyMessageView presentReplyViewWithMessage:message];
                        [weakSelf presentKeyboard:YES];
                    }
                        break;
                    case kNCChatMessageActionCopy:
                    {
                        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                        pasteboard.string = message.parsedMessage.string;
                    }
                        break;
                    default:
                        break;
                }
            } dismissBlock:^{
                [weakSelf.tableView deselectRowAtIndexPath:indexPath animated:YES];
            }];
        }
    }
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if ([scrollView isEqual:self.tableView] && scrollView.contentOffset.y < 0) {
        if ([self couldRetireveHistory]) {
            NSDate *dateSection = [_dateSections objectAtIndex:0];
            NCChatMessage *firstMessage = [[_messages objectForKey:dateSection] objectAtIndex:0];
            if ([_chatController hasHistoryFromMessageId:firstMessage.messageId]) {
                _retrievingHistory = YES;
                [self showLoadingHistoryView];
                [_chatController getHistoryBatchFromMessagesId:firstMessage.messageId];
            }
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

#pragma mark - App lifecycle notifications

-(void)appDidBecomeActive:(NSNotification*)notification
{
    [self removeUnreadMessagesSeparator];
    [[NCRoomsManager sharedInstance] joinRoom:_room.token];
}

-(void)appWillResignActive:(NSNotification*)notification
{
    _hasReceiveNewMessages = NO;
    _leftChatWithVisibleChatVC = YES;
    [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
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
    
    if (_leftChatWithVisibleChatVC && _hasReceiveInitialHistory) {
        _leftChatWithVisibleChatVC = NO;
        [_chatController startReceivingNewChatMessages];
    } else if (!_hasReceiveInitialHistory) {
        [_chatController getInitialChatHistory];
    }
}

- (void)didReceiveInitialChatHistory:(NSNotification *)notification
{
    NSString *room = [notification.userInfo objectForKey:@"room"];
    if (![room isEqualToString:_room.token]) {
        return;
    }
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages.count > 0) {
        // Set last received message as last read message
        NCChatMessage *lastReceivedMessage = [messages objectAtIndex:messages.count - 1];
        _lastReadMessage = lastReceivedMessage.messageId;
        [self sortMessages:messages inDictionary:_messages];
        [self.tableView reloadData];
        [self.tableView slk_scrollToBottomAnimated:NO];
    } else {
        [_chatBackgroundView.placeholderView setHidden:NO];
    }
    
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (!error) {
        _hasReceiveInitialHistory = YES;
        [_chatController startReceivingNewChatMessages];
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
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (![room isEqualToString:_room.token] || error) {
        return;
    }
    
    BOOL firstNewMessagesAfterHistory = !_hasReceiveNewMessages;
    _hasReceiveNewMessages = YES;
    
    NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
    if (messages.count > 0) {
        NSInteger lastSectionBeforeUpdate = _dateSections.count - 1;
        BOOL unreadMessagesReceived = NO;
        // Check if unread messages separator should be added
        if (firstNewMessagesAfterHistory && [self getLastReadMessage] > 0 && messages.count > 0) {
            unreadMessagesReceived = YES;
            NSMutableArray *messagesForLastDateBeforeUpdate = [_messages objectForKey:[_dateSections lastObject]];
            [messagesForLastDateBeforeUpdate addObject:_unreadMessagesSeparator];
            _unreadMessagesSeparatorIP = [NSIndexPath indexPathForRow:messagesForLastDateBeforeUpdate.count - 1 inSection: _dateSections.count - 1];
            [_messages setObject:messagesForLastDateBeforeUpdate forKey:[_dateSections lastObject]];
        }
        
        // Sort received messages
        [self sortMessages:messages inDictionary:_messages];
        
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        
        // Load messages in chat view
        if (messages.count > 1 || unreadMessagesReceived) {
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
        
        BOOL newMessagesContainUserMessage = [self newMessagesContainUserMessage:messages];
        // Remove unread messages separator when user writes a message
        if (newMessagesContainUserMessage) {
            [self removeUnreadMessagesSeparator];
            // Update last message index path
            lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
        }
        
        NCChatMessage *firstNewMessage = [messages objectAtIndex:0];
        NSIndexPath *firstMessageIndexPath = [self indexPathForMessage:firstNewMessage];
        // This variable is needed since several calls to receiveMessages API might be needed
        // (if the number of unread messages is bigger than the "limit" in receiveMessages request)
        // to receive all the unread messages.
        BOOL areReallyNewMessages = firstNewMessage.timestamp >= _chatViewPresentedTimestamp;
        
        // Position chat view
        if (unreadMessagesReceived) {
            [self.tableView scrollToRowAtIndexPath:firstMessageIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        } else if ([self shouldScrollOnNewMessages] || newMessagesContainUserMessage) {
            [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
        } else if (!_firstUnreadMessageIP && areReallyNewMessages) {
            [self showNewMessagesViewUntilIndexPath:firstMessageIndexPath];
        }
        
        // Set last received message as last read message
        NCChatMessage *lastReceivedMessage = [messages objectAtIndex:messages.count - 1];
        _lastReadMessage = lastReceivedMessage.messageId;
    } else if (firstNewMessagesAfterHistory) {
        // Now the chat is loaded after getting the initial history and the first new messages block.
        // Even if there are no new messages, tableview should be reloaded and scrolled to the bottom
        // as it was done when only initial history was loaded.
        [self.tableView reloadData];
        NSMutableArray *messagesForLastDate = [_messages objectForKey:[_dateSections lastObject]];
        if (messagesForLastDate.count > 0) {
            NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:_dateSections.count - 1];
            [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
        }
    }
    
    if (firstNewMessagesAfterHistory) {
        [_chatBackgroundView.loadingView stopAnimating];
        [_chatBackgroundView.loadingView setHidden:YES];
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

- (NSIndexPath *)indexPathForMessage:(NCChatMessage *)message
{
    NSDate *messageDate = [NSDate dateWithTimeIntervalSince1970: message.timestamp];
    NSDate *keyDate = [self getKeyForDate:messageDate inDictionary:_messages];
    NSInteger section = [_dateSections indexOfObject:keyDate];
    if (NSNotFound != section) {
        NSMutableArray *messages = [_messages objectForKey:keyDate];
        for (int i = 0; i < messages.count; i++) {
            NCChatMessage *currentMessage = messages[i];
            if (currentMessage.messageId == message.messageId) {
                return [NSIndexPath indexPathForRow:i inSection:section];
            }
        }
    }
    
    return nil;
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

- (BOOL)couldRetireveHistory
{
    return _hasReceiveInitialHistory && !_retrievingHistory && _dateSections.count > 0;
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
    if (_isVisible) {
        // Scroll if table view is at the bottom (or 80px up)
        CGFloat minimumOffset = (self.tableView.contentSize.height - self.tableView.frame.size.height) - 80;
        if (self.tableView.contentOffset.y >= minimumOffset) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)newMessagesContainUserMessage:(NSMutableArray *)messages
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    for (NCChatMessage *message in messages) {
        if ([message.actorId isEqualToString:activeAccount.userId]) {
            return YES;
        }
    }
    return NO;
}

- (void)showNewMessagesViewUntilIndexPath:(NSIndexPath *)messageIP
{
    _firstUnreadMessageIP = messageIP;
    _unreadMessageButton.hidden = NO;
    // Check if unread messages are already visible
    [self checkUnreadMessagesVisibility];
}

- (void)hideNewMessagesView
{
    _firstUnreadMessageIP = nil;
    _unreadMessageButton.hidden = YES;
}

- (void)removeUnreadMessagesSeparator
{
    if (_unreadMessagesSeparatorIP) {
        NSDate *separatorDate = [_dateSections objectAtIndex:_unreadMessagesSeparatorIP.section];
        NSMutableArray *messages = [_messages objectForKey:separatorDate];
        [messages removeObjectAtIndex:_unreadMessagesSeparatorIP.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:_unreadMessagesSeparatorIP] withRowAnimation:UITableViewRowAnimationTop];
        _unreadMessagesSeparatorIP = nil;
    }
}

- (void)checkUnreadMessagesVisibility
{
    NSArray* visibleCellsIPs = [self.tableView indexPathsForVisibleRows];
    if ([visibleCellsIPs containsObject:_firstUnreadMessageIP]) {
         [self hideNewMessagesView];
    }
}

- (void)cleanChat
{
    _messages = [[NSMutableDictionary alloc] init];
    _dateSections = [[NSMutableArray alloc] init];
    _hasReceiveInitialHistory = NO;
    _hasReceiveNewMessages = NO;
    _unreadMessagesSeparatorIP = nil;
    [self hideNewMessagesView];
    [self.tableView reloadData];
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
    [[NCAPIController sharedInstance] getMentionSuggestionsInRoom:_room.token forString:string forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSMutableArray *mentions, NSError *error) {
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
        NSString *suggestionSource = [suggestion objectForKey:@"source"];
        ChatMessageTableViewCell *suggestionCell = (ChatMessageTableViewCell *)[self.autoCompletionView dequeueReusableCellWithIdentifier:AutoCompletionCellIdentifier];
        suggestionCell.titleLabel.text = suggestionName;
        if ([suggestionId isEqualToString:@"all"]) {
            [suggestionCell.avatarView setImage:[UIImage imageNamed:@"group-bg"]];
        } else if ([suggestionSource isEqualToString:@"guests"]) {
            UIColor *guestAvatarColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
            NSString *name = ([suggestionName isEqualToString:@"Guest"]) ? @"?" : suggestionName;
            [suggestionCell.avatarView setImageWithString:name color:guestAvatarColor circular:true];
        } else {
            [suggestionCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:suggestionId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                             placeholderImage:nil success:nil failure:nil];
        }
        return suggestionCell;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    UITableViewCell *cell = [UITableViewCell new];
    if (message.messageId == kMessageSeparatorIdentifier) {
        MessageSeparatorTableViewCell *separatorCell = (MessageSeparatorTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:MessageSeparatorCellIdentifier];
        return separatorCell;
    }
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
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        [fileCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96 usingAccount:activeAccount]
                                   placeholderImage:nil success:nil failure:nil];
        NSString *imageName = [[NCUtils previewImageForFileMIMEType:message.file.mimetype] stringByAppendingString:@"-chat-preview"];
        UIImage *filePreviewImage = [UIImage imageNamed:imageName];
        __weak FilePreviewImageView *weakPreviewImageView = fileCell.previewImageView;
        [fileCell.previewImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createPreviewRequestForFile:message.file.parameterId width:120 height:120 usingAccount:activeAccount]
                                         placeholderImage:filePreviewImage success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                             [weakPreviewImageView setImage:image];
                                             weakPreviewImageView.layer.borderColor = [[UIColor colorWithWhite:0.9 alpha:1.0] CGColor];
                                             weakPreviewImageView.layer.borderWidth = 1.0f;
                                         } failure:nil];
        return fileCell;
    }
    if (message.parent) {
        ChatMessageTableViewCell *normalCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ReplyMessageCellIdentifier];
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
            [normalCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                         placeholderImage:nil success:nil failure:nil];
        }
        
        normalCell.quotedMessageView.actorLabel.text = message.parent.actorDisplayName;
        normalCell.quotedMessageView.messageLabel.text = message.parent.parsedMessage.string;
        
        return normalCell;
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
            [normalCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
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
        
        if (message.messageId == kMessageSeparatorIdentifier) {
            return kMessageSeparatorCellHeight;
        }
        
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
        
        if (message.parent) {
            height += 60;
            return height;
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
        // Guest mentions are wrapped with double quotes @"guest/<sha1(webrtc session id)>"
        if ([[self.autocompletionUsers[indexPath.row] objectForKey:@"source"] isEqualToString:@"guests"]) {
            mention.parameterId = [NSString stringWithFormat:@"@\"%@\"", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        }
        // User-ids with a space should be wrapped in double quoutes
        NSRange whiteSpaceRange = [mention.parameterId rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (whiteSpaceRange.location != NSNotFound) {
            mention.parameterId = [NSString stringWithFormat:@"@\"%@\"", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        }
        [_mentions addObject:mention];
        
        NSMutableString *mentionString = [[self.autocompletionUsers[indexPath.row] objectForKey:@"label"] mutableCopy];
        [mentionString appendString:@" "];
        [self acceptAutoCompletionWithString:mentionString keepPrefix:YES];
    } else {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

@end
