/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <AVFoundation/AVFoundation.h>
#import <ContactsUI/ContactsUI.h>
#import <QuickLook/QuickLook.h>

@import NCCommunication;

#import "NCChatViewController.h"

#import "AFImageDownloader.h"
#import "FTPopOverMenu.h"
#import "NSDate+DateTools.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "UIResponder+SLKAdditions.h"
#import "UIView+Toast.h"

#import "AppDelegate.h"
#import "BarButtonItemWithActivity.h"
#import "CallKitManager.h"
#import "ChatMessageTableViewCell.h"
#import "DateHeaderView.h"
#import "DirectoryTableViewController.h"
#import "GroupedChatMessageTableViewCell.h"
#import "FileMessageTableViewCell.h"
#import "GeoLocationRichObject.h"
#import "LocationMessageTableViewCell.h"
#import "MapViewController.h"
#import "MessageSeparatorTableViewCell.h"
#import "ObjectShareMessageTableViewCell.h"
#import "PlaceholderView.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatController.h"
#import "NCChatFileController.h"
#import "NCChatMessage.h"
#import "NCChatTitleView.h"
#import "NCConnectionController.h"
#import "NCDatabaseManager.h"
#import "NCImageSessionManager.h"
#import "NCMessageParameter.h"
#import "NCMessageTextView.h"
#import "NCNavigationController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "QuotedMessageView.h"
#import "ReplyMessageView.h"
#import "RoomInfoTableViewController.h"
#import "ShareViewController.h"
#import "ShareConfirmationViewController.h"
#import "ShareItem.h"
#import "SystemMessageTableViewCell.h"
#import "ShareLocationViewController.h"
#import "VoiceMessageRecordingView.h"
#import "VoiceMessageTableViewCell.h"
#import "VoiceMessageTranscribeViewController.h"
#import "NextcloudTalk-Swift.h"


#define k_send_message_button_tag   99
#define k_voice_record_button_tag   98

typedef enum NCChatMessageAction {
    kNCChatMessageActionReply = 1,
    kNCChatMessageActionForward,
    kNCChatMessageActionCopy,
    kNCChatMessageActionResend,
    kNCChatMessageActionDelete,
    kNCChatMessageActionReplyPrivately,
    kNCChatMessageActionOpenFileInNextcloud,
    kNCChatMessageActionAddReaction
} NCChatMessageAction;

NSString * const kActionTypeTranscribeVoiceMessage   = @"transcribe-voice-message";

@interface NCChatViewController () <UIGestureRecognizerDelegate, UINavigationControllerDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UIDocumentPickerDelegate, ShareViewControllerDelegate, ShareConfirmationViewControllerDelegate, FileMessageTableViewCellDelegate, NCChatFileControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource, ChatMessageTableViewCellDelegate, ShareLocationViewControllerDelegate, LocationMessageTableViewCellDelegate, VoiceMessageTableViewCellDelegate, ObjectShareMessageTableViewCellDelegate, PollCreationViewControllerDelegate, AVAudioRecorderDelegate, AVAudioPlayerDelegate, CNContactPickerDelegate>

@property (nonatomic, strong) NCChatController *chatController;
@property (nonatomic, strong) NCChatTitleView *titleView;
@property (nonatomic, strong) PlaceholderView *chatBackgroundView;
@property (nonatomic, strong) NSMutableDictionary *messages;
@property (nonatomic, strong) NSMutableArray *dateSections;
@property (nonatomic, strong) NSMutableDictionary *mentionsDict;
@property (nonatomic, strong) NSMutableArray *autocompletionUsers;
@property (nonatomic, assign) BOOL hasRequestedInitialHistory;
@property (nonatomic, assign) BOOL hasReceiveInitialHistory;
@property (nonatomic, assign) BOOL hasReceiveNewMessages;
@property (nonatomic, assign) BOOL retrievingHistory;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) BOOL hasJoinedRoom;
@property (nonatomic, assign) BOOL startReceivingMessagesAfterJoin;
@property (nonatomic, assign) BOOL offlineMode;
@property (nonatomic, assign) BOOL hasStoredHistory;
@property (nonatomic, assign) BOOL hasStopped;
@property (nonatomic, assign) NSInteger lastReadMessage;
@property (nonatomic, strong) NCChatMessage *unreadMessagesSeparator;
@property (nonatomic, assign) NSInteger chatViewPresentedTimestamp;
@property (nonatomic, strong) UIActivityIndicatorView *loadingHistoryView;
@property (nonatomic, assign) NCChatMessage *firstUnreadMessage;
@property (nonatomic, strong) UIButton *unreadMessageButton;
@property (nonatomic, strong) NSTimer *lobbyCheckTimer;
@property (nonatomic, strong) ReplyMessageView *replyMessageView;
@property (nonatomic, strong) UIImagePickerController *imagePicker;
@property (nonatomic, strong) BarButtonItemWithActivity *videoCallButton;
@property (nonatomic, strong) BarButtonItemWithActivity *voiceCallButton;
@property (nonatomic, assign) BOOL isPreviewControllerShown;
@property (nonatomic, strong) NSString *previewControllerFilePath;
@property (nonatomic, strong) dispatch_group_t animationDispatchGroup;
@property (nonatomic, strong) dispatch_queue_t animationDispatchQueue;
@property (nonatomic, strong) UIView *inputbarBorderView;
@property (nonatomic, strong) UILongPressGestureRecognizer *voiceMessageLongPressGesture;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) VoiceMessageRecordingView *voiceMessageRecordingView;
@property (nonatomic, assign) CGPoint longPressStartingPoint;
@property (nonatomic, assign) CGFloat cancelHintLabelInitialPositionX;
@property (nonatomic, assign) BOOL recordCancelled;
@property (nonatomic, strong) AVAudioPlayer *voiceMessagesPlayer;
@property (nonatomic, strong) NSTimer *playerProgressTimer;
@property (nonatomic, strong) NCChatFileStatus *playerAudioFileStatus;
@property (nonatomic, strong) EmojiTextField *emojiTextField;
@property (nonatomic, strong) NCChatMessage *reactingMessage;
@property (nonatomic, strong) NSIndexPath *lastMessageBeforeReaction;
@property (nonatomic, strong) NSTimer *messageExpirationTimer;

@end

@implementation NCChatViewController

NSString * const NCChatViewControllerReplyPrivatelyNotification = @"NCChatViewControllerReplyPrivatelyNotification";
NSString * const NCChatViewControllerForwardNotification = @"NCChatViewControllerForwardNotification";
NSString * const NCChatViewControllerTalkToUserNotification = @"NCChatViewControllerTalkToUserNotification";

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super initWithTableViewStyle:UITableViewStylePlain];
    if (self) {
        self.room = room;
        self.chatController = [[NCChatController alloc] initForRoom:room];
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
        // Initialize the animation dispatch group/queue
        NSString *dispatchQueueIdentifier = [NSString stringWithFormat:@"%@.%@", groupIdentifier, @"animationQueue"];
        const char *dispatchQueueIdentifierChar = [dispatchQueueIdentifier UTF8String];
        self.animationDispatchGroup = dispatch_group_create();
        self.animationDispatchQueue = dispatch_queue_create(dispatchQueueIdentifierChar, DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willShowKeyboard:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wllHideHideKeyboard:) name:UIKeyboardWillHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didLeaveRoom:) name:NCRoomsManagerDidLeaveRoomNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveInitialChatHistory:) name:NCChatControllerDidReceiveInitialChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveInitialChatHistoryOffline:) name:NCChatControllerDidReceiveInitialChatHistoryOfflineNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatHistory:) name:NCChatControllerDidReceiveChatHistoryNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatMessages:) name:NCChatControllerDidReceiveChatMessagesNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSendChatMessage:) name:NCChatControllerDidSendChatMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveChatBlocked:) name:NCChatControllerDidReceiveChatBlockedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNewerCommonReadMessage:) name:NCChatControllerDidReceiveNewerCommonReadMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveCallStartedMessage:) name:NCChatControllerDidReceiveCallStartedMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveCallEndedMessage:) name:NCChatControllerDidReceiveCallEndedMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveUpdateMessage:) name:NCChatControllerDidReceiveUpdateMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveHistoryCleared:) name:NCChatControllerDidReceiveHistoryClearedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFailRequestingCallTransaction:) name:CallKitManagerDidFailRequestingCallTransaction object:nil];

        // Notifications when runing on Mac 
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:@"NSApplicationDidBecomeActiveNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:@"NSApplicationDidResignActiveNotification" object:nil];
    }
    
    return self;
}
    
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"Dealloc NCChatViewController");
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setTitleView];
    [self configureActionItems];
    
    // Disable room info, input bar and call buttons until joining the room
    [self disableRoomControls];
    
    self.messages = [[NSMutableDictionary alloc] init];
    self.mentionsDict = [[NSMutableDictionary alloc] init];
    self.dateSections = [[NSMutableArray alloc] init];
    
    self.bounces = NO;
    self.shakeToClearEnabled = YES;
    self.keyboardPanningEnabled = YES;
    self.shouldScrollToBottomAfterKeyboardShows = NO;
    self.inverted = NO;
    
    [self showSendMessageButton];
    [self.leftButton setImage:[UIImage imageNamed:@"attachment"] forState:UIControlStateNormal];
    self.leftButton.accessibilityLabel = NSLocalizedString(@"Share a file from your Nextcloud", nil);
    self.leftButton.accessibilityHint = NSLocalizedString(@"Double tap to open file browser", nil);
    
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
    self.textInputbar.contentInset = UIEdgeInsetsMake(8, 4, 8, 4);
    self.textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    
    [self.view setBackgroundColor:[UIColor whiteColor]];
    self.textInputbar.backgroundColor = [UIColor whiteColor];
    [self.textInputbar setSemanticContentAttribute:UISemanticContentAttributeForceLeftToRight];
    
    // Make sure we update the textView frame
    [self.textView layoutSubviews];
    self.textView.layer.cornerRadius = self.textView.frame.size.height / 2;
    
    [self.textInputbar.editorTitle setTextColor:[UIColor darkGrayColor]];
    [self.textInputbar.editorLeftButton setTintColor:[UIColor systemBlueColor]];
    [self.textInputbar.editorRightButton setTintColor:[UIColor systemBlueColor]];
    
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;

    [self.view setBackgroundColor:[UIColor systemBackgroundColor]];
    [self.textInputbar setBackgroundColor:[UIColor systemBackgroundColor]];

    [self.textInputbar.editorTitle setTextColor:[UIColor labelColor]];
    [self.textView.layer setBorderWidth:1.0];
    [self.textView.layer setBorderColor:[UIColor systemGray4Color].CGColor];
    
    // Hide default top border of UIToolbar
    [self.textInputbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
    
    // Add new border subView to inputbar
    self.inputbarBorderView = [UIView new];
    [self.inputbarBorderView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin];
    self.inputbarBorderView.frame = CGRectMake(0, 0, self.textInputbar.frame.size.width, 1);
    self.inputbarBorderView.hidden = YES;
    self.inputbarBorderView.backgroundColor = [UIColor systemGray6Color];

    [self.textInputbar addSubview:self.inputbarBorderView];
    
    // Add emoji textfield for reactions
    _emojiTextField = [[EmojiTextField alloc] init];
    _emojiTextField.delegate = self;
    [self.view addSubview:_emojiTextField];
    
    // Add long press gesture recognizer for voice message recording button
    self.voiceMessageLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressInVoiceMessageRecordButton:)];
    self.voiceMessageLongPressGesture.delegate = self;
    [self.rightButton addGestureRecognizer:self.voiceMessageLongPressGesture];
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ChatMessageCellIdentifier];
    [self.tableView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:ReplyMessageCellIdentifier];
    [self.tableView registerClass:[GroupedChatMessageTableViewCell class] forCellReuseIdentifier:GroupedChatMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:FileMessageCellIdentifier];
    [self.tableView registerClass:[FileMessageTableViewCell class] forCellReuseIdentifier:GroupedFileMessageCellIdentifier];
    [self.tableView registerClass:[LocationMessageTableViewCell class] forCellReuseIdentifier:LocationMessageCellIdentifier];
    [self.tableView registerClass:[LocationMessageTableViewCell class] forCellReuseIdentifier:GroupedLocationMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:SystemMessageCellIdentifier];
    [self.tableView registerClass:[SystemMessageTableViewCell class] forCellReuseIdentifier:InvisibleSystemMessageCellIdentifier];
    [self.tableView registerClass:[VoiceMessageTableViewCell class] forCellReuseIdentifier:VoiceMessageCellIdentifier];
    [self.tableView registerClass:[VoiceMessageTableViewCell class] forCellReuseIdentifier:GroupedVoiceMessageCellIdentifier];
    [self.tableView registerClass:[ObjectShareMessageTableViewCell class] forCellReuseIdentifier:ObjectShareMessageCellIdentifier];
    [self.tableView registerClass:[ObjectShareMessageTableViewCell class] forCellReuseIdentifier:GroupedObjectShareMessageCellIdentifier];
    [self.tableView registerClass:[MessageSeparatorTableViewCell class] forCellReuseIdentifier:MessageSeparatorCellIdentifier];
    [self.autoCompletionView registerClass:[ChatMessageTableViewCell class] forCellReuseIdentifier:AutoCompletionCellIdentifier];
    [self registerPrefixesForAutoCompletion:@[@"@"]];
    self.autoCompletionView.backgroundColor = [UIColor secondarySystemBackgroundColor];

    if (@available(iOS 15.0, *)) {
        self.autoCompletionView.sectionHeaderTopPadding = 0;
    }
    // Align separators to ChatMessageTableViewCell's title label
    self.autoCompletionView.separatorInset = UIEdgeInsetsMake(0, 50, 0, 0);
    
    // Chat placeholder view
    _chatBackgroundView = [[PlaceholderView alloc] init];
    [_chatBackgroundView.placeholderView setHidden:YES];
    [_chatBackgroundView.loadingView startAnimating];
    [_chatBackgroundView.placeholderTextView setText:NSLocalizedString(@"No messages yet, start the conversation!", nil)];
    [_chatBackgroundView setImage:[UIImage imageNamed:@"chat-placeholder"]];
    self.tableView.backgroundView = _chatBackgroundView;
    
    // Unread messages indicator
    _firstUnreadMessage = nil;
    _unreadMessageButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 126, 24)];
    _unreadMessageButton.backgroundColor = [NCAppBranding themeColor];
    [_unreadMessageButton setTitleColor:[NCAppBranding themeTextColor] forState:UIControlStateNormal];
    _unreadMessageButton.titleLabel.font = [UIFont systemFontOfSize:12];
    _unreadMessageButton.layer.cornerRadius = 12;
    _unreadMessageButton.clipsToBounds = YES;
    _unreadMessageButton.hidden = YES;
    _unreadMessageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _unreadMessageButton.contentEdgeInsets = UIEdgeInsetsMake(0.0f, 10.0f, 0.0f, 10.0f);
    _unreadMessageButton.titleLabel.minimumScaleFactor = 0.9f;
    _unreadMessageButton.titleLabel.numberOfLines = 1;
    _unreadMessageButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    NSString *buttonText = NSLocalizedString(@"↓ New messages", nil);
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:12]};
    CGRect textSize = [buttonText boundingRectWithSize:CGSizeMake(300, 24) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
    CGFloat buttonWidth = textSize.size.width + 20;

    [_unreadMessageButton addTarget:self action:@selector(unreadMessagesButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_unreadMessageButton setTitle:buttonText forState:UIControlStateNormal];
    
    // Unread messages separator
    _unreadMessagesSeparator = [[NCChatMessage alloc] init];
    _unreadMessagesSeparator.messageId = kUnreadMessagesSeparatorIdentifier;
    
    self.hasStoredHistory = YES;
    
    [self.view addSubview:_unreadMessageButton];
    _chatViewPresentedTimestamp = [[NSDate date] timeIntervalSince1970];
    _lastReadMessage = _room.lastReadMessage;
    
    // Check if there's a stored pending message
    if (_room.pendingMessage != nil) {
        [self setChatMessage:self.room.pendingMessage];
    }
    
    NSDictionary *views = @{@"unreadMessagesButton": _unreadMessageButton,
                            @"textInputbar": self.textInputbar};
    NSDictionary *metrics = @{@"buttonWidth": @(buttonWidth)};
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[unreadMessagesButton(24)]-5-[textInputbar]" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[unreadMessagesButton(buttonWidth)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual
                                                             toItem:_unreadMessageButton attribute:NSLayoutAttributeCenterX multiplier:1.f constant:0.f]];
    
    // We can't use UIColor with systemBlueColor directly, because it will switch to indigo. So make sure we actually get a blue tint here
    [self.textView setTintColor:[UIColor colorWithCGColor:[UIColor systemBlueColor].CGColor]];
}

- (void)updateToolbar:(BOOL)animated
{
    void (^animations)(void) = ^void() {
        CGFloat minimumOffset = (self.tableView.contentSize.height - self.tableView.frame.size.height) - 10;
        
        if (self.tableView.contentOffset.y < minimumOffset) {
            // Scrolled -> show top border
            self.inputbarBorderView.hidden = NO;
        } else {
            // At the bottom -> no top border
            self.inputbarBorderView.hidden = YES;
        }
    };

    if (animated) {
        // Make sure the previous animation is finished before issuing another one
        dispatch_async(self.animationDispatchQueue, ^{
            dispatch_group_enter(self.animationDispatchGroup);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Make sure we use the superview of the border here
                [UIView transitionWithView:self.textInputbar
                                  duration:0.3
                                   options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:animations
                                completion:^(BOOL finished) {
                    dispatch_group_leave(self.animationDispatchGroup);
                }];
            });
            
            dispatch_group_wait(self.animationDispatchGroup, DISPATCH_TIME_FOREVER);
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            animations();
        });
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self checkRoomControlsAvailability];
    
    [self startObservingExpiredMessages];
    
    // Workaround for open conversations:
    // We can't get initial chat history until we join the conversation (since we are not a participant until then)
    // So for rooms that we don't know the last read message we wait until we join the room to get the initial chat history.
    if (!_hasReceiveInitialHistory && !_hasRequestedInitialHistory && _room.lastReadMessage > 0) {
        _hasRequestedInitialHistory = YES;
        [_chatController getInitialChatHistory];
    }
    
    _isVisible = YES;
    
    if (!_offlineMode) {
        [[NCRoomsManager sharedInstance] joinRoom:_room.token];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self savePendingMessage];
    [self saveLastReadMessage];
    [self stopVoiceMessagePlayer];
    
    _isVisible = NO;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // Leave chat when the view controller has been removed from its parent view.
    if (self.isMovingFromParentViewController) {
        [self leaveChat];
    }

    [_videoCallButton hideActivityIndicator];
    [_voiceCallButton hideActivityIndicator];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self setTitleView];
    }];
}

- (void)stopChat
{
    _hasStopped = YES;
    [_chatController stopChatController];
    [self cleanChat];
}

- (void)resumeChat
{
    _hasStopped = NO;
    if (!_hasReceiveInitialHistory && !_hasRequestedInitialHistory) {
        _hasRequestedInitialHistory = YES;
        [_chatController getInitialChatHistory];
    }
}

- (void)leaveChat
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_lobbyCheckTimer invalidate];
    [_messageExpirationTimer invalidate];
    [_chatController stopChatController];
    
    // If this chat view controller is for the same room as the one owned by the rooms manager
    // then we should not try to leave the chat. Since we will leave the chat when the
    // chat view controller owned by rooms manager moves from parent view controller.
    if ([[NCRoomsManager sharedInstance].chatViewController.room.token isEqualToString:_room.token] &&
        [NCRoomsManager sharedInstance].chatViewController != self) {
        return;
    }
    
    [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
    
    // Remove chat view controller pointer if this chat is owned by rooms manager
    // and the chat view is moving from parent view controller
    if ([NCRoomsManager sharedInstance].chatViewController == self) {
        [NCRoomsManager sharedInstance].chatViewController = nil;
    }
}

- (void)setChatMessage:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = message;
    });
}

#pragma mark - App lifecycle notifications

-(void)appDidBecomeActive:(NSNotification*)notification
{
    // Don't handle this event if the view is not loaded yet.
    // Otherwise we try to join the room and receive new messages while
    // viewDidLoad wasn't called, resulting in uninitialized dictionaries and crashes
    if (!self.isViewLoaded) {
        return;
    }

    // If we stopped the chat, we don't want to resume it here
    if (_hasStopped) {
        return;
    }

    // Check if new messages were added while the app was inactive (eg. via background-refresh)
    NCChatMessage *lastMessage = [[self->_messages objectForKey:[self->_dateSections lastObject]] lastObject];
    
    if (lastMessage) {
        [self.chatController checkForNewMessagesFromMessageId:lastMessage.messageId];
        [self checkLastCommonReadMessage];
    }
    
    if (!_offlineMode) {
        [[NCRoomsManager sharedInstance] joinRoom:_room.token];
    }
    
    [self startObservingExpiredMessages];
}

-(void)appWillResignActive:(NSNotification*)notification
{
    // If we stopped the chat, we don't want to change anything here
    if (_hasStopped) {
        return;
    }

    _hasReceiveNewMessages = NO;
    _startReceivingMessagesAfterJoin = YES;
    [self removeUnreadMessagesSeparator];
    [_chatController stopChatController];
    [_messageExpirationTimer invalidate];
    [[NCRoomsManager sharedInstance] leaveChatInRoom:_room.token];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
        [self.textView.layer setBorderColor:[UIColor systemGray4Color].CGColor];
        [self.textView setTintColor:[UIColor colorWithCGColor:[UIColor systemBlueColor].CGColor]];
        [self updateToolbar:YES];
    }
}

#pragma mark - Keyboard notifications

- (void)willShowKeyboard:(NSNotification *)notification
{
    UIResponder *currentResponder = [UIResponder slk_currentFirstResponder];
    // Skips if it's not the emoji text field
    if (currentResponder && ![currentResponder isKindOfClass:[EmojiTextField class]]) {
        return;
    }

    CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    [self updateViewToShowOrHideEmojiKeyboard:keyboardRect.size.height];
    NSIndexPath *indexPath = [self indexPathForMessage:_reactingMessage];
    if (indexPath) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGRect cellRect = [self.tableView rectForRowAtIndexPath:indexPath];
            // Only scroll if cell is not completely visible
            if (!CGRectContainsRect(self.tableView.bounds, cellRect)) {
                [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
            }
        });
    }
}

- (void)wllHideHideKeyboard:(NSNotification *)notification
{
    UIResponder *currentResponder = [UIResponder slk_currentFirstResponder];
    // Skips if it's not the emoji text field
    if (currentResponder && ![currentResponder isKindOfClass:[EmojiTextField class]]) {
        return;
    }
    
    [self updateViewToShowOrHideEmojiKeyboard:0.0];
    if (_lastMessageBeforeReaction && [NCUtils isValidIndexPath:_lastMessageBeforeReaction forTableView:self.tableView]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.tableView scrollToRowAtIndexPath:self->_lastMessageBeforeReaction atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        });
    }
}

#pragma mark - Connection Controller notifications

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    switch (connectionState) {
        case kConnectionStateConnected:
            if (_offlineMode) {
                _offlineMode = NO;
                _startReceivingMessagesAfterJoin = YES;
                
                [self removeOfflineFooterView];
                [[NCRoomsManager sharedInstance] joinRoom:_room.token];
            }
            break;
            
        default:
            break;
    }
}

#pragma mark - Configuration

- (void)setTitleView
{
    self.titleView = [[NCChatTitleView alloc] init];
    self.titleView.frame = CGRectMake(0, 0, MAXFLOAT, 30);
    [self.titleView.title addTarget:self action:@selector(titleButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    [_titleView.title setTitle:_room.displayName forState:UIControlStateNormal];
    
    // Set room image
    switch (_room.type) {
        case kNCRoomTypeOneToOne:
        {
            // Request user avatar to the server and set it if exist
            [_titleView.image setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                    placeholderImage:nil success:nil failure:nil];
        }
            break;
        case kNCRoomTypeGroup:
            [_titleView.image setImage:[UIImage imageNamed:@"group-15"]];
            [_titleView.image setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypePublic:
            [_titleView.image setImage:[UIImage imageNamed:@"public-15"]];
            [_titleView.image setContentMode:UIViewContentModeCenter];
            break;
        case kNCRoomTypeChangelog:
            [_titleView.image setImage:[UIImage imageNamed:@"changelog"]];
            break;
        default:
            break;
    }
    
    // Set objectType image
    if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [_titleView.image setImage:[UIImage imageNamed:@"file-conv-15"]];
        [_titleView.image setContentMode:UIViewContentModeCenter];
    } else if ([_room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
        [_titleView.image setImage:[UIImage imageNamed:@"pass-conv-15"]];
        [_titleView.image setContentMode:UIViewContentModeCenter];
    }
    
    _titleView.title.accessibilityHint = NSLocalizedString(@"Double tap to go to conversation information", nil);
    
    self.navigationItem.titleView = _titleView;
}

- (void)configureActionItems
{
    UIImage *videoCallImage = [[UIImage imageNamed:@"video"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *voiceCallImage = [[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    CGFloat buttonWidth = 24.0;
    CGFloat buttonPadding = 30.0;
    
    _videoCallButton = [[BarButtonItemWithActivity alloc] initWithWidth:buttonWidth withImage:videoCallImage];
    [_videoCallButton.innerButton addTarget:self action:@selector(videoCallButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    _videoCallButton.accessibilityLabel = NSLocalizedString(@"Video call", nil);
    _videoCallButton.accessibilityHint = NSLocalizedString(@"Double tap to start a video call", nil);
    
    
    _voiceCallButton = [[BarButtonItemWithActivity alloc] initWithWidth:buttonWidth withImage:voiceCallImage];
    [_voiceCallButton.innerButton addTarget:self action:@selector(voiceCallButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    _voiceCallButton.accessibilityLabel = NSLocalizedString(@"Voice call", nil);
    _voiceCallButton.accessibilityHint = NSLocalizedString(@"Double tap to start a voice call", nil);
    
    UIBarButtonItem *fixedSpace =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                    target:nil
                                                    action:nil];
    fixedSpace.width = buttonPadding;

    if ([[NCSettingsController sharedInstance] callsEnabledCapability]) {
        // Only register the call buttons when calling is enabled
        self.navigationItem.rightBarButtonItems = @[_videoCallButton, fixedSpace, _voiceCallButton];
    }
    
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySilentCall]) {
        [_voiceCallButton.innerButton addGestureRecognizer:[self longPressGestureForBarButtonItem]];
        [_videoCallButton.innerButton addGestureRecognizer:[self longPressGestureForBarButtonItem]];
    }
}

- (UILongPressGestureRecognizer *)longPressGestureForBarButtonItem
{
    UILongPressGestureRecognizer *barButtomItemsLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressInBarButtonItem:)];
    barButtomItemsLongPressGesture.delegate = self;
    return barButtomItemsLongPressGesture;
}

#pragma mark - User Interface

- (void)showVoiceMessageRecordButton
{
    [self.rightButton setTitle:@"" forState:UIControlStateNormal];
    [self.rightButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
    self.rightButton.tag = k_voice_record_button_tag;
    self.rightButton.accessibilityLabel = NSLocalizedString(@"Record voice message", nil);
    self.rightButton.accessibilityHint = NSLocalizedString(@"Tap and hold to record a voice message", nil);
}

- (void)showSendMessageButton
{
    [self.rightButton setTitle:@"" forState:UIControlStateNormal];
    [self.rightButton setImage:[UIImage imageNamed:@"send"] forState:UIControlStateNormal];
    self.rightButton.tag = k_send_message_button_tag;
    self.rightButton.accessibilityLabel = NSLocalizedString(@"Send message", nil);
    self.rightButton.accessibilityHint = NSLocalizedString(@"Double tap to send message", nil);
}

- (void)disableRoomControls
{
    _titleView.userInteractionEnabled = NO;

    [_videoCallButton hideActivityIndicator];
    [_voiceCallButton hideActivityIndicator];
    [_videoCallButton setEnabled:NO];
    [_voiceCallButton setEnabled:NO];
    
    [self.leftButton setEnabled:NO];
    [self.rightButton setEnabled:NO];
    self.textInputbar.userInteractionEnabled = NO;
}

- (void)checkRoomControlsAvailability
{
    if (_hasJoinedRoom) {
        // Enable room info, input bar and call buttons
        _titleView.userInteractionEnabled = YES;
        [_videoCallButton setEnabled:YES];
        [_voiceCallButton setEnabled:YES];
        
        [self.leftButton setEnabled:YES];
        [self.rightButton setEnabled:[self canPressRightButton]];
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
    } else if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatPermission] && (_room.permissions & NCPermissionChat) == 0) {
        // Hide text input
        self.textInputbarHidden = YES;
    } else if ([self isTextInputbarHidden]) {
        // Show text input if it was hidden in a previous state
        [self setTextInputbarHidden:NO animated:YES];
    }
    
    if (_presentedInCall) {
        // Remove call buttons
        self.navigationItem.rightBarButtonItems = nil;
    }
}

- (void)checkLobbyState
{
    if ([self shouldPresentLobbyView]) {
        NSString *placeHolderText = NSLocalizedString(@"You are currently waiting in the lobby", nil);
        // Lobby timer
        if (_room.lobbyTimer > 0) {
            NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
            NSString *meetingStart = [NCUtils readableDateTimeFromDate:date];
            placeHolderText = [placeHolderText stringByAppendingString:[NSString stringWithFormat:@"\n\n%@\n%@", NSLocalizedString(@"This meeting is scheduled for", @"The meeting start time will be displayed after this text e.g (This meeting is scheduled for tomorrow at 10:00)"), meetingStart]];
        }
        // Room description
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRoomDescription] && _room.roomDescription && ![_room.roomDescription isEqualToString:@""]) {
            placeHolderText = [placeHolderText stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", _room.roomDescription]];
        }
        // Only set it when text changes to avoid flickering in links
        if (![_chatBackgroundView.placeholderTextView.text isEqualToString:placeHolderText]) {
            [_chatBackgroundView.placeholderTextView setText:placeHolderText];
        }
        [_chatBackgroundView setImage:[UIImage imageNamed:@"lobby-placeholder"]];
        [_chatBackgroundView.placeholderView setHidden:NO];
        [_chatBackgroundView.loadingView stopAnimating];
        [_chatBackgroundView.loadingView setHidden:YES];
        // Clear current chat since chat history will be retrieve when lobby is disabled
        [self cleanChat];
    } else {
        [_chatBackgroundView.placeholderTextView setText:NSLocalizedString(@"No messages yet, start the conversation!", nil)];
        [_chatBackgroundView setImage:[UIImage imageNamed:@"chat-placeholder"]];
        [_chatBackgroundView.placeholderView setHidden:YES];
        [_chatBackgroundView.loadingView startAnimating];
        [_chatBackgroundView.loadingView setHidden:NO];
        // Stop checking lobby flag
        [_lobbyCheckTimer invalidate];
        // Retrieve initial chat history
        if (!_hasReceiveInitialHistory && !_hasRequestedInitialHistory) {
            _hasRequestedInitialHistory = YES;
            [_chatController getInitialChatHistory];
        }
    }
    [self checkRoomControlsAvailability];
}

- (void)setOfflineFooterView
{
    BOOL isAtBottom = [self shouldScrollOnNewMessages];
    
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 350, 24)];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.textColor = [UIColor secondaryLabelColor];
    footerLabel.font = [UIFont systemFontOfSize:12.0];
    footerLabel.backgroundColor = [UIColor clearColor];
    footerLabel.text = NSLocalizedString(@"Offline, only showing downloaded messages", nil);
    self.tableView.tableFooterView = footerLabel;
    self.tableView.tableFooterView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    
    if (isAtBottom) {
        [self.tableView slk_scrollToBottomAnimated:YES];
    }
}

- (void)removeOfflineFooterView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.tableView.tableFooterView) {
            [self.tableView.tableFooterView removeFromSuperview];
            self.tableView.tableFooterView = nil;
            
            // Scrolling after removing the tableFooterView won't scroll all the way to the bottom
            // therefore just keep the current position
            //[self.tableView slk_scrollToBottomAnimated:YES];
        }
    });
}

#pragma mark - Utils

- (NSInteger)getLastReadMessage
{
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker]) {
        return _lastReadMessage;
    }
    return 0;
}

- (NCChatMessage *)getFirstRealMessage
{
    for (int section = 0; section < [_dateSections count]; section++) {
        NSDate *dateSection = [_dateSections objectAtIndex:section];
        NSMutableArray *messagesInSection = [_messages objectForKey:dateSection];
        
        for (int message = 0; message < [messagesInSection count]; message++) {
            NCChatMessage *chatMessage = [messagesInSection objectAtIndex:message];
            
            // Ignore temporary messages
            if (chatMessage && chatMessage.messageId > 0) {
                return chatMessage;
            }
        }
    }
    
    return nil;
}

- (NSString *)getHeaderStringFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.doesRelativeDateFormatting = YES;
    return [formatter stringFromDate:date];
}

- (NSString *)createSendingMessage:(NSString *)text withMessageParameters:(NSDictionary *)messageParameters
{
    NSString *sendingMessage = [text copy];
    for (NSString *parameterKey in messageParameters.allKeys) {
        NCMessageParameter *parameter = [messageParameters objectForKey:parameterKey];
        sendingMessage = [sendingMessage stringByReplacingOccurrencesOfString:parameter.mentionDisplayName withString:parameter.mentionId];
    }
    return sendingMessage;
}

- (void)presentJoinError:(NSString *)alertMessage
{
    NSString *alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Could not join %@", nil), _room.displayName];
    if (_room.type == kNCRoomTypeOneToOne) {
        alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Could not join conversation with %@", nil), _room.displayName];
    }

    UIAlertController * alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                    message:alertMessage
                                                             preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

#pragma mark - Temporary messages

- (NCChatMessage *)createTemporaryMessage:(NSString *)message replyToMessage:(NCChatMessage *)parentMessage withMessageParameters:(NSString *)messageParameters
{
    NCChatMessage *temporaryMessage = [[NCChatMessage alloc] init];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    temporaryMessage.accountId = activeAccount.accountId;
    temporaryMessage.actorDisplayName = activeAccount.userDisplayName;
    temporaryMessage.actorId = activeAccount.userId;
    temporaryMessage.timestamp = [[NSDate date] timeIntervalSince1970];
    temporaryMessage.token = _room.token;
    temporaryMessage.message = [self replaceMentionsDisplayNamesWithMentionsKeysInMessage:message usingMessageParameters:messageParameters];
    NSString * referenceId = [NSString stringWithFormat:@"temp-%f",[[NSDate date] timeIntervalSince1970] * 1000];
    temporaryMessage.referenceId = [NCUtils sha1FromString:referenceId];
    temporaryMessage.internalId = referenceId;
    temporaryMessage.isTemporary = YES;
    temporaryMessage.parentId = parentMessage.internalId;
    temporaryMessage.messageParametersJSONString = messageParameters;

    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addObject:temporaryMessage];
    }];
    
    NCChatMessage *unmanagedTemporaryMessage = [[NCChatMessage alloc] initWithValue:temporaryMessage];
    return unmanagedTemporaryMessage;
}

- (NSString *)replaceMentionsDisplayNamesWithMentionsKeysInMessage:(NSString *)message usingMessageParameters:(NSString *)messageParameters
{
    NSString *resultMessage = [[message copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *messageParametersDict = [NCMessageParameter messageParametersDictFromJSONString:messageParameters];
    for (NSString *parameterKey in messageParametersDict.allKeys) {
        NCMessageParameter *parameter = [messageParametersDict objectForKey:parameterKey];
        NSString *parameterKeyString = [[NSString alloc] initWithFormat:@"{%@}", parameterKey];
        resultMessage = [resultMessage stringByReplacingOccurrencesOfString:parameter.mentionDisplayName withString:parameterKeyString];
    }
    return resultMessage;
}

- (NSString *)replaceMessageMentionsKeysWithMentionsDisplayNames:(NSString *)message usingMessageParameters:(NSString *)messageParameters
{
    NSString *resultMessage = [[message copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *messageParametersDict = [NCMessageParameter messageParametersDictFromJSONString:messageParameters];
    for (NSString *parameterKey in messageParametersDict.allKeys) {
        NCMessageParameter *parameter = [messageParametersDict objectForKey:parameterKey];
        NSString *parameterKeyString = [[NSString alloc] initWithFormat:@"{%@}", parameterKey];
        resultMessage = [resultMessage stringByReplacingOccurrencesOfString:parameterKeyString withString:parameter.mentionDisplayName];
    }
    return resultMessage;
}

- (void)appendTemporaryMessage:(NCChatMessage *)temporaryMessage
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger lastSectionBeforeUpdate = self->_dateSections.count - 1;
        NSMutableArray *messages = [[NSMutableArray alloc] initWithObjects:temporaryMessage, nil];
        [self appendMessages:messages inDictionary:self->_messages];
        
        NSMutableArray *messagesForLastDate = [self->_messages objectForKey:[self->_dateSections lastObject]];
        NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:self->_dateSections.count - 1];
        
        [self.tableView beginUpdates];
        NSInteger newLastSection = self->_dateSections.count - 1;
        BOOL newSection = lastSectionBeforeUpdate != newLastSection;
        if (newSection) {
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:newLastSection] withRowAnimation:UITableViewRowAnimationNone];
        } else {
            [self.tableView insertRowsAtIndexPaths:@[lastMessageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
        [self.tableView endUpdates];
        
        [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    });
}

- (void)removePermanentlyTemporaryMessage:(NCChatMessage *)temporaryMessage
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCChatMessage *managedTemporaryMessage = [NCChatMessage objectsWhere:@"referenceId = %@ AND isTemporary = true", temporaryMessage.referenceId].firstObject;
        if (managedTemporaryMessage) {
            [realm deleteObject:managedTemporaryMessage];
        }
    }];
    [self removeTemporaryMessages:@[temporaryMessage]];
}

- (void)removeTemporaryMessages:(NSArray *)messages
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NCChatMessage *message in messages) {
            NSIndexPath *indexPath = [self indexPathForMessage:message];
            if (indexPath) {
                [self removeMessageAtIndexPath:indexPath];
            }
        }
    });
}

- (void)setFailedStatusToMessageWithReferenceId:(NSString *)referenceId
{
    NSMutableArray *reloadIndexPaths = [NSMutableArray new];
    NSIndexPath *indexPath = [self indexPathForMessageWithReferenceId:referenceId];
    if (indexPath) {
        [reloadIndexPaths addObject:indexPath];
        
        // Set failed status
        NSDate *keyDate = [_dateSections objectAtIndex:indexPath.section];
        NSMutableArray *messages = [_messages objectForKey:keyDate];
        NCChatMessage *failedMessage = [messages objectAtIndex:indexPath.row];
        failedMessage.sendingFailed = YES;
    }
    
    [self.tableView beginUpdates];
    [self.tableView reloadRowsAtIndexPaths:reloadIndexPaths withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView endUpdates];
}

#pragma mark - Message expiration

- (void)startObservingExpiredMessages
{
    [_messageExpirationTimer invalidate];
    [self removeExpiredMessages];
    _messageExpirationTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(removeExpiredMessages) userInfo:nil repeats:YES];
}

- (void)removeExpiredMessages
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger currentTimestamp = [[NSDate date] timeIntervalSince1970];
        for (NSInteger i = 0; i < self->_dateSections.count; i++) {
            NSDate *keyDate = [self->_dateSections objectAtIndex:i];
            NSMutableArray *messages = [self->_messages objectForKey:keyDate];
            NSMutableArray *deleteMessages = [NSMutableArray new];
            for (NSInteger j = 0; j < messages.count; j++) {
                NCChatMessage *currentMessage = messages[j];
                NSInteger messageExpirationTime = currentMessage.expirationTimestamp;
                if (messageExpirationTime > 0 && messageExpirationTime <= currentTimestamp) {
                    [deleteMessages addObject:currentMessage];
                }
            }
            if (deleteMessages.count > 0) {
                [self.tableView beginUpdates];
                [messages removeObjectsInArray:deleteMessages];
                if (messages.count > 0) {
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:i] withRowAnimation:UITableViewRowAnimationTop];
                } else {
                    [self->_messages removeObjectForKey:keyDate];
                    [self sortDateSections];
                    [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:i] withRowAnimation:UITableViewRowAnimationTop];
                }
                [self.tableView endUpdates];
            }
        }
        [self->_chatController removeExpiredMessages];
    });
}

#pragma mark - Message updates

- (void)updateMessageWithMessageId:(NSInteger)messageId withMessage:(NCChatMessage *)updatedMessage
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isAtBottom = [self shouldScrollOnNewMessages];
        
        NSMutableArray *reloadIndexPaths = [NSMutableArray new];
        NSIndexPath *indexPath = [self indexPathForMessageWithMessageId:messageId];
        if (indexPath) {
            [reloadIndexPaths addObject:indexPath];
            NSDate *keyDate = [self->_dateSections objectAtIndex:indexPath.section];
            NSMutableArray *messages = [self->_messages objectForKey:keyDate];
            NCChatMessage *currentMessage = messages[indexPath.row];
            updatedMessage.isGroupMessage = currentMessage.isGroupMessage && ![currentMessage.actorType isEqualToString:@"bots"];
            messages[indexPath.row] = updatedMessage;
        }
        
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:reloadIndexPaths withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Make sure we're really at the bottom after updating a message
            if (isAtBottom) {
                [self.tableView slk_scrollToBottomAnimated:NO];
                [self updateToolbar:NO];
            }
        });
    });
}

#pragma mark - Action Methods

- (void)titleButtonPressed:(id)sender
{
    RoomInfoTableViewController *roomInfoVC = [[RoomInfoTableViewController alloc] initForRoom:_room fromChatViewController:self];
    NCSplitViewController *splitViewController = [NCUserInterfaceController sharedInstance].mainSplitViewController;

    if (splitViewController != nil && !splitViewController.isCollapsed) {
        roomInfoVC.modalPresentationStyle = UIModalPresentationPageSheet;
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:roomInfoVC];
        [self presentViewController:navController animated:YES completion:nil];
    } else {
        [self.navigationController pushViewController:roomInfoVC animated:YES];
    }
    
    // When returning from RoomInfoTableViewController the default keyboard will be shown, so the height might be wrong -> make sure the keyboard is hidden
    [self dismissKeyboard:YES];
}

- (void)unreadMessagesButtonPressed:(id)sender
{
    if (_firstUnreadMessage) {
        [self.tableView scrollToRowAtIndexPath:[self indexPathForMessage:_firstUnreadMessage] atScrollPosition:UITableViewScrollPositionNone animated:YES];
    }
}

- (void)videoCallButtonPressed:(id)sender
{
    [_videoCallButton showActivityIndicator];
    [[CallKitManager sharedInstance] startCall:_room.token withVideoEnabled:YES andDisplayName:_room.displayName silently:NO withAccountId:_room.accountId];
}

- (void)voiceCallButtonPressed:(id)sender
{
    [_voiceCallButton showActivityIndicator];
    [[CallKitManager sharedInstance] startCall:_room.token withVideoEnabled:NO andDisplayName:_room.displayName silently:NO withAccountId:_room.accountId];
}

- (void)handleLongPressInBarButtonItem:(UILongPressGestureRecognizer *)gestureRecognizer
{
    UIButton *button = (UIButton *)gestureRecognizer.view;
    BOOL isVoiceCallButton = button == self.voiceCallButton.innerButton;
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
        [self presentStartCallOptions:isVoiceCallButton];
    }
}

- (void)presentStartCallOptions:(BOOL)audioOnly
{
    UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Call options", nil)
                                                                                message:nil
                                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *silentCallAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Call without notification", nil)
                                                               style:UIAlertActionStyleDefault
                                                             handler:^void (UIAlertAction *action) {
        if (audioOnly) {
            [self->_voiceCallButton showActivityIndicator];
        } else {
            [self->_videoCallButton showActivityIndicator];
        }
        [[CallKitManager sharedInstance] startCall:self->_room.token withVideoEnabled:!audioOnly andDisplayName:self->_room.displayName
                                          silently:YES withAccountId:self->_room.accountId];
    }];
    [silentCallAction setValue:[[UIImage imageNamed:@"notifications-off"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    [optionsActionSheet addAction:silentCallAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.barButtonItem = audioOnly ? self.voiceCallButton : self.videoCallButton;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)sendChatMessage:(NSString *)message withParentMessage:(NCChatMessage *)parentMessage messageParameters:(NSString *)messageParameters silently:(BOOL)silently
{
    // Create temporary message
    NSString *referenceId = nil;
    
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReferenceId]) {
        NCChatMessage *temporaryMessage = [self createTemporaryMessage:message replyToMessage:parentMessage withMessageParameters:messageParameters];
        referenceId = temporaryMessage.referenceId;
        [self appendTemporaryMessage:temporaryMessage];
    }
    
    // Send message
    NSDictionary *messageParametersDict = [NCMessageParameter messageParametersDictFromJSONString:messageParameters];
    NSString *sendingText = [self createSendingMessage:message withMessageParameters:messageParametersDict];
    NSInteger replyTo = parentMessage ? parentMessage.messageId : -1;
    [_chatController sendChatMessage:sendingText replyTo:replyTo referenceId:referenceId silently:silently];
}

- (void)presentSendChatMessageOptions
{
    if (![[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySilentSend]) {return;}
    
    UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Send options", nil)
                                                                                message:nil
                                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *silentSendAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send without notification", nil)
                                                               style:UIAlertActionStyleDefault
                                                             handler:^void (UIAlertAction *action) {
        [self sendCurrentMessageSilently:YES];
    }];
    [silentSendAction setValue:[[UIImage imageNamed:@"notifications-off"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    [optionsActionSheet addAction:silentSendAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.textInputbar;
    optionsActionSheet.popoverPresentationController.sourceRect = self.rightButton.frame;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)sendCurrentMessageSilently:(BOOL)silently
{
    NCChatMessage *replyToMessage = _replyMessageView.isVisible ? _replyMessageView.message : nil;
    NSString *messageParameters = [NCMessageParameter messageParametersJSONStringFromDictionary:_mentionsDict];
    [self sendChatMessage:self.textView.text withParentMessage:replyToMessage messageParameters:messageParameters silently:silently];
    
    [_mentionsDict removeAllObjects];
    [_replyMessageView dismiss];
    [super didPressRightButton:self];
    [self clearPendingMessage];
}

- (BOOL)canPressRightButton
{
    BOOL canPress = [super canPressRightButton];
    
    if (!canPress && !_presentedInCall && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityVoiceMessage]) {
        [self showVoiceMessageRecordButton];
        return YES;
    }
    
    [self showSendMessageButton];
    
    return canPress;
}

- (void)didPressRightButton:(id)sender
{
    UIButton *button = sender;
    if (button.tag == k_send_message_button_tag) {
        [self sendCurrentMessageSilently:NO];
        [super didPressRightButton:sender];
    } else if (button.tag == k_voice_record_button_tag) {
        [self showVoiceMessageRecordHint];
    }
}

- (void)didPressLeftButton:(id)sender
{
    [self presentAttachmentsOptions];
    [super didPressLeftButton:sender];
}

- (void)presentAttachmentsOptions
{
    UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                                message:nil
                                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self checkAndPresentCamera];
    }];
    [cameraAction setValue:[[UIImage imageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *photoLibraryAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photo Library", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self presentPhotoLibrary];
    }];
    [photoLibraryAction setValue:[[UIImage imageNamed:@"photos"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *shareLocationAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Location", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self presentShareLocation];
    }];
    [shareLocationAction setValue:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *contactShareAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Contacts", nil)
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
        [self presentShareContact];
    }];
    [contactShareAction setValue:[[UIImage imageNamed:@"contact"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *filesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Files", nil)
                                                          style:UIAlertActionStyleDefault
                                                        handler:^void (UIAlertAction *action) {
        [self presentDocumentPicker];
    }];
    [filesAction setValue:[[UIImage imageNamed:@"files"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *ncFilesAction = [UIAlertAction actionWithTitle:filesAppName
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
        [self presentNextcloudFilesBrowser];
    }];
    [ncFilesAction setValue:[[UIImage imageNamed:@"logo-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    UIAlertAction *pollAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Poll", nil)
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
        [self presentPollCreation];
    }];
    [pollAction setValue:[[UIImage imageNamed:@"poll"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
    
    // Add actions
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        [optionsActionSheet addAction:cameraAction];
    }
    [optionsActionSheet addAction:photoLibraryAction];
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityTalkPolls] && _room.type != kNCRoomTypeOneToOne) {
        [optionsActionSheet addAction:pollAction];
    }
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityLocationSharing]) {
        [optionsActionSheet addAction:shareLocationAction];
    }
    [optionsActionSheet addAction:contactShareAction];
    [optionsActionSheet addAction:filesAction];
    [optionsActionSheet addAction:ncFilesAction];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.leftButton;
    optionsActionSheet.popoverPresentationController.sourceRect = self.leftButton.frame;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)presentNextcloudFilesBrowser
{
    DirectoryTableViewController *directoryVC = [[DirectoryTableViewController alloc] initWithPath:@"" inRoom:_room.token];
    NCNavigationController *fileSharingNC = [[NCNavigationController alloc] initWithRootViewController:directoryVC];
    [self presentViewController:fileSharingNC animated:YES completion:nil];
}

- (void)checkAndPresentCamera
{
    // https://stackoverflow.com/a/20464727/2512312
    NSString *mediaType = AVMediaTypeVideo;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    
    if(authStatus == AVAuthorizationStatusAuthorized) {
        [self presentCamera];
        return;
    } else if(authStatus == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            if(granted){
                [self presentCamera];
            }
        }];
        return;
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access camera", nil)
                                 message:NSLocalizedString(@"Camera access is not allowed. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

- (void)presentCamera
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_imagePicker = [[UIImagePickerController alloc] init];
        self->_imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        self->_imagePicker.cameraFlashMode = [NCUserDefaults preferredCameraFlashMode];
        self->_imagePicker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:self->_imagePicker.sourceType];
        self->_imagePicker.delegate = self;
        [self presentViewController:self->_imagePicker animated:YES completion:nil];
    });
}

- (void)presentPhotoLibrary
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_imagePicker = [[UIImagePickerController alloc] init];
        self->_imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        self->_imagePicker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:self->_imagePicker.sourceType];
        self->_imagePicker.delegate = self;
        [self presentViewController:self->_imagePicker animated:YES completion:nil];
    });
}

- (void)presentPollCreation
{
    PollCreationViewController *pollCreationVC = [[PollCreationViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    pollCreationVC.pollCreationDelegate = self;
    NCNavigationController *pollCreationNC = [[NCNavigationController alloc] initWithRootViewController:pollCreationVC];
    [self presentViewController:pollCreationNC animated:YES completion:nil];
}

- (void)presentShareLocation
{
    ShareLocationViewController *shareLocationVC = [[ShareLocationViewController alloc] init];
    shareLocationVC.delegate = self;
    NCNavigationController *shareLocationNC = [[NCNavigationController alloc] initWithRootViewController:shareLocationVC];
    [self presentViewController:shareLocationNC animated:YES completion:nil];
}

- (void)presentShareContact
{
    CNContactPickerViewController *contactPicker = [[CNContactPickerViewController alloc] init];
    contactPicker.delegate = self;
    [self presentViewController:contactPicker animated:YES completion:nil];
}

- (void)presentDocumentPicker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
        documentPicker.delegate = self;
        [self presentViewController:documentPicker animated:YES completion:nil];
    });
}

- (void)didPressReply:(NCChatMessage *)message {
    // Make sure we get a smooth animation after dismissing the context menu
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL isAtBottom = [self shouldScrollOnNewMessages];
        
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        self.replyMessageView = (ReplyMessageView *)self.typingIndicatorProxyView;
        [self.replyMessageView presentReplyViewWithMessage:message withUserId:activeAccount.userId];
        [self presentKeyboard:YES];

        // Make sure we're really at the bottom after showing the replyMessageView
        if (isAtBottom) {
            [self.tableView slk_scrollToBottomAnimated:NO];
            [self updateToolbar:NO];
        }
    });
}

- (void)didPressReplyPrivately:(NCChatMessage *)message {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:message.actorId forKey:@"actorId"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatViewControllerReplyPrivatelyNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)didPressAddReaction:(NCChatMessage *)message atIndexPath:(NSIndexPath *)indexPath {
    // Hide the keyboard because we are going to present the emoji keyboard
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.textView resignFirstResponder];
    });

    // Present emoji keyboard
    dispatch_async(dispatch_get_main_queue(), ^{
        self.reactingMessage = message;
        self.lastMessageBeforeReaction = [[self.tableView indexPathsForVisibleRows] lastObject];

        if ([NCUtils isiOSAppOnMac]) {
            // Move the emojiTextField to the position of the cell
            CGRect rowRect = [self.tableView rectForRowAtIndexPath:indexPath];
            CGRect convertedRowRect = [self.tableView convertRect:rowRect toView:self.view];

            // Show the emoji picker at the textView location of the cell
            convertedRowRect.origin.y += convertedRowRect.size.height - 16;
            convertedRowRect.origin.x += 54;

            // We don't want to have a clickable textField floating around
            convertedRowRect.size.width = 0;
            convertedRowRect.size.height = 0;

            // Remove and add the emojiTextField to the view, so the Mac OS emoji picker is always at the right location
            [self.emojiTextField removeFromSuperview];
            [self.emojiTextField setFrame:convertedRowRect];
            [self.view addSubview:self.emojiTextField];
        }

        [self.emojiTextField becomeFirstResponder];
    });
}

- (void)didPressForward:(NCChatMessage *)message {
    ShareViewController *shareViewController;
    
    if (message.isObjectShare) {
        shareViewController = [[ShareViewController alloc] initToForwardObjectShareMessage:message fromChatViewController:self];
    } else {
        shareViewController = [[ShareViewController alloc] initToForwardMessage:message.parsedMessage.string fromChatViewController:self];
    }
    shareViewController.delegate = self;
    NCNavigationController *forwardMessageNC = [[NCNavigationController alloc] initWithRootViewController:shareViewController];
    [self presentViewController:forwardMessageNC animated:YES completion:nil];
}

- (void)didPressResend:(NCChatMessage *)message {
    // Make sure there's no unread message separator, as the indexpath could be invalid after removing a message
    [self removeUnreadMessagesSeparator];
    
    [self removePermanentlyTemporaryMessage:message];
    NSString *sendingMessage = [self replaceMessageMentionsKeysWithMentionsDisplayNames:message.message usingMessageParameters:message.messageParametersJSONString];
    [self sendChatMessage:sendingMessage withParentMessage:message.parent messageParameters:message.messageParametersJSONString silently:NO];
}

- (void)didPressCopy:(NCChatMessage *)message {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = message.parsedMessage.string;
    [self.view makeToast:NSLocalizedString(@"Message copied", nil) duration:1.5 position:CSToastPositionCenter];
}

- (void) didPressTranscribeVoiceMessage:(NCChatMessage *) message {
    NCChatFileController *downloader = [[NCChatFileController alloc] init];
    downloader.delegate = self;
    downloader.messageType = kMessageTypeVoiceMessage;
    downloader.actionType = kActionTypeTranscribeVoiceMessage;
    [downloader downloadFileFromMessage:message.file];
}

- (void)didPressDelete:(NCChatMessage *)message {
    if (message.sendingFailed) {
        [self removePermanentlyTemporaryMessage:message];
    } else {
        // Set deleting state
        NCChatMessage *deletingMessage = [message copy];
        deletingMessage.message = NSLocalizedString(@"Deleting message", nil);
        deletingMessage.isDeleting = YES;
        [self updateMessageWithMessageId:deletingMessage.messageId withMessage:deletingMessage];
        // Delete message
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        [[NCAPIController sharedInstance] deleteChatMessageInRoom:self->_room.token withMessageId:message.messageId forAccount:activeAccount withCompletionBlock:^(NSDictionary *messageDict, NSError *error, NSInteger statusCode) {
            if (!error && messageDict) {
                if (statusCode == 202) {
                    [self.view makeToast:NSLocalizedString(@"Message deleted successfully, but Matterbridge is configured and the message might already be distributed to other services", nil) duration:5 position:CSToastPositionCenter];
                } else if (statusCode == 200) {
                    [self.view makeToast:NSLocalizedString(@"Message deleted successfully", nil) duration:3 position:CSToastPositionCenter];
                }
                NCChatMessage *deleteMessage = [NCChatMessage messageWithDictionary:[messageDict objectForKey:@"parent"] andAccountId:activeAccount.accountId];
                if (deleteMessage) {
                    [self updateMessageWithMessageId:deleteMessage.messageId withMessage:deleteMessage];
                }
            } else if (error) {
                if (statusCode == 400) {
                    [self.view makeToast:NSLocalizedString(@"Message could not be deleted because it is too old", nil) duration:5 position:CSToastPositionCenter];
                } else if (statusCode == 405) {
                    [self.view makeToast:NSLocalizedString(@"Only normal chat messages can be deleted", nil) duration:5 position:CSToastPositionCenter];
                } else {
                    [self.view makeToast:NSLocalizedString(@"An error occurred while deleting the message", nil) duration:5 position:CSToastPositionCenter];
                }
                // Set back original message on failure
                [self updateMessageWithMessageId:message.messageId withMessage:message];
            }
        }];
    }
}

- (void)didPressOpenInNextcloud:(NCChatMessage *)message {
    if (message.file) {
        [NCUtils openFileInNextcloudAppOrBrowser:message.file.path withFileLink:message.file.link];
    }
}

- (void)presentOptionsForMessageActor:(NCChatMessage *)message fromIndexPath:(NSIndexPath *)indexPath
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getUserActionsForUser:message.actorId usingAccount:activeAccount withCompletionBlock:^(NSDictionary *userActions, NSError *error) {
        if (!error) {
            NSArray *actions = [userActions objectForKey:@"actions"];
            if ([actions isKindOfClass:[NSArray class]]) {
                UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:message.actorDisplayName
                                                                                            message:nil
                                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
                for (NSDictionary *action in actions) {
                    NSString *appId = [action objectForKey:@"appId"];
                    NSString *title = [action objectForKey:@"title"];
                    NSString *link = [action objectForKey:@"hyperlink"];
                    
                    // Talk to user action
                    if ([appId isEqualToString:@"spreed"]) {
                        UIAlertAction *talkAction = [UIAlertAction actionWithTitle:title
                                                                             style:UIAlertActionStyleDefault
                                                                           handler:^void (UIAlertAction *action) {
                            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                            NSString *userId = [userActions objectForKey:@"userId"];
                            [userInfo setObject:userId forKey:@"actorId"];
                            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatViewControllerTalkToUserNotification
                                                                                object:self
                                                                              userInfo:userInfo];
                        }];
                        [talkAction setValue:[[UIImage imageNamed:@"navigationLogo"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
                        [optionsActionSheet addAction:talkAction];
                        continue;
                    }
                    
                    // Other user actions
                    UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                        NSURL *actionURL = [NSURL URLWithString:[link stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
                        [[UIApplication sharedApplication] openURL:actionURL options:@{} completionHandler:nil];
                    }];
                    
                    if ([appId isEqualToString:@"profile"]) {
                        [action setValue:[[UIImage imageNamed:@"user"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
                    } else if ([appId isEqualToString:@"email"]) {
                        [action setValue:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
                    }
                    
                    [optionsActionSheet addAction:action];
                }
                
                [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
                
                // Presentation on iPads
                optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
                CGRect cellRect = [self.tableView rectForRowAtIndexPath:indexPath];
                CGFloat avatarSize = kChatCellAvatarHeight + 10;
                CGRect avatarRect = CGRectMake(cellRect.origin.x, cellRect.origin.y, avatarSize, avatarSize);
                optionsActionSheet.popoverPresentationController.sourceRect = avatarRect;
                
                [self presentViewController:optionsActionSheet animated:YES completion:nil];
            }
        }
    }];
}

- (void)highlightMessageAtIndexPath:(NSIndexPath *)indexPath withScrollPosition:(UITableViewScrollPosition)scrollPosition
{
    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:scrollPosition];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    });
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == _emojiTextField && _reactingMessage) {
        _reactingMessage = nil;
        [textField resignFirstResponder];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (textField == _emojiTextField && string.isSingleEmoji && _reactingMessage) {
        [self addReaction:string toChatMessage:_reactingMessage];
        [textField resignFirstResponder];
    }
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (textField == _emojiTextField && _reactingMessage) {
        _reactingMessage = nil;
    }
}

#pragma mark - UIImagePickerController Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    [self saveImagePickerSettings:picker];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    ShareConfirmationViewController *shareConfirmationVC = [[ShareConfirmationViewController alloc] initWithRoom:_room account:activeAccount serverCapabilities:serverCapabilities];
    shareConfirmationVC.delegate = self;
    shareConfirmationVC.isModal = YES;
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:shareConfirmationVC];
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
        
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:navigationController animated:YES completion:^{
                [shareConfirmationVC.shareItemController addItemWithImage:image];
            }];
        }];
    } else if ([mediaType isEqualToString:@"public.movie"]) {
        NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
        
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:navigationController animated:YES completion:^{
                [shareConfirmationVC.shareItemController addItemWithURL:videoURL];
            }];
        }];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self saveImagePickerSettings:picker];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveImagePickerSettings:(UIImagePickerController *)picker
{
    if (picker.sourceType == UIImagePickerControllerSourceTypeCamera &&
        picker.cameraCaptureMode == UIImagePickerControllerCameraCaptureModePhoto) {
        [NCUserDefaults setPreferredCameraFlashMode:picker.cameraFlashMode];
    }
}

#pragma mark - UIDocumentPickerViewController Delegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    [self shareDocumentsWithURLs:urls fromController:controller];
}

- (void)shareDocumentsWithURLs:(NSArray<NSURL *> *)urls fromController:(UIDocumentPickerViewController *)controller {
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    ShareConfirmationViewController *shareConfirmationVC = [[ShareConfirmationViewController alloc] initWithRoom:_room account:activeAccount serverCapabilities:serverCapabilities];
    shareConfirmationVC.delegate = self;
    shareConfirmationVC.isModal = YES;
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:shareConfirmationVC];
    
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        [self presentViewController:navigationController animated:YES completion:^{
            for (NSURL* url in urls) {
                [shareConfirmationVC.shareItemController addItemWithURL:url];
            }
        }];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    
}

#pragma mark - ShareViewController Delegate

- (void)shareViewControllerDidCancel:(ShareViewController *)viewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - ShareConfirmationViewController Delegate

- (void)shareConfirmationViewControllerDidFailed:(ShareConfirmationViewController *)viewController
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (viewController.forwardingMessage) {
            [self.view makeToast:NSLocalizedString(@"Failed to forward message", nil) duration:1.5 position:CSToastPositionCenter];
        }
    }];
}

- (void)shareConfirmationViewControllerDidFinish:(ShareConfirmationViewController *)viewController
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (viewController.forwardingMessage) {
            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
            [userInfo setObject:viewController.room.token forKey:@"token"];
            [userInfo setObject:viewController.account.accountId forKey:@"accountId"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatViewControllerForwardNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    }];
}

#pragma mark - ShareLocationViewController Delegate

-(void)shareLocationViewController:(ShareLocationViewController *)viewController didSelectLocationWithLatitude:(double)latitude longitude:(double)longitude andName:(NSString *)name
{
    GeoLocationRichObject *richObject = [GeoLocationRichObject geoLocationRichObjectWithLatitude:latitude longitude:longitude name:name];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] shareRichObject:richObject.richObjectDictionary inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error sharing rich object: %@", error);
        }
    }];
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - CNContactPickerViewController Delegate

- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContact:(CNContact *)contact
{
    [self shareContact:contact];
}

#pragma mark - Contact sharing

- (void)shareContact:(CNContact *)contact
{
    NSError* error = nil;
    NSData* vCardData = [CNContactVCardSerialization dataWithContacts:@[contact] error:&error];
    NSString* vcString = [[NSString alloc] initWithData:vCardData encoding:NSUTF8StringEncoding];
    
    if (contact.imageData) {
        NSString* base64Image = [contact.imageData base64EncodedStringWithOptions:0];
        NSString* vcardImageString = [[@"PHOTO;TYPE=JPEG;ENCODING=BASE64:" stringByAppendingString:base64Image] stringByAppendingString:@"\n"];
        vcString = [vcString stringByReplacingOccurrencesOfString:@"END:VCARD" withString:[vcardImageString stringByAppendingString:@"END:VCARD"]];
    }
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *folderPath = [paths objectAtIndex:0];
    NSString *filePath = [folderPath stringByAppendingPathComponent:@"contact.vcf"];
    [vcString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *url = [NSURL fileURLWithPath:filePath];
    
    NSString *contactFileName = [NSString stringWithFormat:@"%@.vcf", contact.identifier];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] uniqueNameForFileUploadWithName:contactFileName originalName:YES forAccount:activeAccount withCompletionBlock:^(NSString *fileServerURL, NSString *fileServerPath, NSInteger errorCode, NSString *errorDescription) {
        if (fileServerURL && fileServerPath) {
            [self uploadFileAtPath:url.path withFileServerURL:fileServerURL andFileServerPath:fileServerPath withMetaData:nil];
        } else {
            NSLog(@"Could not find unique name for voice message file.");
        }
    }];
}

#pragma mark - Voice messages recording

- (void)showVoiceMessageRecordHint
{
    CGPoint toastPosition = CGPointMake(self.textInputbar.center.x, self.textInputbar.center.y - self.textInputbar.frame.size.height);
    [self.view makeToast:NSLocalizedString(@"Tap and hold to record a voice message, release the button to send it.", nil) duration:3 position:@(toastPosition)];
}

- (void)showVoiceMessageRecordingView
{
    _voiceMessageRecordingView = [[VoiceMessageRecordingView alloc] init];
    _voiceMessageRecordingView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.textInputbar addSubview:_voiceMessageRecordingView];
    [self.textInputbar bringSubviewToFront:_voiceMessageRecordingView];
    
    NSDictionary *views = @{@"voiceMessageRecordingView": _voiceMessageRecordingView};
    NSDictionary *metrics = @{@"buttonWidth": @(self.rightButton.frame.size.width)};
    [self.textInputbar addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[voiceMessageRecordingView]|" options:0 metrics:nil views:views]];
    [self.textInputbar addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[voiceMessageRecordingView(>=0)]-(buttonWidth)-|" options:0 metrics:metrics views:views]];
}

- (void)hideVoiceMessageRecordingView
{
    _voiceMessageRecordingView.hidden = YES;
}

- (void)setupAudioRecorder
{
    // Set the audio file
    NSArray *pathComponents = [NSArray arrayWithObjects:
                               [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                               @"voice-message-recording.m4a",
                               nil];
    NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];

    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

    // Define the recorder setting
    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];

    [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [recordSetting setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];

    // Initiate and prepare the recorder
    _recorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:nil];
    _recorder.delegate = self;
    _recorder.meteringEnabled = YES;
    [_recorder prepareToRecord];
}

- (void)checkPermissionAndRecordVoiceMessage
{
    NSString *mediaType = AVMediaTypeAudio;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    
    if(authStatus == AVAuthorizationStatusAuthorized) {
        [self startRecordingVoiceMessage];
        return;
    } else if(authStatus == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            NSLog(@"Microphone permission granted: %@", granted ? @"YES" : @"NO");
        }];
        return;
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access microphone", nil)
                                 message:NSLocalizedString(@"Microphone access is not allowed. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

- (void)startRecordingVoiceMessage
{
    [self setupAudioRecorder];
    [self showVoiceMessageRecordingView];
    if (!_recorder.recording) {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:YES error:nil];
        [_recorder record];
    }
}

- (void)stopRecordingVoiceMessage
{
    [self hideVoiceMessageRecordingView];
    if (_recorder.recording) {
        [_recorder stop];
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:NO error:nil];
    }
}

- (void)shareVoiceMessage
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH-mm-ss"];
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    // Replace chars that are not allowed on the filesystem
    NSCharacterSet *notAllowedCharSet = [NSCharacterSet characterSetWithCharactersInString:@"\\/:%"];
    NSString *roomString = [[_room.displayName componentsSeparatedByCharactersInSet: notAllowedCharSet] componentsJoinedByString: @" "];
    // Replace multiple spaces with 1
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"  +" options:NSRegularExpressionCaseInsensitive error:&error];
    roomString = [regex stringByReplacingMatchesInString:roomString options:0 range:NSMakeRange(0, [roomString length]) withTemplate:@" "];
    NSString *audioFileName = [NSString stringWithFormat:@"Talk recording from %@ (%@)", dateString, roomString];
    // Trim the file name if too long
    if ([audioFileName length] > 146) {
        audioFileName = [audioFileName substringWithRange:NSMakeRange(0, 146)];
    }
    audioFileName = [audioFileName stringByAppendingString:@".mp3"];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] uniqueNameForFileUploadWithName:audioFileName originalName:YES forAccount:activeAccount withCompletionBlock:^(NSString *fileServerURL, NSString *fileServerPath, NSInteger errorCode, NSString *errorDescription) {
        if (fileServerURL && fileServerPath) {
            NSDictionary *talkMetaData = @{@"messageType" : @"voice-message"};
            [self uploadFileAtPath:self->_recorder.url.path withFileServerURL:fileServerURL andFileServerPath:fileServerPath withMetaData:talkMetaData];
        } else {
            NSLog(@"Could not find unique name for voice message file.");
        }
    }];
}

- (void)uploadFileAtPath:(NSString *)localPath withFileServerURL:(NSString *)fileServerURL andFileServerPath:(NSString *)fileServerPath withMetaData:(NSDictionary *)talkMetaData
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] setupNCCommunicationForAccount:activeAccount];
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:localPath dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil queue:dispatch_get_main_queue() taskHandler:^(NSURLSessionTask *task) {
        NSLog(@"Upload task");
    } progressHandler:^(NSProgress *progress) {
        NSLog(@"Progress:%f", progress.fractionCompleted);
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSDictionary *allHeaderFields, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);

        if (errorCode == 0) {
            [[NCAPIController sharedInstance] shareFileOrFolderForAccount:activeAccount atPath:fileServerPath toRoom:self->_room.token talkMetaData:talkMetaData withCompletionBlock:^(NSError *error) {
                if (error) {
                    NSLog(@"Failed to share voice message");
                }
            }];
        } else if (errorCode == 404 || errorCode == 409) {
            [[NCAPIController sharedInstance] checkOrCreateAttachmentFolderForAccount:activeAccount withCompletionBlock:^(BOOL created, NSInteger errorCode) {
                if (created) {
                    [self uploadFileAtPath:localPath withFileServerURL:fileServerURL andFileServerPath:fileServerPath withMetaData:talkMetaData];
                } else {
                    NSLog(@"Failed to check or create attachment folder");
                }
            }];
        } else {
            NSLog(@"Failed upload voice message");
        }
    }];
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
    if (flag && recorder == _recorder && !_recordCancelled) {
        [self shareVoiceMessage];
    }
}

#pragma mark - Voice Messages Transcribe

- (void) transcribeVoiceMessageWithAudioFileStatus:(NCChatFileStatus *)fileStatus
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *audioFileUrl = [[NSURL alloc] initFileURLWithPath:fileStatus.fileLocalPath];
        VoiceMessageTranscribeViewController *viewController = [[VoiceMessageTranscribeViewController alloc] initWithAudiofileUrl:audioFileUrl];
        NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:viewController];

        [self presentViewController:navigationController animated:YES completion:nil];
    });
}

#pragma mark - Voice Messages Player

- (void)setupVoiceMessagePlayerWithAudioFileStatus:(NCChatFileStatus *)fileStatus
{
    NSData *data = [NSData dataWithContentsOfFile:fileStatus.fileLocalPath];
    NSError *error;
    _voiceMessagesPlayer = [[AVAudioPlayer alloc] initWithData:data error:&error];
    _voiceMessagesPlayer.delegate = self;
    if (!error) {
        _playerAudioFileStatus = fileStatus;
        [self playVoiceMessagePlayer];
    } else {
        NSLog(@"Error: %@", error);
    }
}

- (void)playVoiceMessagePlayer
{
    if (!_presentedInCall) {
        [self setSpeakerAudioSession];
        [self enableProximitySensor];
    }
    
    [self startVoiceMessagePlayerTimer];
    [_voiceMessagesPlayer play];
}

- (void)pauseVoiceMessagePlayer
{
    if (!_presentedInCall) {
        [self disableProximitySensor];
    }
    
    [self stopVoiceMessagePlayerTimer];
    [_voiceMessagesPlayer pause];
    [self checkVisibleCellAudioPlayers];
}

- (void)stopVoiceMessagePlayer
{
    if (!_presentedInCall) {
        [self disableProximitySensor];
    }
    
    [self stopVoiceMessagePlayerTimer];
    [_voiceMessagesPlayer stop];
}

- (void)enableProximitySensor
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:)
                                                 name:UIDeviceProximityStateDidChangeNotification object:nil];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
}

- (void)disableProximitySensor
{
    if ([[UIDevice currentDevice] proximityState] == NO) {
        // Only disable monitoring if proximity sensor state is not active.
        // If not proximity sensor state is cached as active and next time we enable monitoring
        // sensorStateChange won't be trigger until proximity sensor state changes to inactive.
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceProximityStateDidChangeNotification object:nil];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    }
}

- (void)setSpeakerAudioSession
{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    [session setActive:YES error:nil];
}

- (void)setVoiceChatAudioSession
{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:0 error:nil];
    [session setActive:YES error:nil];
}

- (void)sensorStateChange:(NSNotificationCenter *)notification
{
    if (_presentedInCall) {
        return;
    }
    
    if ([[UIDevice currentDevice] proximityState] == YES) {
        [self setVoiceChatAudioSession];
    } else {
        [self pauseVoiceMessagePlayer];
        [self setSpeakerAudioSession];
        [self disableProximitySensor];
    }
}

- (void)checkVisibleCellAudioPlayers
{
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        if (message.isVoiceMessage) {
            VoiceMessageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (message.file && [message.file.parameterId isEqualToString:_playerAudioFileStatus.fileId] && [message.file.path isEqualToString:_playerAudioFileStatus.filePath]) {
                [cell setPlayerProgress:_voiceMessagesPlayer.currentTime isPlaying:_voiceMessagesPlayer.isPlaying maximumValue:_voiceMessagesPlayer.duration];
                continue;
            }
            [cell resetPlayer];
        }
    }
}

- (void)startVoiceMessagePlayerTimer
{
    [self stopVoiceMessagePlayerTimer];
    _playerProgressTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(checkVisibleCellAudioPlayers) userInfo:nil repeats:YES];
}

- (void)stopVoiceMessagePlayerTimer
{
    [_playerProgressTimer invalidate];
    _playerProgressTimer = nil;
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self stopVoiceMessagePlayerTimer];
    [self checkVisibleCellAudioPlayers];
    [self disableProximitySensor];
}

#pragma mark - Gesture recognizer

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    BOOL shouldBegin = [super gestureRecognizerShouldBegin:gestureRecognizer];
    if (gestureRecognizer == self.voiceMessageLongPressGesture) {
        return YES;
    }
    return shouldBegin;
}

- (void)handleLongPressInVoiceMessageRecordButton:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (self.rightButton.tag != k_voice_record_button_tag) {
        if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
            [self presentSendChatMessageOptions];
        }
        return;
    }
    
    CGPoint point = [gestureRecognizer locationInView:self.view];
    
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
        NSLog(@"Start recording audio message");
        // 'Pop' feedback (strong boom)
        AudioServicesPlaySystemSound(1520);
        [self checkPermissionAndRecordVoiceMessage];
        [self shouldLockInterfaceOrientation:YES];
        _recordCancelled = NO;
        _longPressStartingPoint = point;
        _cancelHintLabelInitialPositionX = _voiceMessageRecordingView.slideToCancelHintLabel.frame.origin.x;
    } else if ([gestureRecognizer state] == UIGestureRecognizerStateEnded) {
        NSLog(@"Stop recording audio message");
        [self shouldLockInterfaceOrientation:NO];
        [self stopRecordingVoiceMessage];
    } else if ([gestureRecognizer state] == UIGestureRecognizerStateChanged) {
        CGFloat slideX = _longPressStartingPoint.x - point.x;
        // Only slide view to the left
        if (slideX > 0) {
            CGFloat maxSlideX = 100;
            CGRect labelFrame = _voiceMessageRecordingView.slideToCancelHintLabel.frame;
            labelFrame = CGRectMake(_cancelHintLabelInitialPositionX - slideX, labelFrame.origin.y, labelFrame.size.width, labelFrame.size.height);
            _voiceMessageRecordingView.slideToCancelHintLabel.frame = labelFrame;
            [_voiceMessageRecordingView.slideToCancelHintLabel setAlpha:(maxSlideX - slideX) / 100];
            // Cancel recording if slided more than maxSlideX
            if (slideX > maxSlideX && !_recordCancelled) {
                NSLog(@"Cancel recording audio message");
                // 'Cancelled' feedback (three sequential weak booms)
                AudioServicesPlaySystemSound(1521);
                _recordCancelled = YES;
                [self stopRecordingVoiceMessage];
            }
        }
    } else if ([gestureRecognizer state] == UIGestureRecognizerStateCancelled || [gestureRecognizer state] == UIGestureRecognizerStateFailed) {
        NSLog(@"Gesture cancelled or failed -> Cancel recording audio message");
        [self shouldLockInterfaceOrientation:NO];
        _recordCancelled = YES;
        [self stopRecordingVoiceMessage];
    }
}

- (void)shouldLockInterfaceOrientation:(BOOL)lock
{
    AppDelegate *appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    appDelegate.shouldLockInterfaceOrientation = lock;
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if ([scrollView isEqual:self.tableView] && scrollView.contentOffset.y < 0) {
        if ([self couldRetireveHistory]) {
            NCChatMessage *firstMessage = [self getFirstRealMessage];
            if (firstMessage && [_chatController hasHistoryFromMessageId:firstMessage.messageId]) {
                _retrievingHistory = YES;
                [self showLoadingHistoryView];
                if (_offlineMode) {
                    [_chatController getHistoryBatchOfflineFromMessagesId:firstMessage.messageId];
                } else {
                    [_chatController getHistoryBatchFromMessagesId:firstMessage.messageId];
                }
            }
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [super scrollViewDidEndDecelerating:scrollView];
    
    if ([scrollView isEqual:self.tableView]) {
        if (_firstUnreadMessage) {
            [self checkUnreadMessagesVisibility];
        }
        
        [self updateToolbar:YES];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [super scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    
    if ([scrollView isEqual:self.tableView]) {
        if (!decelerate && _firstUnreadMessage) {
            [self checkUnreadMessagesVisibility];
        }
        
        [self updateToolbar:YES];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    if ([scrollView isEqual:self.tableView]) {
        if (_firstUnreadMessage) {
            [self checkUnreadMessagesVisibility];
        }
        
        [self updateToolbar:YES];
    }
}

#pragma mark - UITextViewDelegate Methods

- (BOOL)textView:(SLKTextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    // Do not allow to type while recording
    if (_voiceMessageLongPressGesture.state != UIGestureRecognizerStatePossible) {
        return NO;
    }
    
    if ([text isEqualToString:@""]) {
        UITextRange *selectedRange = [textView selectedTextRange];
        NSInteger cursorOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:selectedRange.start];
        NSString *text = textView.text;
        NSString *substring = [text substringToIndex:cursorOffset];
        NSMutableString *lastPossibleMention = [[[substring componentsSeparatedByString:@"@"] lastObject] mutableCopy];
        [lastPossibleMention insertString:@"@" atIndex:0];
        for (NSString *mentionKey in _mentionsDict.allKeys) {
            NCMessageParameter *mentionParameter = [_mentionsDict objectForKey:mentionKey];
            if ([lastPossibleMention isEqualToString:mentionParameter.mentionDisplayName]) {
                // Delete mention
                NSRange range = NSMakeRange(cursorOffset - lastPossibleMention.length, lastPossibleMention.length);
                textView.text = [[self.textView text] stringByReplacingCharactersInRange:range withString:@""];
                // Only delete it from mentionsDict if there are no more mentions for that user/room
                // User could have manually added the mention without selecting it from autocompletion
                // so no mention was added to the mentionsDict
                if ([textView.text rangeOfString:lastPossibleMention].location != NSNotFound) {
                    [_mentionsDict removeObjectForKey:mentionKey];
                }
                return YES;
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
    
    if (!_hasStopped) {
        [self checkLobbyState];
    }
}

- (void)didJoinRoom:(NSNotification *)notification
{
    NSString *token = [notification.userInfo objectForKey:@"token"];
    if (![token isEqualToString:_room.token]) {
        return;
    }
    
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (error && _isVisible) {
        _offlineMode = YES;
        [self setOfflineFooterView];
        [_chatController stopReceivingNewChatMessages];
        [self presentJoinError:[notification.userInfo objectForKey:@"errorReason"]];
        return;
    }
    
    _hasJoinedRoom = YES;
    [self checkRoomControlsAvailability];
    
    if (_hasStopped) {
        return;
    }
    
    if (_startReceivingMessagesAfterJoin && _hasReceiveInitialHistory) {
        _startReceivingMessagesAfterJoin = NO;
        [_chatController startReceivingNewChatMessages];
    } else if (!_hasReceiveInitialHistory && !_hasRequestedInitialHistory) {
        _hasRequestedInitialHistory = YES;
        [_chatController getInitialChatHistory];
    }
}

- (void)didLeaveRoom:(NSNotification *)notification
{
    [self disableRoomControls];
}

#pragma mark - CallKit Manager notifications

- (void)didFailRequestingCallTransaction:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (![roomToken isEqualToString:_room.token]) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureActionItems];
    });
}

#pragma mark - Chat Controller notifications

- (void)didReceiveInitialChatHistory:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notification.object != self->_chatController) {
            return;
        }
        
        NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
        if (messages.count > 0) {
            NSIndexPath *indexPathUnreadMessageSeparator;
            int lastMessageIndex = (int)[messages count] - 1;
            NCChatMessage *lastMessage = [messages objectAtIndex:lastMessageIndex];
            
            [self appendMessages:messages inDictionary:self->_messages];
            
            if (lastMessage && lastMessage.messageId > self->_lastReadMessage) {
                // Iterate backwards to find the correct location for the unread message separator
                for (NSInteger sectionIndex = (self->_dateSections.count - 1); sectionIndex >= 0; sectionIndex--) {
                    NSDate *dateSection = [self->_dateSections objectAtIndex:sectionIndex];
                    NSMutableArray *messagesInSection = [self->_messages objectForKey:dateSection];
                    
                    for (NSInteger messageIndex = (messagesInSection.count - 1); messageIndex >= 0; messageIndex--) {
                        NCChatMessage *chatMessage = [messagesInSection objectAtIndex:messageIndex];
                        
                        if (chatMessage && chatMessage.messageId <= self->_lastReadMessage) {
                            // Insert unread message separator after the current message
                            [messagesInSection insertObject:self->_unreadMessagesSeparator atIndex:(messageIndex + 1)];
                            [self->_messages setObject:messagesInSection forKey:dateSection];
                            indexPathUnreadMessageSeparator = [NSIndexPath indexPathForRow:(messageIndex + 1) inSection:sectionIndex];
                            
                            break;
                        }
                    }
                    
                    if (indexPathUnreadMessageSeparator) {
                        break;
                    }
                }
                
                // Set last received message as last read message
                self->_lastReadMessage = lastMessage.messageId;
            }
            
            NSMutableArray *storedTemporaryMessages = [self->_chatController getTemporaryMessages];
            if (storedTemporaryMessages.count > 0) {
                [self insertMessages:storedTemporaryMessages];
                
                if (indexPathUnreadMessageSeparator) {
                    // It is possible that temporary messages are added which add new sections
                    // In this case the indexPath of the unreadMessageSeparator would be invalid and could lead to a crash
                    // Therefore we need to make sure we got the correct indexPath here
                    indexPathUnreadMessageSeparator = [self getIndexPathOfUnreadMessageSeparator];
                }
            }
            
            [self.tableView reloadData];
            
            if (indexPathUnreadMessageSeparator) {
                [self.tableView scrollToRowAtIndexPath:indexPathUnreadMessageSeparator atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            } else {
                [self.tableView slk_scrollToBottomAnimated:NO];
            }
            [self updateToolbar:NO];
        } else {
            [self->_chatBackgroundView.placeholderView setHidden:NO];
        }
        
        self->_hasReceiveInitialHistory = YES;
        
        NSError *error = [notification.userInfo objectForKey:@"error"];
        if (!error) {
            [self->_chatController startReceivingNewChatMessages];
        } else {
            self->_offlineMode = YES;
            [self->_chatController getInitialChatHistoryForOfflineMode];
        }
    });
}

- (void)didReceiveInitialChatHistoryOffline:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notification.object != self->_chatController) {
            return;
        }
        
        NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
        if (messages.count > 0) {
            [self appendMessages:messages inDictionary:self->_messages];
            [self setOfflineFooterView];
            [self.tableView reloadData];
            [self.tableView slk_scrollToBottomAnimated:NO];
            [self updateToolbar:NO];
        } else {
            [self->_chatBackgroundView.placeholderView setHidden:NO];
        }
        
        NSMutableArray *storedTemporaryMessages = [self->_chatController getTemporaryMessages];
        if (storedTemporaryMessages.count > 0) {
            [self insertMessages:storedTemporaryMessages];
            [self.tableView reloadData];
            [self.tableView slk_scrollToBottomAnimated:NO];
            [self updateToolbar:NO];
        }
    });
}

- (void)didReceiveChatHistory:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notification.object != self->_chatController) {
            return;
        }
        
        NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
        BOOL shouldAddBlockSeparator = [[notification.userInfo objectForKey:@"shouldAddBlockSeparator"] boolValue];
        if (messages.count > 0) {
            NSIndexPath *lastHistoryMessageIP = [self prependMessages:messages addingBlockSeparator:shouldAddBlockSeparator];
            [self.tableView reloadData];
            
            if ([NCUtils isValidIndexPath:lastHistoryMessageIP forTableView:self.tableView]) {
                [self.tableView scrollToRowAtIndexPath:lastHistoryMessageIP atScrollPosition:UITableViewScrollPositionTop animated:NO];
            }
        }
        
        BOOL noMoreStoredHistory = [[notification.userInfo objectForKey:@"noMoreStoredHistory"] boolValue];
        if (noMoreStoredHistory) {
            self->_hasStoredHistory = NO;
        }
        self->_retrievingHistory = NO;
        [self hideLoadingHistoryView];
    });
}

- (void)didReceiveChatMessages:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = [notification.userInfo objectForKey:@"error"];
        if (notification.object != self->_chatController || error) {
            return;
        }
        
        BOOL firstNewMessagesAfterHistory = !self->_hasReceiveNewMessages;
        self->_hasReceiveNewMessages = YES;
        
        NSMutableArray *messages = [notification.userInfo objectForKey:@"messages"];
        if (messages.count > 0) {
            // Detect if we should scroll to new messages before we issue a reloadData
            // Otherwise longer messages will prevent scrolling
            BOOL shouldScrollOnNewMessages = [self shouldScrollOnNewMessages] ;
            
            BOOL newMessagesContainVisibleMessages = [self messagesContainVisibleMessages:messages];
            // Check if unread messages separator should be added (only if it's not already shown)
            NSIndexPath *indexPathUnreadMessageSeparator;
            if (firstNewMessagesAfterHistory && [self getLastReadMessage] > 0 && ![self getIndexPathOfUnreadMessageSeparator] && newMessagesContainVisibleMessages) {
                NSMutableArray *messagesForLastDateBeforeUpdate = [self->_messages objectForKey:[self->_dateSections lastObject]];
                [messagesForLastDateBeforeUpdate addObject:self->_unreadMessagesSeparator];
                indexPathUnreadMessageSeparator = [NSIndexPath indexPathForRow:messagesForLastDateBeforeUpdate.count - 1 inSection: self->_dateSections.count - 1];
                [self->_messages setObject:messagesForLastDateBeforeUpdate forKey:[self->_dateSections lastObject]];
            }
            
            // Sort received messages
            [self appendMessages:messages inDictionary:self->_messages];
            
            NSMutableArray *messagesForLastDate = [self->_messages objectForKey:[self->_dateSections lastObject]];
            NSIndexPath *lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:self->_dateSections.count - 1];
            
            // Load messages in chat view
            [self.tableView reloadData];
            
            BOOL newMessagesContainUserMessage = [self newMessagesContainUserMessage:messages];
            // Remove unread messages separator when user writes a message
            if (newMessagesContainUserMessage) {
                [self removeUnreadMessagesSeparator];
                indexPathUnreadMessageSeparator = nil;
                // Update last message index path
                lastMessageIndexPath = [NSIndexPath indexPathForRow:messagesForLastDate.count - 1 inSection:self->_dateSections.count - 1];
            }
            
            NCChatMessage *firstNewMessage = [messages objectAtIndex:0];
            // This variable is needed since several calls to receiveMessages API might be needed
            // (if the number of unread messages is bigger than the "limit" in receiveMessages request)
            // to receive all the unread messages.
            BOOL areReallyNewMessages = firstNewMessage.timestamp >= self->_chatViewPresentedTimestamp;
            
            // Position chat view
            if (indexPathUnreadMessageSeparator) {
                // Dispatch it in the next cycle so reloadData is always completed.
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSIndexPath *indexPath = [self getIndexPathOfUnreadMessageSeparator];
                    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                });
            } else if (shouldScrollOnNewMessages || newMessagesContainUserMessage) {
                [self.tableView scrollToRowAtIndexPath:lastMessageIndexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
            } else if (!self->_firstUnreadMessage && areReallyNewMessages && newMessagesContainVisibleMessages) {
                [self showNewMessagesViewUntilMessage:firstNewMessage];
            }
            
            // Set last received message as last read message
            NCChatMessage *lastReceivedMessage = [messages objectAtIndex:messages.count - 1];
            self->_lastReadMessage = lastReceivedMessage.messageId;
        }
        
        if (firstNewMessagesAfterHistory) {
            [self->_chatBackgroundView.loadingView stopAnimating];
            [self->_chatBackgroundView.loadingView setHidden:YES];
        }
        
        if (self->_highlightMessageId) {
            NSIndexPath *indexPath = [self indexPathForMessageWithMessageId:self->_highlightMessageId];
            if (indexPath) {
                [self highlightMessageAtIndexPath:indexPath withScrollPosition:UITableViewScrollPositionMiddle];
            }
            self->_highlightMessageId = 0;
        }
    });
}

- (void)didSendChatMessage:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notification.object != self->_chatController) {
            return;
        }
        
        NSError *error = [notification.userInfo objectForKey:@"error"];
        NSString *message = [notification.userInfo objectForKey:@"message"];
        NSString *referenceId = [notification.userInfo objectForKey:@"referenceId"];
        if (error) {
            if (referenceId) {
                [self setFailedStatusToMessageWithReferenceId:referenceId];
            } else {
                self.textView.text = message;
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"Could not send the message", nil)
                                             message:NSLocalizedString(@"An error occurred while sending the message", nil)
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* okButton = [UIAlertAction
                                           actionWithTitle:NSLocalizedString(@"OK", nil)
                                           style:UIAlertActionStyleDefault
                                           handler:nil];
                
                [alert addAction:okButton];
                [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
            }
        }
    });
}

- (void)didReceiveChatBlocked:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    
    [self startObservingRoomLobbyFlag];
}

- (void)didReceiveNewerCommonReadMessage:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    
    [self checkLastCommonReadMessage];
}

- (void)didReceiveCallStartedMessage:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    _room.hasCall = YES;
    [self checkRoomControlsAvailability];
}

- (void)didReceiveCallEndedMessage:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    _room.hasCall = NO;
    [self checkRoomControlsAvailability];
}

- (void)didReceiveUpdateMessage:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    
    NCChatMessage *message = [notification.userInfo objectForKey:@"updateMessage"];
    NCChatMessage *deleteMessage = message.parent;
    if (deleteMessage) {
        [self updateMessageWithMessageId:deleteMessage.messageId withMessage:deleteMessage];
    }
}

- (void)didReceiveHistoryCleared:(NSNotification *)notification
{
    if (notification.object != _chatController) {
        return;
    }
    
    NCChatMessage *message = [notification.userInfo objectForKey:@"historyCleared"];
    if ([_chatController hasOlderStoredMessagesThanMessageId:message.messageId]) {
        [self cleanChat];
        [_chatController clearHistoryAndResetChatController];
        _hasRequestedInitialHistory = YES;
        [_chatController getInitialChatHistory];
    }
}

#pragma mark - Lobby functions

- (void)startObservingRoomLobbyFlag
{
    [self updateRoomInformation];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lobbyCheckTimer invalidate];
        self->_lobbyCheckTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(updateRoomInformation) userInfo:nil repeats:YES];
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

- (NSIndexPath *)prependMessages:(NSMutableArray *)historyMessages addingBlockSeparator:(BOOL)shouldAddBlockSeparator
{
    NSMutableDictionary *historyDict = [[NSMutableDictionary alloc] init];
    [self appendMessages:historyMessages inDictionary:historyDict];
    
    NSDate *chatSection = nil;
    NSMutableArray *historyMessagesForSection = nil;
    // Sort history sections
    NSMutableArray *historySections = [NSMutableArray arrayWithArray:historyDict.allKeys];
    [historySections sortUsingSelector:@selector(compare:)];
    
    // Add every section in history that can't be merged with current chat messages
    for (NSDate *historySection in historySections) {
        historyMessagesForSection = [historyDict objectForKey:historySection];
        chatSection = [self getKeyForDate:historySection inDictionary:_messages];
        if (!chatSection) {
            [_messages setObject:historyMessagesForSection forKey:historySection];
        }
    }
    
    [self sortDateSections];
    
    if (shouldAddBlockSeparator) {
        // Chat block separator
        NCChatMessage *blockSeparatorMessage = [[NCChatMessage alloc] init];
        blockSeparatorMessage.messageId = kChatBlockSeparatorIdentifier;
        [historyMessagesForSection addObject:blockSeparatorMessage];
    }
    
    NSMutableArray *lastHistoryMessages = [historyDict objectForKey:[historySections lastObject]];
    NSIndexPath *lastHistoryMessageIP = [NSIndexPath indexPathForRow:lastHistoryMessages.count - 1 inSection:historySections.count - 1];
    
    // Merge last section of history messages with first section in current chat
    if (chatSection) {
        NSMutableArray *chatMessages = [_messages objectForKey:chatSection];
        NCChatMessage *lastHistoryMessage = [historyMessagesForSection lastObject];
        NCChatMessage *firstChatMessage = [chatMessages firstObject];
        firstChatMessage.isGroupMessage = [self shouldGroupMessage:firstChatMessage withMessage:lastHistoryMessage];
        [historyMessagesForSection addObjectsFromArray:chatMessages];
        [_messages setObject:historyMessagesForSection forKey:chatSection];
    }
    
    return lastHistoryMessageIP;
}

- (void)appendMessages:(NSMutableArray *)messages inDictionary:(NSMutableDictionary *)dictionary
{
    for (NCChatMessage *newMessage in messages) {
        NSDate *newMessageDate = [NSDate dateWithTimeIntervalSince1970: newMessage.timestamp];
        NSDate *keyDate = [self getKeyForDate:newMessageDate inDictionary:dictionary];
        NSMutableArray *messagesForDate = [dictionary objectForKey:keyDate];

        if (messagesForDate) {
            BOOL messageUpdated = NO;
            
            // Check if we can update the message instead of adding a new one
            for (int i = 0; i < messagesForDate.count; i++) {
                NCChatMessage *currentMessage = messagesForDate[i];
                if ((!currentMessage.isTemporary && currentMessage.messageId == newMessage.messageId) ||
                    (currentMessage.isTemporary && [currentMessage.referenceId isEqualToString:newMessage.referenceId])) {
                    // The newly received message either already exists or its temporary counterpart exists -> update
                    // If the user type a command the newMessage.actorType will be "bots", then we should not group those messages
                    // even if the original message was grouped.
                    newMessage.isGroupMessage = currentMessage.isGroupMessage && ![newMessage.actorType isEqualToString:@"bots"];
                    messagesForDate[i] = newMessage;
                    messageUpdated = YES;
                    break;
                }
            }
            
            if (!messageUpdated) {
                NCChatMessage *lastMessage = [messagesForDate lastObject];
                newMessage.isGroupMessage = [self shouldGroupMessage:newMessage withMessage:lastMessage];
                [messagesForDate addObject:newMessage];
            }
        } else {
            NSMutableArray *newMessagesInDate = [NSMutableArray new];
            [dictionary setObject:newMessagesInDate forKey:newMessageDate];
            [newMessagesInDate addObject:newMessage];
        }
    }
    
    [self sortDateSections];
}

- (void)insertMessages:(NSMutableArray *)messages
{
    for (NCChatMessage *newMessage in messages) {
        NSDate *newMessageDate = [NSDate dateWithTimeIntervalSince1970: newMessage.timestamp];
        NSDate *keyDate = [self getKeyForDate:newMessageDate inDictionary:_messages];
        NSMutableArray *messagesForDate = [_messages objectForKey:keyDate];
        if (messagesForDate) {
            for (int i = 0; i < messagesForDate.count; i++) {
                NCChatMessage *currentMessage = [messagesForDate objectAtIndex:i];
                if (currentMessage.timestamp > newMessage.timestamp) {
                    // Message inserted in between other messages
                    if (i > 0) {
                        NCChatMessage *previousMessage = [messagesForDate objectAtIndex:i-1];
                        newMessage.isGroupMessage = [self shouldGroupMessage:newMessage withMessage:previousMessage];
                    }
                    currentMessage.isGroupMessage = [self shouldGroupMessage:currentMessage withMessage:newMessage];
                    [messagesForDate insertObject:newMessage atIndex:i];
                    break;
                // Message inserted at the end of a date section
                } else if (i == messagesForDate.count - 1) {
                    newMessage.isGroupMessage = [self shouldGroupMessage:newMessage withMessage:currentMessage];
                    [messagesForDate addObject:newMessage];
                    break;
                }
            }
        } else {
            NSMutableArray *newMessagesInDate = [NSMutableArray new];
            [_messages setObject:newMessagesInDate forKey:newMessageDate];
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
            if ((!currentMessage.isTemporary && currentMessage.messageId == message.messageId) ||
                (currentMessage.isTemporary && [currentMessage.referenceId isEqualToString:message.referenceId])) {
                return [NSIndexPath indexPathForRow:i inSection:section];
            }
        }
    }
    
    return nil;
}

- (NSIndexPath *)indexPathForMessageWithMessageId:(NSInteger)messageId
{
    for (NSInteger i = _dateSections.count - 1; i >= 0; i--) {
        NSDate *keyDate = [_dateSections objectAtIndex:i];
        NSMutableArray *messages = [_messages objectForKey:keyDate];
        NCChatMessage *firstMessage = messages.firstObject;
        if (firstMessage.messageId > messageId) continue;
        for (NSInteger j = messages.count - 1; j >= 0; j--) {
            NCChatMessage *currentMessage = messages[j];
            if (currentMessage.messageId == messageId) {
                return [NSIndexPath indexPathForRow:j inSection:i];
            }
        }
    }
    
    return nil;
}

- (NSIndexPath *)indexPathForMessageWithReferenceId:(NSString *)referenceId
{
    for (NSInteger i = _dateSections.count - 1; i >= 0; i--) {
        NSDate *keyDate = [_dateSections objectAtIndex:i];
        NSMutableArray *messages = [_messages objectForKey:keyDate];
        for (int j = 0; j < messages.count; j++) {
            NCChatMessage *currentMessage = messages[j];
            if ([currentMessage.referenceId isEqualToString:referenceId]) {
                return [NSIndexPath indexPathForRow:j inSection:i];
            }
        }
    }
    
    return nil;
}

- (NSIndexPath *)removeMessageAtIndexPath:(NSIndexPath *)indexPath
{
    NSDate *sectionKey = [_dateSections objectAtIndex:indexPath.section];
    if (sectionKey) {
        NSMutableArray *messages = [_messages objectForKey:sectionKey];
        if (indexPath.row < messages.count) {
            if (messages.count == 1) {
                // Remove section
                [_messages removeObjectForKey:sectionKey];
                [self sortDateSections];
                [self.tableView beginUpdates];
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];
                [self.tableView endUpdates];
            } else {
                // Remove message
                BOOL isLastMessage = indexPath.row == messages.count - 1;
                [messages removeObjectAtIndex:indexPath.row];
                [self.tableView beginUpdates];
                [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self.tableView endUpdates];
                if (!isLastMessage) {
                    // Update the message next to removed message
                    NCChatMessage *nextMessage = [messages objectAtIndex:indexPath.row];
                    nextMessage.isGroupMessage = NO;
                    if (indexPath.row > 0) {
                        NCChatMessage *previousMessage = [messages objectAtIndex:indexPath.row - 1];
                        nextMessage.isGroupMessage = [self shouldGroupMessage:nextMessage withMessage:previousMessage];
                    }
                    [self.tableView beginUpdates];
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                    [self.tableView endUpdates];
                }
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
    
    return sameActor & sameType & timeDiff;
}

- (BOOL)couldRetireveHistory
{
    return _hasReceiveInitialHistory && !_retrievingHistory && _dateSections.count > 0 && _hasStoredHistory;
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
        if ([message.actorId isEqualToString:activeAccount.userId] && !message.isSystemMessage) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)messagesContainVisibleMessages:(NSMutableArray *)messages
{
    for (NCChatMessage *message in messages) {
        if (![message isUpdateMessage]) {
            return YES;
        }
    }
    return NO;
}

- (void)showNewMessagesViewUntilMessage:(NCChatMessage *)message
{
    _firstUnreadMessage = message;
    _unreadMessageButton.hidden = NO;
    // Check if unread messages are already visible
    [self checkUnreadMessagesVisibility];
}

- (void)hideNewMessagesView
{
    _firstUnreadMessage = nil;
    _unreadMessageButton.hidden = YES;
}

- (NSIndexPath *)getIndexPathOfUnreadMessageSeparator
{
    // Most likely the unreadMessageSeparator is somewhere near the bottom of the chat, so we look for it from bottom up
    for (NSInteger sectionIndex = (self->_dateSections.count - 1); sectionIndex >= 0; sectionIndex--) {
        NSDate *dateSection = [self->_dateSections objectAtIndex:sectionIndex];
        NSMutableArray *messagesInSection = [self->_messages objectForKey:dateSection];
        
        for (NSInteger messageIndex = (messagesInSection.count - 1); messageIndex >= 0; messageIndex--) {
            NCChatMessage *chatMessage = [messagesInSection objectAtIndex:messageIndex];
            
            if (chatMessage && chatMessage.messageId == kUnreadMessagesSeparatorIdentifier) {
                return [NSIndexPath indexPathForRow:messageIndex inSection:sectionIndex];
            }
        }
    }
    
    return nil;
}

- (void)removeUnreadMessagesSeparator
{
    NSIndexPath *indexPath = [self getIndexPathOfUnreadMessageSeparator];
    
    if (indexPath) {
        NSDate *separatorDate = [_dateSections objectAtIndex:indexPath.section];
        NSMutableArray *messages = [_messages objectForKey:separatorDate];
        [messages removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationTop];
    }
}

- (void)checkUnreadMessagesVisibility
{
    NSIndexPath *indexPath = [self indexPathForMessage:_firstUnreadMessage];
    NSArray* visibleCellsIPs = [self.tableView indexPathsForVisibleRows];
    if ([visibleCellsIPs containsObject:indexPath]) {
         [self hideNewMessagesView];
    }
}

- (void)checkLastCommonReadMessage
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *reloadCells = [NSMutableArray new];
        for (NSIndexPath *visibleIndexPath in self.tableView.indexPathsForVisibleRows) {
            NSDate *sectionDate = [self->_dateSections objectAtIndex:visibleIndexPath.section];
            NCChatMessage *message = [[self->_messages objectForKey:sectionDate] objectAtIndex:visibleIndexPath.row];
            if (message.messageId > 0 && message.messageId <= self->_room.lastCommonReadMessage) {
                [reloadCells addObject:visibleIndexPath];
            }
        }
        
        if (reloadCells.count > 0) {
            [self.tableView beginUpdates];
            [self.tableView reloadRowsAtIndexPaths:reloadCells withRowAnimation:UITableViewRowAnimationNone];
            [self.tableView endUpdates];
        }
    });
}

- (void)cleanChat
{
    _messages = [[NSMutableDictionary alloc] init];
    _dateSections = [[NSMutableArray alloc] init];
    _hasReceiveInitialHistory = NO;
    _hasRequestedInitialHistory = NO;
    _hasReceiveNewMessages = NO;
    [self hideNewMessagesView];
    [self.tableView reloadData];
}

- (void)savePendingMessage
{
    _room.pendingMessage = self.textView.text;
    [[NCRoomsManager sharedInstance] updatePendingMessage:_room.pendingMessage forRoom:_room];
}

- (void)clearPendingMessage
{
    _room.pendingMessage = @"";
    [[NCRoomsManager sharedInstance] updatePendingMessage:_room.pendingMessage forRoom:_room];
}

- (void)saveLastReadMessage
{
    [[NCRoomsManager sharedInstance] updateLastReadMessage:_lastReadMessage forRoom:_room];
}

#pragma mark - Reactions

- (void)addReaction:(NSString *)reaction toChatMessage:(NCChatMessage *)message
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self setTemporaryReaction:reaction withState:NCChatReactionStateAdding toMessage:message];
    [[NCAPIController sharedInstance] addReaction:reaction toMessage:message.messageId inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSDictionary *reactionsDict, NSError *error, NSInteger statusCode) {
        if (error) {
            [self.view makeToast:NSLocalizedString(@"An error occurred while adding a reaction to message", nil) duration:5 position:CSToastPositionCenter];
            [self removeTemporaryReaction:reaction forMessageId:message.messageId];
        }
    }];
}

- (void)removeReaction:(NSString *)reaction fromChatMessage:(NCChatMessage *)message
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self setTemporaryReaction:reaction withState:NCChatReactionStateRemoving toMessage:message];
    [[NCAPIController sharedInstance] removeReaction:reaction fromMessage:message.messageId inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSDictionary *reactionsDict, NSError *error, NSInteger statusCode) {
        if (error) {
            [self.view makeToast:NSLocalizedString(@"An error occurred while removing a reaction from message", nil) duration:5 position:CSToastPositionCenter];
            [self removeTemporaryReaction:reaction forMessageId:message.messageId];
        }
    }];
}

- (void)addOrRemoveReaction:(NCChatReaction *)reaction inChatMessage:(NCChatMessage *)message
{
    if ([message isReactionBeingModified:reaction.reaction]) {return;}
    
    if (reaction.userReacted) {
        [self removeReaction:reaction.reaction fromChatMessage:message];
    } else {
        [self addReaction:reaction.reaction toChatMessage:message];
    }
}

- (void)removeTemporaryReaction:(NSString *)reaction forMessageId:(NSInteger)messageId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *reloadIndexPaths = [NSMutableArray new];
        NSIndexPath *indexPath = [self indexPathForMessageWithMessageId:messageId];
        if (indexPath) {
            [reloadIndexPaths addObject:indexPath];
            NSDate *keyDate = [self->_dateSections objectAtIndex:indexPath.section];
            NSMutableArray *messages = [self->_messages objectForKey:keyDate];
            NCChatMessage *currentMessage = messages[indexPath.row];
            //Remove temporary reaction
            [currentMessage removeReactionFromTemporayReactions:reaction];
        }
        
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:reloadIndexPaths withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    });
}

- (void)setTemporaryReaction:(NSString *)reaction withState:(NCChatReactionState)state toMessage:(NCChatMessage *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *reloadIndexPaths = [NSMutableArray new];
        NSIndexPath *indexPath = [self indexPathForMessageWithMessageId:message.messageId];
        if (indexPath) {
            [reloadIndexPaths addObject:indexPath];
            NSDate *keyDate = [self->_dateSections objectAtIndex:indexPath.section];
            NSMutableArray *messages = [self->_messages objectForKey:keyDate];
            NCChatMessage *currentMessage = messages[indexPath.row];
            // Add temporary reaction
            if (state == NCChatReactionStateAdding) {
                [currentMessage addTemporaryReaction:reaction];
            }
            // Remove reaction temporarily
            else if (state == NCChatReactionStateRemoving) {
                [currentMessage removeReactionTemporarily:reaction];
            }
        }
        
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:reloadIndexPaths withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    });
}



- (void)showReactionsSummaryOfMessage:(NCChatMessage *)message
{
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);

    ReactionsSummaryView *reactionsVC = [[ReactionsSummaryView alloc] initWithStyle:UITableViewStyleInsetGrouped];
    NCNavigationController *reactionsNC = [[NCNavigationController alloc] initWithRootViewController:reactionsVC];
    [self presentViewController:reactionsNC animated:YES completion:nil];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getReactions:nil fromMessage:message.messageId inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSDictionary *reactionsDict, NSError *error, NSInteger statusCode) {
        if (!error) {
            [reactionsVC updateReactionsWithReactions:reactionsDict];
        }
    }];
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

    NSDate *date = [_dateSections objectAtIndex:section];
    NSMutableArray *messages = [_messages objectForKey:date];

    if (![self messagesContainVisibleMessages:messages]) {
        // No visible message found -> hide section
        return 0.0;
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
    
    DateLabelCustom *headerLabel = (DateLabelCustom*)headerView.dateLabel;
    headerLabel.tableView = self.tableView;
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        if (!_autocompletionUsers || indexPath.row >= [_autocompletionUsers count] || !_autocompletionUsers[indexPath.row]) {
            return [self.autoCompletionView dequeueReusableCellWithIdentifier:AutoCompletionCellIdentifier];
        }

        NSDictionary *suggestion = [_autocompletionUsers objectAtIndex:indexPath.row];
        NSString *suggestionId = [suggestion objectForKey:@"id"];
        NSString *suggestionName = [suggestion objectForKey:@"label"];
        NSString *suggestionSource = [suggestion objectForKey:@"source"];
        NSString *suggestionUserStatus = [suggestion objectForKey:@"status"];
        ChatMessageTableViewCell *suggestionCell = (ChatMessageTableViewCell *)[self.autoCompletionView dequeueReusableCellWithIdentifier:AutoCompletionCellIdentifier];
        suggestionCell.titleLabel.text = suggestionName;
        [suggestionCell setUserStatus:suggestionUserStatus];
        if ([suggestionId isEqualToString:@"all"]) {
            [suggestionCell.avatarView setImage:[UIImage imageNamed:@"group-15"]];
            [suggestionCell.avatarView setContentMode:UIViewContentModeCenter];
        } else if ([suggestionSource isEqualToString:@"guests"]) {
            UIColor *guestAvatarColor = [NCAppBranding placeholderColor];
            NSString *name = ([suggestionName isEqualToString:@"Guest"]) ? @"?" : suggestionName;
            [suggestionCell.avatarView setImageWithString:name color:guestAvatarColor circular:true];
        } else {
            [suggestionCell.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:suggestionId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                             placeholderImage:nil success:nil failure:nil];
        }
        return suggestionCell;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    
    return [self getCellForMessage:message];
}

- (UITableViewCell *)getCellForMessage:(NCChatMessage *) message
{
    UITableViewCell *cell;
    if (message.messageId == kUnreadMessagesSeparatorIdentifier) {
        MessageSeparatorTableViewCell *separatorCell = (MessageSeparatorTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:MessageSeparatorCellIdentifier];
        separatorCell.messageId = message.messageId;
        separatorCell.separatorLabel.text = NSLocalizedString(@"Unread messages", nil);
        return separatorCell;
    }
    if (message.messageId == kChatBlockSeparatorIdentifier) {
        MessageSeparatorTableViewCell *separatorCell = (MessageSeparatorTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:MessageSeparatorCellIdentifier];
        separatorCell.messageId = message.messageId;
        separatorCell.separatorLabel.text = NSLocalizedString(@"Some messages not shown, will be downloaded when online", nil);
        return separatorCell;
    }
    if (message.isSystemMessage) {
        if ([message isUpdateMessage]) {
            return (SystemMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:InvisibleSystemMessageCellIdentifier];
        }
        SystemMessageTableViewCell *systemCell = (SystemMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:SystemMessageCellIdentifier];
        [systemCell setupForMessage:message];
        return systemCell;
    }
    if (message.file) {
        if (message.isVoiceMessage) {
            NSString *voiceMessageCellIdentifier = (message.isGroupMessage) ? GroupedVoiceMessageCellIdentifier : VoiceMessageCellIdentifier;
            VoiceMessageTableViewCell *voiceMessageCell = (VoiceMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:voiceMessageCellIdentifier];
            voiceMessageCell.delegate = self;
            [voiceMessageCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];
            if ([message.file.parameterId isEqualToString:_playerAudioFileStatus.fileId] && [message.file.path isEqualToString:_playerAudioFileStatus.filePath]) {
                [voiceMessageCell setPlayerProgress:_voiceMessagesPlayer.currentTime isPlaying:_voiceMessagesPlayer.isPlaying maximumValue:_voiceMessagesPlayer.duration];
            } else {
                [voiceMessageCell resetPlayer];
            }
            return voiceMessageCell;
        }
        NSString *fileCellIdentifier = (message.isGroupMessage) ? GroupedFileMessageCellIdentifier : FileMessageCellIdentifier;
        FileMessageTableViewCell *fileCell = (FileMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:fileCellIdentifier];
        fileCell.delegate = self;
        
        [fileCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];

        return fileCell;
    }
    if (message.geoLocation) {
        NSString *locationCellIdentifier = (message.isGroupMessage) ? GroupedLocationMessageCellIdentifier : LocationMessageCellIdentifier;
        LocationMessageTableViewCell *locationCell = (LocationMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:locationCellIdentifier];
        locationCell.delegate = self;
        
        [locationCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];

        return locationCell;
    }
    if (message.poll) {
        NSString *pollCellIdentifier = (message.isGroupMessage) ? GroupedObjectShareMessageCellIdentifier : ObjectShareMessageCellIdentifier;
        ObjectShareMessageTableViewCell *pollCell = (ObjectShareMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:pollCellIdentifier];
        pollCell.delegate = self;
        
        [pollCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];

        return pollCell;
    }
    if (message.parent) {
        ChatMessageTableViewCell *replyCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ReplyMessageCellIdentifier];
        replyCell.delegate = self;
        
        [replyCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];
        
        return replyCell;
    }
    if (message.isGroupMessage) {
        GroupedChatMessageTableViewCell *groupedCell = (GroupedChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:GroupedChatMessageCellIdentifier];
        groupedCell.delegate = self;

        [groupedCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];
        
        return groupedCell;
    } else {
        ChatMessageTableViewCell *normalCell = (ChatMessageTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:ChatMessageCellIdentifier];
        normalCell.delegate = self;

        [normalCell setupForMessage:message withLastCommonReadMessage:_room.lastCommonReadMessage];
        
        return normalCell;
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.tableView]) {
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        
        CGFloat width = CGRectGetWidth(tableView.frame) - kChatCellAvatarHeight;
        width -= tableView.safeAreaInsets.left + tableView.safeAreaInsets.right;
        
        return [self getCellHeightForMessage:message withWidth:width];
    }
    else {
        return kChatMessageCellMinimumHeight;
    }
}

- (CGFloat)getCellHeightForMessage:(NCChatMessage *)message withWidth:(CGFloat)width
{
    // Chat separators
    if (message.messageId == kUnreadMessagesSeparatorIdentifier ||
        message.messageId == kChatBlockSeparatorIdentifier) {
        return kMessageSeparatorCellHeight;
    }
    
    // Update messages (the ones that notify about an update in one message, they should not be displayed)
    if (message.message.length == 0 || [message isUpdateMessage]) {
        return 0.0;
    }
    
    // Chat messages
    NSMutableAttributedString *messageString = message.parsedMessage;
    width -= (message.isSystemMessage)? 80.0 : 30.0; // 4*right(10) + dateLabel(40) : 3*right(10)
    if (message.poll) {
        messageString = [[NSMutableAttributedString alloc] initWithString:message.poll.name];
        [messageString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:[ObjectShareMessageTableViewCell defaultFontSize]] range:NSMakeRange(0,messageString.length)];
        width -= kObjectShareMessageCellObjectTypeImageSize + 25; // 2*right(10) + left(5)
    }
    CGRect bodyBounds = [messageString boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading) context:NULL];
    
    CGFloat height = kChatCellAvatarHeight;
    height += ceil(CGRectGetHeight(bodyBounds));
    height += 20.0; // right(10) + 2*left(5)
    
    if (height < kChatMessageCellMinimumHeight) {
        height = kChatMessageCellMinimumHeight;
    }
    
    if (message.reactionsArray.count > 0) {
        height += 40; // reactionsView(40)
    }

    if (message.containsURL) {
        height += 105;
    }
    
    if (message.parent) {
        height += 55; // left(5) + quoteView(50)
        return height;
    }
    
    if (message.isGroupMessage || message.isSystemMessage) {
        height = ceil(CGRectGetHeight(bodyBounds)) + 10; // 2*left(5)
        
        if (height < kGroupedChatMessageCellMinimumHeight) {
            height = kGroupedChatMessageCellMinimumHeight;
        }
        
        if (message.reactionsArray.count > 0) {
            height += 40; // reactionsView(40)
        }

        if (message.containsURL) {
            height += 105;
        }
    }
    
    // Voice message should be before message.file check since it contains a file
    if (message.isVoiceMessage) {
        height -= ceil(CGRectGetHeight(bodyBounds));
        return height += kVoiceMessageCellPlayerHeight + 10; // right(10)
    }
    
    if (message.file) {
        return height += message.file.previewImageHeight == 0 ? kFileMessageCellFilePreviewHeight + 10 : message.file.previewImageHeight + 10; // right(10)
    }
    
    if (message.geoLocation) {
        return height += kLocationMessageCellPreviewHeight + 10; // right(10)
    }
    
    if (message.poll) {
        return height += 20; // 2*right(10)
    }
    
    return height;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:self.autoCompletionView]) {
        if (!_autocompletionUsers || indexPath.row >= [_autocompletionUsers count] || !_autocompletionUsers[indexPath.row]) {
            return;
        }

        NCMessageParameter *mention = [[NCMessageParameter alloc] init];
        mention.parameterId = [self.autocompletionUsers[indexPath.row] objectForKey:@"id"];
        mention.name = [self.autocompletionUsers[indexPath.row] objectForKey:@"label"];
        mention.mentionDisplayName = [NSString stringWithFormat:@"@%@", mention.name];
        mention.mentionId = [NSString stringWithFormat:@"@%@", [self.autocompletionUsers[indexPath.row] objectForKey:@"id"]];
        // Guest mentions are wrapped with double quotes @"guest/<sha1(webrtc session id)>"
        if ([[self.autocompletionUsers[indexPath.row] objectForKey:@"source"] isEqualToString:@"guests"]) {
            mention.mentionId = [NSString stringWithFormat:@"@\"%@\"", mention.parameterId];
        }
        // User-ids with a space should be wrapped in double quoutes
        NSRange whiteSpaceRange = [mention.parameterId rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (whiteSpaceRange.location != NSNotFound) {
            mention.mentionId = [NSString stringWithFormat:@"@\"%@\"", mention.parameterId];
        }
        // Set parameter type
        if ([[self.autocompletionUsers[indexPath.row] objectForKey:@"source"] isEqualToString:@"calls"]) {
            mention.type = @"call";
        } else if ([[self.autocompletionUsers[indexPath.row] objectForKey:@"source"] isEqualToString:@"users"]) {
            mention.type = @"user";
        }
        
        NSString *mentionKey = [NSString stringWithFormat:@"mention-%ld", _mentionsDict.allKeys.count];
        [_mentionsDict setObject:mention forKey:mentionKey];
        
        NSString *mentionWithWhiteSpace = [NSString stringWithFormat:@"%@ ", mention.name];
        [self acceptAutoCompletionWithString:mentionWithWhiteSpace keepPrefix:YES];
    } else {
        [self.emojiTextField resignFirstResponder];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

#pragma mark - iOS >=13 message long press menu

- (BOOL)isMessageReplyable:(NCChatMessage *)message
{
    return message.isReplyable && !message.isDeleting && !_offlineMode;
}

- (BOOL)isMessageReactable:(NCChatMessage *)message
{
    BOOL isReactable = [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityReactions];
    isReactable &= !_offlineMode;
    isReactable &= _room.readOnlyState != NCRoomReadOnlyStateReadOnly;
    isReactable &= !message.isDeletedMessage && !message.isCommandMessage && !message.sendingFailed && !message.isTemporary;
    
    return isReactable;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point
{
    if ([tableView isEqual:self.autoCompletionView]) {
        return nil;
    }
    
    // Do not show context menu if long pressing in reactions view
    ChatTableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    CGPoint pointInCell = [tableView convertPoint:point toView:cell];
    for (UIView *subview in cell.contentView.subviews) {
        if ([subview isKindOfClass:ReactionsView.class] && CGRectContainsPoint(subview.frame, pointInCell)) {
            [self showReactionsSummaryOfMessage:cell.message];
            return nil;
        }
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    
    if (message.isSystemMessage || message.messageId == kUnreadMessagesSeparatorIdentifier) {
        return nil;
    }
        
    NSMutableArray *actions = [[NSMutableArray alloc] init];

    BOOL hasChatPermission = ![[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatPermission] || (_room.permissions & NCPermissionChat) != 0;

    // Reply option
    if ([self isMessageReplyable:message] && hasChatPermission) {
        UIImage *replyImage = [[UIImage imageNamed:@"reply"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *replyAction = [UIAction actionWithTitle:NSLocalizedString(@"Reply", nil) image:replyImage identifier:nil handler:^(UIAction *action){
            
            [self didPressReply:message];
        }];
        
        [actions addObject:replyAction];
    }
    
    // Add reaction option
    if ([self isMessageReactable:message] && hasChatPermission) {
        UIImage *reactionImage = [[UIImage imageNamed:@"emoji"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *reactionAction = [UIAction actionWithTitle:NSLocalizedString(@"Add reaction", nil) image:reactionImage identifier:nil handler:^(UIAction *action){
            
            [self didPressAddReaction:message atIndexPath:indexPath];
        }];
        
        [actions addObject:reactionAction];
    }
    
    // Reply-privately option (only to other users and not in one-to-one)
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([self isMessageReplyable:message] && _room.type != kNCRoomTypeOneToOne && [message.actorType isEqualToString:@"users"] && ![message.actorId isEqualToString:activeAccount.userId] )
    {
        UIImage *replyPrivateImage = [[UIImage imageNamed:@"user"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *replyPrivateAction = [UIAction actionWithTitle:NSLocalizedString(@"Reply privately", nil) image:replyPrivateImage identifier:nil handler:^(UIAction *action){
            
            [self didPressReplyPrivately:message];
        }];
        
        [actions addObject:replyPrivateAction];
    }
    
    // Forward option (only normal messages for now)
    if (!message.file && !message.poll && !message.isDeletedMessage && !_offlineMode) {
        UIImage *forwardImage = [[UIImage imageNamed:@"forward"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *forwardAction = [UIAction actionWithTitle:NSLocalizedString(@"Forward", nil) image:forwardImage identifier:nil handler:^(UIAction *action){
            
            [self didPressForward:message];
        }];
        
        [actions addObject:forwardAction];
    }

    // Re-send option
    if (message.sendingFailed && !_offlineMode && hasChatPermission) {
        UIImage *resendImage = [[UIImage imageNamed:@"refresh"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *resendAction = [UIAction actionWithTitle:NSLocalizedString(@"Resend", nil) image:resendImage identifier:nil handler:^(UIAction *action){
            
            [self didPressResend:message];
        }];
        
        [actions addObject:resendAction];
    }
    
    // Copy option
    UIImage *copyImage = [[UIImage imageNamed:@"copy"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIAction *copyAction = [UIAction actionWithTitle:NSLocalizedString(@"Copy", nil) image:copyImage identifier:nil handler:^(UIAction *action){
        
        [self didPressCopy:message];
    }];
    
    [actions addObject:copyAction];
    
    // Open in nextcloud option
    if (message.file && !_offlineMode) {
        NSString *openInNextcloudTitle = [NSString stringWithFormat:NSLocalizedString(@"Open in %@", nil), filesAppName];
        UIImage *nextcloudActionImage = [[UIImage imageNamed:@"logo-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *openInNextcloudAction = [UIAction actionWithTitle:openInNextcloudTitle image:nextcloudActionImage identifier:nil handler:^(UIAction *action){
            
            [self didPressOpenInNextcloud:message];
        }];

        [actions addObject:openInNextcloudAction];
    }
    
    // Transcribe voice-message
    if ([message.messageType isEqualToString:kMessageTypeVoiceMessage]) {
        UIImage *transcribeActionImage = [[UIImage imageNamed:@"transcribe-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *transcribeAction = [UIAction actionWithTitle:NSLocalizedString(@"Transcribe", @"TRANSLATORS this is for transcribing a voice message to text") image:transcribeActionImage identifier:nil handler:^(UIAction *action){
            
            [self didPressTranscribeVoiceMessage:message];
        }];

        [actions addObject:transcribeAction];
    }
    

    // Delete option
    if (message.sendingFailed || ([message isDeletableForAccount:[[NCDatabaseManager sharedInstance] activeAccount] andParticipantType:_room.participantType] && hasChatPermission)) {
        UIImage *deleteImage = [[UIImage imageNamed:@"delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *deleteAction = [UIAction actionWithTitle:NSLocalizedString(@"Delete", nil) image:deleteImage identifier:nil handler:^(UIAction *action){
            
            [self didPressDelete:message];
        }];
    
        deleteAction.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:deleteAction];
    }
    
    UIMenu *menu = [UIMenu menuWithTitle:@"" children:actions];
    
    UIContextMenuConfiguration *configuration = [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:^UIViewController * _Nullable{
        return [self getPreviewViewControllerForTableView:tableView withIndexPath:indexPath];
    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return menu;
    }];

    return configuration;
}

- (UIViewController *)getPreviewViewControllerForTableView:(UITableView *)tableView withIndexPath:(NSIndexPath *)indexPath
{
    if (SLK_IS_IPAD) {
        return nil;
    }
    
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    
    // Remember grouped-status -> Create a previewView which always is a non-grouped-message
    BOOL isGroupMessage = message.isGroupMessage;
    message.isGroupMessage = NO;
    
    CGFloat maxPreviewWidth = self.view.bounds.size.width;
    CGFloat maxPreviewHeight = self.view.bounds.size.height * 0.6;
    
    if (SLK_IS_IPHONE && SLK_IS_LANDSCAPE) {
        maxPreviewWidth = self.view.bounds.size.width / 3;
    }
    
    UITableViewCell *previewView = [self getCellForMessage:message];
    CGFloat maxTextWidth = maxPreviewWidth - kChatCellAvatarHeight;
    CGFloat cellHeight = [self getCellHeightForMessage:message withWidth:maxTextWidth];
    
    // Cut the height if bigger than max height
    if (cellHeight > maxPreviewHeight) {
        cellHeight = maxPreviewHeight;
    }
    
    // Make sure the previewView has the correct size
    previewView.contentView.frame = CGRectMake(0,0, maxPreviewWidth, cellHeight);
    
    // Restore grouped-status
    message.isGroupMessage = isGroupMessage;
    
    UIViewController *previewController = [[UIViewController alloc] init];
    [previewController.view addSubview:previewView.contentView];
    previewController.preferredContentSize = previewView.contentView.frame.size;
    
    return previewController;
}

//Swipe to reply option
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
    NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
    if (message.isReplyable && !message.isDeleting && !_offlineMode) {
        UIContextualAction *replyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self didPressReply:message];
            completionHandler(true);
        }];
        replyAction.image = [UIImage imageNamed:@"reply-settings"];
        replyAction.backgroundColor = self.tableView.backgroundColor;
        return [UISwipeActionsConfiguration configurationWithActions:@[replyAction]];
    } else {
        return nil;
    }
}

#pragma mark - FileMessageTableViewCellDelegate

- (void)cellWantsToDownloadFile:(NCMessageFileParameter *)fileParameter
{
    if (fileParameter.fileStatus && fileParameter.fileStatus.isDownloading) {
        NSLog(@"File already downloading -> skipping new download");
        return;
    }
    
    NCChatFileController *downloader = [[NCChatFileController alloc] init];
    downloader.delegate = self;
    [downloader downloadFileFromMessage:fileParameter];
}

- (void)cellHasDownloadedImagePreviewWithHeight:(CGFloat)height forMessage:(NCChatMessage *)message
{
    message.file.previewImageHeight = height;
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}
#pragma mark - VoiceMessageTableViewCellDelegate

- (void)cellWantsToPlayAudioFile:(NCMessageFileParameter *)fileParameter
{
    if (fileParameter.fileStatus && fileParameter.fileStatus.isDownloading) {
        NSLog(@"File already downloading -> skipping new download");
        return;
    }
    
    if (!_voiceMessagesPlayer.isPlaying && [fileParameter.parameterId isEqualToString:_playerAudioFileStatus.fileId] && [fileParameter.path isEqualToString:_playerAudioFileStatus.filePath]) {
        [self playVoiceMessagePlayer];
        return;
    }
    
    NCChatFileController *downloader = [[NCChatFileController alloc] init];
    downloader.delegate = self;
    downloader.messageType = kMessageTypeVoiceMessage;
    [downloader downloadFileFromMessage:fileParameter];
}

- (void)cellWantsToPauseAudioFile:(NCMessageFileParameter *)fileParameter
{
    if (_voiceMessagesPlayer.isPlaying && [fileParameter.parameterId isEqualToString:_playerAudioFileStatus.fileId] && [fileParameter.path isEqualToString:_playerAudioFileStatus.filePath]) {
        [self pauseVoiceMessagePlayer];
    }
}

- (void)cellWantsToChangeProgress:(CGFloat)progress fromAudioFile:(NCMessageFileParameter *)fileParameter
{
    if ([fileParameter.parameterId isEqualToString:_playerAudioFileStatus.fileId] && [fileParameter.path isEqualToString:_playerAudioFileStatus.filePath]) {
        [self pauseVoiceMessagePlayer];
        [_voiceMessagesPlayer setCurrentTime:progress];
        [self checkVisibleCellAudioPlayers];
    }
}

#pragma mark - LocationMessageTableViewCellDelegate

- (void)cellWantsToOpenLocation:(GeoLocationRichObject *)geoLocationRichObject
{
    MapViewController *mapVC = [[MapViewController alloc] initWithGeoLocationRichObject:geoLocationRichObject];
    NCNavigationController *mapNC = [[NCNavigationController alloc] initWithRootViewController:mapVC];
    [self presentViewController:mapNC animated:YES completion:nil];
}

#pragma mark - ObjectShareMessageTableViewCellDelegate

- (void)cellWantsToOpenPoll:(NCMessageParameter *)poll
{
    PollVotingView *pollVC = [[PollVotingView alloc] initWithStyle:UITableViewStyleInsetGrouped];
    pollVC.room = _room;
    NCNavigationController *pollNC = [[NCNavigationController alloc] initWithRootViewController:pollVC];
    [self presentViewController:pollNC animated:YES completion:nil];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getPollWithId:poll.parameterId.integerValue inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NCPoll *poll, NSError *error, NSInteger statusCode) {
        if (!error) {
            [pollVC updatePollWithPoll:poll];
        }
    }];
}

#pragma mark - PollCreationViewControllerDelegate

- (void)wantsToCreatePollWithQuestion:(NSString *)question options:(NSArray<NSString *> *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] createPollWithQuestion:question options:options resultMode:resultMode maxVotes:maxVotes inRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NCPoll *poll, NSError *error, NSInteger statusCode) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
}

#pragma mark - ChatMessageTableViewCellDelegate

- (void)cellWantsToScrollToMessage:(NCChatMessage *)message {
    NSIndexPath *indexPath = [self indexPathForMessage:message];
    if (indexPath) {
        [self highlightMessageAtIndexPath:indexPath withScrollPosition:UITableViewScrollPositionTop];
    }
}

- (void)cellWantsToDisplayOptionsForMessageActor:(NCChatMessage *)message {
    NSIndexPath *indexPath = [self indexPathForMessage:message];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (indexPath && [message.actorType isEqualToString:@"users"] && ![message.actorId isEqualToString:activeAccount.userId]) {
        [self presentOptionsForMessageActor:message fromIndexPath:indexPath];
    }
}

- (void)cellDidSelectedReaction:(NCChatReaction *)reaction forMessage:(NCChatMessage *)message
{
    [self addOrRemoveReaction:reaction inChatMessage:message];
}

#pragma mark - NCChatFileControllerDelegate

- (void)fileControllerDidLoadFile:(NCChatFileController *)fileController withFileStatus:(NCChatFileStatus *)fileStatus
{
    if ([fileController.messageType isEqualToString:kMessageTypeVoiceMessage]) {
        if ([fileController.actionType isEqualToString:kActionTypeTranscribeVoiceMessage]) {
            [self transcribeVoiceMessageWithAudioFileStatus:fileStatus];
        } else {
            [self setupVoiceMessagePlayerWithAudioFileStatus:fileStatus];
        }
        
        return;
    }
    
    if (_isPreviewControllerShown) {
        // We are showing a file already, no need to open another one
        return;
    }
    
    BOOL isFileCellStillVisible = NO;
    
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        NSDate *sectionDate = [_dateSections objectAtIndex:indexPath.section];
        NCChatMessage *message = [[_messages objectForKey:sectionDate] objectAtIndex:indexPath.row];
        
        if (message.file && [message.file.parameterId isEqualToString:fileStatus.fileId] && [message.file.path isEqualToString:fileStatus.filePath]) {
            isFileCellStillVisible = YES;
            break;
        }
    }
    
    if (!isFileCellStillVisible) {
        // Only open file when the corresponding cell is still visible on the screen
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_isPreviewControllerShown = YES;
        self->_previewControllerFilePath = fileStatus.fileLocalPath;
        
        // When the keyboard is not dismissed, dismissing the previewController might result in a corrupted keyboardView
        [self dismissKeyboard:NO];

        QLPreviewController * preview = [[QLPreviewController alloc] init];
        UIColor *themeColor = [NCAppBranding themeColor];
        
        preview.dataSource = self;
        preview.delegate = self;

        preview.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
        preview.navigationController.navigationBar.barTintColor = themeColor;
        preview.tabBarController.tabBar.tintColor = themeColor;

        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        preview.navigationItem.standardAppearance = appearance;
        preview.navigationItem.compactAppearance = appearance;
        preview.navigationItem.scrollEdgeAppearance = appearance;

        [self presentViewController:preview animated:YES completion:nil];
    });
}

- (void)fileControllerDidFailLoadingFile:(NCChatFileController *)fileController withErrorDescription:(NSString *)errorDescription
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Unable to load file", nil)
                                 message:errorDescription
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

#pragma mark - QLPreviewControllerDelegate/DataSource

- (NSInteger)numberOfPreviewItemsInPreviewController:(nonnull QLPreviewController *)controller {
    return 1;
}

- (nonnull id<QLPreviewItem>)previewController:(nonnull QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return [NSURL fileURLWithPath:_previewControllerFilePath];
}

- (void)previewControllerDidDismiss:(QLPreviewController *)controller
{
    _isPreviewControllerShown = NO;
}

@end
