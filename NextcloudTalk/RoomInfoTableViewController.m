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

#import "RoomInfoTableViewController.h"

@import NextcloudKit;

#import <QuickLook/QuickLook.h>

#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "UIView+Toast.h"

#import "NextcloudTalk-Swift.h"

#import "AddParticipantsTableViewController.h"
#import "CallConstants.h"
#import "ContactsTableViewCell.h"
#import "HeaderWithButton.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatFileController.h"
#import "NCDatabaseManager.h"
#import "NCNavigationController.h"
#import "NCRoomsManager.h"
#import "NCRoomParticipant.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "RoomDescriptionTableViewCell.h"
#import "RoomNameTableViewCell.h"
#import "NCUserStatus.h"

typedef enum RoomInfoSection {
    kRoomInfoSectionName = 0,
    kRoomInfoSectionDescription,
    kRoomInfoSectionFile,
    kRoomInfoSectionSharedItems,
    kRoomInfoSectionNotifications,
    kRoomInfoSectionGuests,
    kRoomInfoSectionConversation,
    kRoomInfoSectionWebinar,
    kRoomInfoSectionSIP,
    kRoomInfoSectionParticipants,
    kRoomInfoSectionDestructive
} RoomInfoSection;

typedef enum NotificationAction {
    kNotificationActionChatNotifications = 0,
    kNotificationActionCallNotifications
} NotificationAction;

typedef enum GuestAction {
    kGuestActionPublicToggle = 0,
    kGuestActionPassword,
    kGuestActionResendInvitations
} GuestAction;

typedef enum ConversationAction {
    kConversationActionMessageExpiration = 0,
    kConversationActionListable,
    kConversationActionListableForEveryone,
    kConversationActionReadOnly,
    kConversationActionShareLink
} ConversationAction;

typedef enum WebinarAction {
    kWebinarActionLobby = 0,
    kWebinarActionLobbyTimer,
    kWebinarActionSIP,
    kWebinarActionSIPNoPIN
} WebinarAction;

typedef enum SIPAction {
    kSIPActionSIPInfo = 0,
    kSIPActionMeetingId,
    kSIPActionPIN,
    kSIPActionNumber
} SIPAction;

typedef enum DestructiveAction {
    kDestructiveActionLeave = 0,
    kDestructiveActionClearHistory,
    kDestructiveActionDelete
} DestructiveAction;

typedef enum ModificationError {
    kModificationErrorRename = 0,
    kModificationErrorChatNotifications,
    kModificationErrorCallNotifications,
    kModificationErrorShare,
    kModificationErrorPassword,
    kModificationErrorResendInvitations,
    kModificationErrorSendCallNotification,
    kModificationErrorLobby,
    kModificationErrorSIP,
    kModificationErrorModeration,
    kModificationErrorRemove,
    kModificationErrorLeave,
    kModificationErrorLeaveModeration,
    kModificationErrorDelete,
    kModificationErrorClearHistory,
    kModificationErrorListable,
    kModificationErrorReadOnly,
    kModificationErrorMessageExpiration
} ModificationError;

typedef enum FileAction {
    kFileActionPreview = 0,
    kFileActionOpenInFilesApp
} FileAction;

#define k_set_password_textfield_tag    98

@interface RoomInfoTableViewController () <UITextFieldDelegate, UIGestureRecognizerDelegate, AddParticipantsTableViewControllerDelegate, NCChatFileControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NCChatViewController *chatViewController;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UISwitch *publicSwitch;
@property (nonatomic, strong) UISwitch *listableSwitch;
@property (nonatomic, strong) UISwitch *listableForEveryoneSwitch;
@property (nonatomic, strong) UISwitch *readOnlySwitch;
@property (nonatomic, strong) UISwitch *lobbySwitch;
@property (nonatomic, strong) UISwitch *sipSwitch;
@property (nonatomic, strong) UISwitch *sipNoPINSwitch;
@property (nonatomic, strong) UISwitch *callNotificationSwitch;
@property (nonatomic, strong) UIDatePicker *lobbyDatePicker;
@property (nonatomic, strong) UITextField *lobbyDateTextField;
@property (nonatomic, strong) UIActivityIndicatorView *modifyingRoomView;
@property (nonatomic, strong) HeaderWithButton *headerView;
@property (nonatomic, strong) UIAlertAction *setPasswordAction;
@property (nonatomic, strong) UIActivityIndicatorView *fileDownloadIndicator;
@property (nonatomic, strong) NSString *previewControllerFilePath;

@end

@implementation RoomInfoTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    return [self initForRoom:room fromChatViewController:nil];
}

- (instancetype)initForRoom:(NCRoom *)room fromChatViewController:(NCChatViewController *)chatViewController
{
    self = [super init];
    if (self) {
        _room = room;
        _chatViewController = chatViewController;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Conversation info", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    
    _roomParticipants = [[NSMutableArray alloc] init];
    
    _publicSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_publicSwitch addTarget: self action: @selector(publicValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _listableSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_listableSwitch addTarget: self action: @selector(listableValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _listableForEveryoneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_listableForEveryoneSwitch addTarget: self action: @selector(listableForEveryoneValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _readOnlySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_readOnlySwitch addTarget: self action: @selector(readOnlyValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _lobbySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_lobbySwitch addTarget: self action: @selector(lobbyValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _sipSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_sipSwitch addTarget: self action: @selector(sipValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _sipNoPINSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_sipNoPINSwitch addTarget: self action: @selector(sipNoPINValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _callNotificationSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_callNotificationSwitch addTarget: self action: @selector(callNotificationValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _lobbyDatePicker = [[UIDatePicker alloc] init];
    _lobbyDatePicker.datePickerMode = UIDatePickerModeDateAndTime;
    _lobbyDatePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    
    _lobbyDateTextField = [[UITextField alloc] initWithFrame:CGRectMake(0, 00, 150, 30)];
    _lobbyDateTextField.textAlignment = NSTextAlignmentRight;
    _lobbyDateTextField.placeholder = NSLocalizedString(@"Manual", @"TRANSLATORS this is used when no meeting start time is set and the meeting will be started manually");
    _lobbyDateTextField.adjustsFontSizeToFitWidth = YES;
    _lobbyDateTextField.minimumFontSize = 9;
    [_lobbyDateTextField setInputView:_lobbyDatePicker];
    [self setupLobbyDatePicker];
    
    _modifyingRoomView = [[UIActivityIndicatorView alloc] init];
    _modifyingRoomView.color = [NCAppBranding themeTextColor];
    
    _headerView = [[HeaderWithButton alloc] init];
    [_headerView.button setTitle:NSLocalizedString(@"Add", nil) forState:UIControlStateNormal];
    [_headerView.button addTarget:self action:@selector(addParticipantsButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomDescriptionTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomDescriptionCellIdentifier];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    
    if (!_chatViewController || [self.navigationController.viewControllers count] == 1) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[NCRoomsManager sharedInstance] updateRoom:_room.token withCompletionBlock:nil];
    [self getRoomParticipants];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dismissKeyboard
{
    [_roomNameTextField resignFirstResponder];
}

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Utils

- (void)getRoomParticipants
{
    [[NCAPIController sharedInstance] getParticipantsFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSMutableArray *participants, NSError *error) {
        self->_roomParticipants = participants;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange([self getSectionForRoomInfoSection:kRoomInfoSectionParticipants], 1)] withRowAnimation:UITableViewRowAnimationNone];
        [self removeModifyingRoomUI];
    }];
}

- (NSArray *)getRoomInfoSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    // Room name section
    [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionName]];
    // Room description section
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRoomDescription] && _room.roomDescription && ![_room.roomDescription isEqualToString:@""]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionDescription]];
    }
    // File actions section
    if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionFile]];
    }
    // Shared items section
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRichObjectListMedia]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionSharedItems]];
    }
    // Notifications section
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionNotifications]];
    }
    // Conversation section
    if ([self getConversationActions].count > 0) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionConversation]];
    }
    // Moderator sections
    if (_room.canModerate) {
        // Guests section
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionGuests]];
        // Webinar section
        if (_room.type != kNCRoomTypeOneToOne && _room.type != kNCRoomTypeFormerOneToOne && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityWebinaryLobby]) {
            [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionWebinar]];
        }
    }
    // SIP section
    if (_room.sipState > NCRoomSIPStateDisabled) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionSIP]];
    }
    // Participants section
    [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionParticipants]];
    // Destructive actions section
    if (!_chatViewController || !_chatViewController.presentedInCall) {
        // Do not show destructive actions when chat is presented during a call
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionDestructive]];
    }
    return [NSArray arrayWithArray:sections];
}

- (NSInteger)getSectionForRoomInfoSection:(RoomInfoSection)section
{
    NSInteger sectionNumber = [[self getRoomInfoSections] indexOfObject:[NSNumber numberWithInt:section]];
    if(NSNotFound != sectionNumber) {
        return sectionNumber;
    }
    return 0;
}

- (NSArray *)getNotificationsActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Chat notifications levels action
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels]) {
        [actions addObject:[NSNumber numberWithInt:kNotificationActionChatNotifications]];
    }
    // Call notifications action
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationCalls] && [[NCSettingsController sharedInstance] callsEnabledCapability]) {
        [actions addObject:[NSNumber numberWithInt:kNotificationActionCallNotifications]];
    }
    
    return [NSArray arrayWithArray:actions];
}

- (NSIndexPath *)getIndexPathForNotificationAction:(NotificationAction)action
{
    NSInteger section = [self getSectionForRoomInfoSection:kRoomInfoSectionNotifications];
    NSIndexPath *actionIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
    NSInteger actionRow = [[self getNotificationsActions] indexOfObject:[NSNumber numberWithInt:action]];
    if(NSNotFound != actionRow) {
        actionIndexPath = [NSIndexPath indexPathForRow:actionRow inSection:section];
    }
    return actionIndexPath;
}

- (NSArray *)getFileActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // File preview
    [actions addObject:[NSNumber numberWithInt:kFileActionPreview]];
    // Open file in nextcloud app
    [actions addObject:[NSNumber numberWithInt:kFileActionOpenInFilesApp]];
    
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getGuestsActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Public room toggle
    [actions addObject:[NSNumber numberWithInt:kGuestActionPublicToggle]];

    // Password protection
    if (_room.isPublic) {
        [actions addObject:[NSNumber numberWithInt:kGuestActionPassword]];
    }
    // Resend invitations
    if (_room.isPublic && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySIPSupport]) {
        [actions addObject:[NSNumber numberWithInt:kGuestActionResendInvitations]];
    }
    return [NSArray arrayWithArray:actions];
}

- (NSIndexPath *)getIndexPathForGuestAction:(GuestAction)action
{
    NSInteger section = [self getSectionForRoomInfoSection:kRoomInfoSectionGuests];
    NSIndexPath *actionIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
    NSInteger actionRow = [[self getGuestsActions] indexOfObject:[NSNumber numberWithInt:action]];
    if(NSNotFound != actionRow) {
        actionIndexPath = [NSIndexPath indexPathForRow:actionRow inSection:section];
    }
    return actionIndexPath;
}

- (NSArray *)getConversationActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];

    // Message expiration action
    if (_room.isUserOwnerOrModerator && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityMessageExpiration]) {
        [actions addObject:[NSNumber numberWithInt:kConversationActionMessageExpiration]];
    }

    if (_room.canModerate) {
        // Listable room action
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityListableRooms]) {
            [actions addObject:[NSNumber numberWithInt:kConversationActionListable]];
            
            if (_room.listable != NCRoomListableScopeParticipantsOnly && [[NCSettingsController sharedInstance] isGuestsAppEnabled]) {
                [actions addObject:[NSNumber numberWithInt:kConversationActionListableForEveryone]];
            }
        }

        // Read only room action
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityReadOnlyRooms]) {
            [actions addObject:[NSNumber numberWithInt:kConversationActionReadOnly]];
        }
    }

    if (_room.type != kNCRoomTypeChangelog) {
        [actions addObject:[NSNumber numberWithInt:kConversationActionShareLink]];
    }
    
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getWebinarActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Lobby toggle
    [actions addObject:[NSNumber numberWithInt:kWebinarActionLobby]];
    // Lobby timer
    if (_room.lobbyState == NCRoomLobbyStateModeratorsOnly) {
        [actions addObject:[NSNumber numberWithInt:kWebinarActionLobbyTimer]];
    }
    // SIP toggle
    if (_room.canEnableSIP) {
        [actions addObject:[NSNumber numberWithInt:kWebinarActionSIP]];
        if (_room.sipState > NCRoomSIPStateDisabled && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySIPSupportNoPIN]) {
            [actions addObject:[NSNumber numberWithInt:kWebinarActionSIPNoPIN]];
        }
    }
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getRoomDestructiveActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Leave room
    if (_room.isLeavable) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionLeave]];
    }
    // Clear history
    if (_room.canModerate && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityClearHistory]) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionClearHistory]];
    }
    // Delete room
    if (_room.canModerate) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionDelete]];
    }
    return [NSArray arrayWithArray:actions];
}

- (NSIndexPath *)getIndexPathForDestructiveAction:(DestructiveAction)action
{
    NSInteger section = [self getSectionForRoomInfoSection:kRoomInfoSectionDestructive];
    NSIndexPath *actionIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
    NSInteger actionRow = [[self getRoomDestructiveActions] indexOfObject:[NSNumber numberWithInt:action]];
    if(NSNotFound != actionRow) {
        actionIndexPath = [NSIndexPath indexPathForRow:actionRow inSection:section];
    }
    return actionIndexPath;
}

- (BOOL)isAppUser:(NCRoomParticipant *)participant
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([participant.participantId isEqualToString:activeAccount.userId]) {
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
    [self showRoomModificationError:error withMessage:nil];
}

- (void)showRoomModificationError:(ModificationError)error withMessage:(NSString *)errorMessage
{
    [self removeModifyingRoomUI];
    NSString *errorDescription = @"";
    switch (error) {
        case kModificationErrorRename:
            errorDescription = NSLocalizedString(@"Could not rename the conversation", nil);
            break;
            
        case kModificationErrorChatNotifications:
            errorDescription = NSLocalizedString(@"Could not change notifications setting", nil);
            break;
            
        case kModificationErrorCallNotifications:
            errorDescription = NSLocalizedString(@"Could not change call notifications setting", nil);
            break;
            
        case kModificationErrorShare:
            errorDescription = NSLocalizedString(@"Could not change sharing permissions of the conversation", nil);
            break;
            
        case kModificationErrorPassword:
            errorDescription = NSLocalizedString(@"Could not change password protection settings", nil);
            break;
            
        case kModificationErrorResendInvitations:
            errorDescription = NSLocalizedString(@"Could not resend email invitations", nil);
            break;
            
        case kModificationErrorSendCallNotification:
            errorDescription = NSLocalizedString(@"Could not send call notification", nil);
            break;
            
        case kModificationErrorLobby:
            errorDescription = NSLocalizedString(@"Could not change lobby state of the conversation", nil);
            break;
            
        case kModificationErrorSIP:
            errorDescription = NSLocalizedString(@"Could not change SIP state of the conversation", nil);
            break;
            
        case kModificationErrorModeration:
            errorDescription = NSLocalizedString(@"Could not change moderation permissions of the participant", nil);
            break;
            
        case kModificationErrorRemove:
            errorDescription = NSLocalizedString(@"Could not remove participant", nil);
            break;
        
        case kModificationErrorLeave:
            errorDescription = NSLocalizedString(@"Could not leave conversation", nil);
            break;
            
        case kModificationErrorLeaveModeration:
            errorDescription = NSLocalizedString(@"You need to promote a new moderator before you can leave this conversation", nil);
            break;
            
        case kModificationErrorDelete:
            errorDescription = NSLocalizedString(@"Could not delete conversation", nil);
            break;
            
        case kModificationErrorClearHistory:
            errorDescription = NSLocalizedString(@"Could not clear chat history", nil);
            break;
            
        case kModificationErrorListable:
            errorDescription = NSLocalizedString(@"Could not change listable scope of the conversation", nil);
            break;
            
        case kModificationErrorReadOnly:
            errorDescription = NSLocalizedString(@"Could not change read-only state of the conversation", nil);
            break;
            
        case kModificationErrorMessageExpiration:
            errorDescription = NSLocalizedString(@"Could not set message expiration time", nil);
            break;
            
        default:
            break;
    }
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:errorDescription
                                        message:errorMessage
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [renameDialog addAction:okAction];
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)showConfirmationDialogForDestructiveAction:(DestructiveAction)action
{
    NSString *title = @"";
    NSString *message = @"";
    UIAlertAction *confirmAction = nil;
    
    switch (action) {
        case kDestructiveActionLeave:
        {
            title = NSLocalizedString(@"Leave conversation", nil);
            message = NSLocalizedString(@"Once a conversation is left, to rejoin a closed conversation, an invite is needed. An open conversation can be rejoined at any time.", nil);
            confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Leave", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self leaveRoom];
            }];
        }
            break;
        case kDestructiveActionClearHistory:
        {
            title = NSLocalizedString(@"Delete all messages", nil);
            message = NSLocalizedString(@"Do you really want to delete all messages in this conversation?", nil);
            confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Delete all", "Short version for confirmation button. Complete text is 'Delete all messages'.") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self clearHistory];
            }];
        }
            break;
        case kDestructiveActionDelete:
        {
            title = NSLocalizedString(@"Delete conversation", nil);
            message = _room.deletionMessage;
            confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self deleteRoom];
            }];
        }
            break;
    }
    
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:title
                                        message:message
                                 preferredStyle:UIAlertControllerStyleAlert];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)presentNotificationLevelSelector
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Notifications", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelAlways]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelMention]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelNever]];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[self getIndexPathForNotificationAction:kNotificationActionChatNotifications]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (UIAlertAction *)actionForNotificationLevel:(NCRoomNotificationLevel)level
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:[_room stringForNotificationLevel:level]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
                                                       [self setNotificationLevel:level];
                                                   }];
    if (_room.notificationLevel == level) {
        [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    return action;
}

- (void)presentMessageExpirationSelector
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Message expiration time", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpirationOff]];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpiration4Weeks]];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpiration1Week]];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpiration1Day]];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpiration8Hours]];
    [optionsActionSheet addAction:[self actionForMessageExpiration:NCMessageExpiration1Hour]];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[self getIndexPathForNotificationAction:kNotificationActionChatNotifications]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (UIAlertAction *)actionForMessageExpiration:(NCMessageExpiration)messageExpiration
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:[_room stringForMessageExpiration:messageExpiration]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
                                                       [self setMessageExpiration:messageExpiration];
                                                   }];
    if (_room.messageExpiration == messageExpiration) {
        [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    return action;
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
    [self setupLobbyDatePicker];
    [self.tableView reloadData];
}

#pragma mark - Room options

- (void)renameRoom
{
    NSString *newRoomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([newRoomName isEqualToString:_room.name]) {
        return;
    }
    if ([newRoomName isEqualToString:@""]) {
        _roomNameTextField.text = _room.name;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not set conversation name", nil)
                                       message:NSLocalizedString(@"Conversation name cannot be empty", nil)
                                       preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault
           handler:^(UIAlertAction * action) {}];

        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] renameRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withName:newRoomName andCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error renaming the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorRename];
        }
    }];
}

- (void)setNotificationLevel:(NCRoomNotificationLevel)level
{
    if (level == _room.notificationLevel) {
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setNotificationLevel:level forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting room notification level: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorChatNotifications];
        }
    }];
}

- (void)setMessageExpiration:(NCMessageExpiration)messageExpiration
{
    if (messageExpiration == _room.messageExpiration) {
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setMessageExpiration:messageExpiration forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting message expiration time: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorMessageExpiration];
        }
    }];
}

- (void)setCallNotificationEnabled:(BOOL)enabled
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setCallNotificationEnabled:enabled forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting room call notification: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorCallNotifications];
        }
        self->_callNotificationSwitch.enabled = YES;
    }];
}

- (void)showPasswordOptions
{
    NSString *alertTitle = _room.hasPassword ? NSLocalizedString(@"Set new password:", nil) : NSLocalizedString(@"Set password:", nil);
    UIAlertController *passwordDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    __weak typeof(self) weakSelf = self;
    [passwordDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = NSLocalizedString(@"Password", nil);
        textField.secureTextEntry = YES;
        textField.delegate = weakSelf;
        textField.tag = k_set_password_textfield_tag;
    }];
    
    NSString *actionTitle = _room.hasPassword ? NSLocalizedString(@"Change password", nil) : NSLocalizedString(@"OK", nil);
    _setPasswordAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = [[passwordDialog textFields][0] text];
        NSString *trimmedPassword = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:self->_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error, NSString *errorDescription) {
            if (!error) {
                [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                [self.tableView reloadData];
                [self showRoomModificationError:kModificationErrorPassword withMessage:errorDescription];
            }
        }];
    }];
    _setPasswordAction.enabled = NO;
    [passwordDialog addAction:_setPasswordAction];
    
    if (_room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Remove password", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:self->_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error, NSString *errorDescription) {
                if (!error) {
                    [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    [self.tableView reloadData];
                    [self showRoomModificationError:kModificationErrorPassword withMessage:errorDescription];
                }
            }];
        }];
        [passwordDialog addAction:removePasswordAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [passwordDialog addAction:cancelAction];
    
    [self presentViewController:passwordDialog animated:YES completion:nil];
}

- (void)resendInvitations
{
    NSIndexPath *indexPath = [self getIndexPathForGuestAction:kGuestActionResendInvitations];
    [self resendInvitationToParticipant:nil fromIndexPath:indexPath];
}

- (void)resendInvitationToParticipant:(NSString *)participant fromIndexPath:(NSIndexPath *)indexPath
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] resendInvitationToParticipant:participant inRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
            NSString *toastText = participant ? NSLocalizedString(@"Invitation resent", nil) : NSLocalizedString(@"Invitations resent", nil);
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            CGPoint toastPosition = CGPointMake(cell.center.x, cell.center.y);
            [self.view makeToast:toastText duration:1.5 position:@(toastPosition)];
        } else {
            NSLog(@"Error resending email invitations: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorResendInvitations];
        }
    }];
}

- (void)sendCallNotificationToParticipant:(NSString *)participant fromIndexPath:(NSIndexPath *)indexPath
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] sendCallNotificationToParticipant:participant inRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            CGPoint toastPosition = CGPointMake(cell.center.x, cell.center.y);
            [self.view makeToast:NSLocalizedString(@"Call notification sent", nil) duration:1.5 position:@(toastPosition)];
        } else {
            NSLog(@"Error sending call notification: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorSendCallNotification];
        }
    }];
}

- (void)makeRoomPublic
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPublic:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            NSIndexPath *indexPath = [self getIndexPathForGuestAction:kGuestActionPublicToggle];
            [self shareRoomLinkFromIndexPath:indexPath];
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorShare];
        }
        self->_publicSwitch.enabled = YES;
    }];
}

- (void)makeRoomPrivate
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPrivate:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorShare];
        }
        self->_publicSwitch.enabled = YES;
    }];
}

- (void)shareRoomLinkFromIndexPath:(NSIndexPath *)indexPath
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *joinConversationString = NSLocalizedString(@"Join the conversation at", nil);

    if (_room.displayName && ![_room.displayName isEqualToString:@""]) {
        joinConversationString = [NSString stringWithFormat:NSLocalizedString(@"Join the conversation %@ at", nil), [NSString stringWithFormat:@"\"%@\"", _room.displayName]];
    }
    NSString *shareMessage = [NSString stringWithFormat:@"%@ %@/index.php/call/%@", joinConversationString, activeAccount.server, _room.token];
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:NSLocalizedString(@"%@ invitation", nil), appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];
    
    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
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

- (void)setListableScope:(NCRoomListableScope)scope
{
    if (scope == _room.listable) {
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setListableScope:scope forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting room listable scope: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorListable];
        }
        
        self->_listableSwitch.enabled = YES;
        self->_listableForEveryoneSwitch.enabled = YES;
    }];
}

- (void)setReadOnlyState:(NCRoomReadOnlyState)state
{
    if (state == _room.readOnlyState) {
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setReadOnlyState:state forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting room readonly state: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorReadOnly];
        }
        
        self->_readOnlySwitch.enabled = true;
    }];
}

- (void)previewRoomFile:(NSIndexPath *)indexPath
{
    if (_fileDownloadIndicator) {
        // Already downloading a file
        return;
    }
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    _fileDownloadIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    
    [_fileDownloadIndicator startAnimating];
    [cell setAccessoryView:_fileDownloadIndicator];
    
    NCChatFileController *downloader = [[NCChatFileController alloc] init];
    downloader.delegate = self;
    [downloader downloadFileWithFileId:_room.objectId];
}

- (void)openRoomFileInFilesApp:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    
    [activityIndicator startAnimating];
    [cell setAccessoryView:activityIndicator];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    
    [[NCAPIController sharedInstance] getFileByFileId:activeAccount fileId:_room.objectId withCompletionBlock:^(NKFile *file, NSInteger error, NSString *errorDescription) {

        dispatch_async(dispatch_get_main_queue(), ^{
            [activityIndicator stopAnimating];
            [cell setAccessoryView:nil];
        });
        
        if (file) {
            NSString *remoteDavPrefix = [NSString stringWithFormat:@"/remote.php/dav/files/%@/", activeAccount.userId];
            NSString *directoryPath = [file.path componentsSeparatedByString:remoteDavPrefix].lastObject;
            
            NSString *filePath = [NSString stringWithFormat:@"%@%@", directoryPath, file.fileName];
            NSString *fileLink = [NSString stringWithFormat:@"%@/index.php/f/%@", activeAccount.server, self->_room.objectId];
            
            NSLog(@"File path: %@ fileLink: %@", filePath, fileLink);

            [NCUtils openFileInNextcloudAppOrBrowser:filePath withFileLink:fileLink];
        } else {
            NSLog(@"An error occurred while getting file with fileId %@: %@", self->_room.objectId, errorDescription);
            
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"Unable to open file", nil)
                                         message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while opening the file %@", nil), self->_room.name]
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];
            
            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        }
    }];
}

- (void)presentSharedItemsView
{
    RoomSharedItemsTableViewController *sharedItemsVC = [[RoomSharedItemsTableViewController alloc] initWithRoom:_room];
    [self.navigationController pushViewController:sharedItemsVC animated:YES];
}

- (void)clearHistory
{
    [[NCAPIController sharedInstance] clearChatHistoryInRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *messageDict, NSError *error, NSInteger statusCode) {
        if (!error) {
            NSLog(@"Chat history cleared.");
            NSIndexPath *indexPath = [self getIndexPathForDestructiveAction:kDestructiveActionClearHistory];
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            CGPoint toastPosition = CGPointMake(cell.center.x, cell.center.y);
            [self.view makeToast:NSLocalizedString(@"All messages were deleted", nil) duration:1.5 position:@(toastPosition)];
        } else {
            NSLog(@"Error clearing chat history: %@", error.description);
            [self showRoomModificationError:kModificationErrorClearHistory];
        }
    }];
}

- (void)leaveRoom
{
    [[NCAPIController sharedInstance] removeSelfFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSInteger errorCode, NSError *error) {
        if (!error) {
            if (self->_chatViewController) {
                [self->_chatViewController leaveChat];
            }
            [[NCUserInterfaceController sharedInstance] presentConversationsList];
        } else if (errorCode == 400) {
            [self showRoomModificationError:kModificationErrorLeaveModeration];
        } else {
            NSLog(@"Error leaving the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorLeave];
        }
    }];
}

- (void)deleteRoom
{
    [[NCAPIController sharedInstance] deleteRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            if (self->_chatViewController) {
                [self->_chatViewController leaveChat];
            }
            [[NCUserInterfaceController sharedInstance] presentConversationsList];
        } else {
            NSLog(@"Error deleting the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorDelete];
        }
    }];
}

#pragma mark - Webinar options

- (void)enableLobby
{
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:0];
}

- (void)disableLobby
{
    [self setLobbyState:NCRoomLobbyStateAllParticipants withTimer:0];
}

- (void)setLobbyState:(NCRoomLobbyState)lobbyState withTimer:(NSInteger)timer
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setLobbyState:lobbyState withTimer:timer forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error changing lobby state in room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorLobby];
        }
        self->_lobbySwitch.enabled = YES;
    }];
}

- (void)setLobbyDate
{
    NSInteger lobbyTimer = _lobbyDatePicker.date.timeIntervalSince1970;
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:lobbyTimer];
    
    NSString *lobbyTimerReadable = [NCUtils readableDateTimeFromDate:_lobbyDatePicker.date];
    _lobbyDateTextField.text = [NSString stringWithFormat:@"%@",lobbyTimerReadable];
    [self dismissLobbyDatePicker];
}

- (void)removeLobbyDate
{
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:0];
    [self dismissLobbyDatePicker];
}

- (void)dismissLobbyDatePicker
{
    [_lobbyDateTextField resignFirstResponder];
}

- (void)setupLobbyDatePicker
{
    [_lobbyDatePicker setMinimumDate:[NSDate new]];
    // Round up default lobby timer to next hour
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components: NSCalendarUnitEra|NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour fromDate: [NSDate new]];
    [components setHour: [components hour] + 1];
    [_lobbyDatePicker setDate:[calendar dateFromComponents:components]];
    
    UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismissLobbyDatePicker)];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(setLobbyDate)];
    UIBarButtonItem *space = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [toolBar setItems:[NSArray arrayWithObjects:cancelButton, space,doneButton, nil]];
    [_lobbyDateTextField setInputAccessoryView:toolBar];
    
    if (_room.lobbyTimer > 0) {
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
        UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Remove", nil) style:UIBarButtonItemStylePlain target:self action:@selector(removeLobbyDate)];
        [clearButton setTintColor:[UIColor redColor]];
        [toolBar setItems:[NSArray arrayWithObjects:clearButton, space, doneButton, nil]];
        [_lobbyDatePicker setDate:date];
    }
}

- (void)setSIPState:(NCRoomSIPState)state
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setSIPState:state forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error changing SIP state in room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorSIP];
        }
        self->_sipSwitch.enabled = YES;
        self->_sipNoPINSwitch.enabled = YES;
    }];
}

#pragma mark - Participant options

- (void)addParticipantsButtonPressed
{
    AddParticipantsTableViewController *addParticipantsVC = [[AddParticipantsTableViewController alloc] initForRoom:_room];
    addParticipantsVC.delegate = self;
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:addParticipantsVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)addParticipantsTableViewControllerDidFinish:(AddParticipantsTableViewController *)viewController
{
    [self getRoomParticipants];
}

- (void)showOptionsForParticipantAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
    
    BOOL canParticipantBeModerated = participant.participantType != kNCParticipantTypeOwner && ![self isAppUser:participant] && _room.canModerate;
    
    BOOL canParticipantBeNotifiedAboutCall =
    ![self isAppUser:participant] &&
    (_room.permissions & NCPermissionStartCall) &&
    _room.participantFlags > CallFlagDisconnected &&
    participant.inCall == CallFlagDisconnected &&
    [participant.actorType isEqualToString:NCAttendeeTypeUser] &&
    [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySendCallNotification];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:[self detailedNameForParticipant:participant]
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (canParticipantBeModerated && participant.canBeDemoted) {
        UIAlertAction *demoteFromModerator = [UIAlertAction actionWithTitle:NSLocalizedString(@"Demote from moderator", nil)
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self demoteFromModerator:participant];
                                                                    }];
        [demoteFromModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:demoteFromModerator];
    } else if (canParticipantBeModerated && participant.canBePromoted) {
        UIAlertAction *promoteToModerator = [UIAlertAction actionWithTitle:NSLocalizedString(@"Promote to moderator", nil)
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self promoteToModerator:participant];
                                                                   }];
        [promoteToModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:promoteToModerator];
    }
    
    if (canParticipantBeNotifiedAboutCall) {
        UIAlertAction *sendCallNotification = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send call notification", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self sendCallNotificationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [sendCallNotification setValue:[[UIImage imageNamed:@"notifications"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:sendCallNotification];
    }
    
    if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
        UIAlertAction *resendInvitation = [UIAlertAction actionWithTitle:NSLocalizedString(@"Resend invitation", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self resendInvitationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [resendInvitation setValue:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:resendInvitation];
    }
    
    if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
        UIAlertAction *resendInvitation = [UIAlertAction actionWithTitle:NSLocalizedString(@"Resend invitation", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self resendInvitationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [resendInvitation setValue:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:resendInvitation];
    }
    
    if (canParticipantBeModerated) {
        // Remove participant
        NSString *title = NSLocalizedString(@"Remove participant", nil);
        if (participant.isGroup) {
            title = NSLocalizedString(@"Remove group and members", nil);
        } else if (participant.isCircle) {
            title = NSLocalizedString(@"Remove circle and members", nil);
        }
        UIAlertAction *removeParticipant = [UIAlertAction actionWithTitle:title
                                                                    style:UIAlertActionStyleDestructive
                                                                  handler:^void (UIAlertAction *action) {
                                                                      [self removeParticipant:participant];
                                                                  }];
        [removeParticipant setValue:[[UIImage imageNamed:@"delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:removeParticipant];
    }
    
    if (optionsActionSheet.actions.count == 0) {return;}
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)promoteToModerator:(NCRoomParticipant *)participant
{
    [self setModifyingRoomUI];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *participantId = participant.participantId;
    if ([[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount] >= APIv3) {
        participantId = [NSString stringWithFormat:@"%ld", (long)participant.attendeeId];
    }
    [[NCAPIController sharedInstance] promoteParticipant:participantId toModeratorOfRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
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
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *participantId = participant.participantId;
    if ([[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount] >= APIv3) {
        participantId = [NSString stringWithFormat:@"%ld", (long)participant.attendeeId];
    }
    [[NCAPIController sharedInstance] demoteModerator:participantId toParticipantOfRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
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
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSInteger conversationAPIVersion = [[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount];
    if (conversationAPIVersion >= APIv3) {
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] removeAttendee:participant.attendeeId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self getRoomParticipants];
            } else {
                NSLog(@"Error removing attendee from room: %@", error.description);
                [self showRoomModificationError:kModificationErrorRemove];
            }
        }];
    } else {
        if (participant.isGuest) {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] removeGuest:participant.participantId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self getRoomParticipants];
                } else {
                    NSLog(@"Error removing guest from room: %@", error.description);
                    [self showRoomModificationError:kModificationErrorRemove];
                }
            }];
        } else {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] removeParticipant:participant.participantId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self getRoomParticipants];
                } else {
                    NSLog(@"Error removing participant from room: %@", error.description);
                    [self showRoomModificationError:kModificationErrorRemove];
                }
            }];
        }
    }
}

- (NSString *)detailedNameForParticipant:(NCRoomParticipant *)participant
{
    if (participant.canModerate && (_room.type == kNCRoomTypeOneToOne || _room.type == kNCRoomTypeFormerOneToOne)) {
        return participant.displayName;
    }
    return participant.detailedName;
}

#pragma mark - Public switch

- (void)publicValueChanged:(id)sender
{
    _publicSwitch.enabled = NO;
    if (_publicSwitch.on) {
        [self makeRoomPublic];
    } else {
        [self makeRoomPrivate];
    }
}

#pragma mark - Lobby switch

- (void)lobbyValueChanged:(id)sender
{
    _lobbySwitch.enabled = NO;
    if (_lobbySwitch.on) {
        [self enableLobby];
    } else {
        [self disableLobby];
    }
}

#pragma mark - Listable switches

- (void)listableValueChanged:(id)sender
{
    _listableSwitch.enabled = NO;
    _listableForEveryoneSwitch.enabled = NO;
    if (_listableSwitch.on) {
        [self setListableScope:NCRoomListableScopeRegularUsersOnly];
    } else {
        [self setListableScope:NCRoomListableScopeParticipantsOnly];
    }
}

- (void)listableForEveryoneValueChanged:(id)sender
{
    _listableSwitch.enabled = NO;
    _listableForEveryoneSwitch.enabled = NO;
    if (_listableForEveryoneSwitch.on) {
        [self setListableScope:NCRoomListableScopeEveryone];
    } else {
        [self setListableScope:NCRoomListableScopeRegularUsersOnly];
    }
}


#pragma mark - ReadOnly switch

- (void)readOnlyValueChanged:(id)sender
{
    _readOnlySwitch.enabled = NO;
    if (_readOnlySwitch.on) {
        [self setReadOnlyState:NCRoomReadOnlyStateReadOnly];
    } else {
        [self setReadOnlyState:NCRoomReadOnlyStateReadWrite];
    }
}

#pragma mark - SIP switch

- (void)sipValueChanged:(id)sender
{
    _sipSwitch.enabled = NO;
    _sipNoPINSwitch.enabled = NO;
    if (_sipSwitch.on) {
        [self setSIPState:NCRoomSIPStateEnabled];
    } else {
        [self setSIPState:NCRoomSIPStateDisabled];
    }
}

- (void)sipNoPINValueChanged:(id)sender
{
    _sipSwitch.enabled = NO;
    _sipNoPINSwitch.enabled = NO;
    if (_sipNoPINSwitch.on) {
        [self setSIPState:NCRoomSIPStateEnabledWithoutPIN];
    } else {
        [self setSIPState:NCRoomSIPStateEnabled];
    }
}

#pragma mark - Call notifications switch

- (void)callNotificationValueChanged:(id)sender
{
    _callNotificationSwitch.enabled = NO;
    if (_callNotificationSwitch.on) {
        [self setCallNotificationEnabled:YES];
    } else {
        [self setCallNotificationEnabled:NO];
    }
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    // Allow click on tableview cells
    if ([touch.view isDescendantOfView:self.tableView]) {
        if (![touch.view isDescendantOfView:_roomNameTextField]) {
            [self dismissKeyboard];
        }
        return NO;
    }
    return YES;
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

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == _roomNameTextField || textField.tag == k_set_password_textfield_tag) {
        // Prevent crashing undo bug
        // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
        if (range.length + range.location > textField.text.length) {
            return NO;
        }
        // Set maximum character length
        NSUInteger newLength = [textField.text length] + [string length] - range.length;
        BOOL hasAllowedLength = newLength <= 200;
        // Enable/Disable password confirmation button
        if (hasAllowedLength) {
            NSString *newValue = [[textField.text stringByReplacingCharactersInRange:range withString:string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            _setPasswordAction.enabled = (newValue.length > 0);
        }
        return hasAllowedLength;
    }
    return YES;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getRoomInfoSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionNotifications:
            return [self getNotificationsActions].count;
            break;
            
        case kRoomInfoSectionFile:
            return [self getFileActions].count;
            break;
            
        case kRoomInfoSectionSharedItems:
            return 1;
            break;
            
        case kRoomInfoSectionGuests:
            return [self getGuestsActions].count;
            break;
            
        case kRoomInfoSectionConversation:
            return [self getConversationActions].count;
            break;
            
        case kRoomInfoSectionWebinar:
            return [self getWebinarActions].count;
            break;
            
        case kRoomInfoSectionSIP:
            return kSIPActionNumber;
            break;
            
        case kRoomInfoSectionParticipants:
            return _roomParticipants.count;
            break;
            
        case kRoomInfoSectionDestructive:
            return [self getRoomDestructiveActions].count;
            break;
        default:
            break;
    }
    
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:indexPath.section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionName:
            return 80;
            break;
        case kRoomInfoSectionDescription:
            return [self heightForDescription:_room.roomDescription];
            break;
        case kRoomInfoSectionSIP:
            if (indexPath.row == kSIPActionSIPInfo) {
                TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
                NSDictionary *activeAccountSignalingConfig  = [[[NCSettingsController sharedInstance] signalingConfigutations] objectForKey:activeAccount.accountId];
                return [self heightForDescription:[activeAccountSignalingConfig objectForKey:@"sipDialinInfo"]];
            }
            break;
        case kRoomInfoSectionParticipants:
            return kContactsTableCellHeight;
            break;
        default:
            break;
    }
    return 48;
}

- (CGFloat)heightForDescription:(NSString *)description
{
    CGFloat width = CGRectGetWidth(self.tableView.frame) - 32;
    width -= self.tableView.safeAreaInsets.left + self.tableView.safeAreaInsets.right;

    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:17]};
    CGRect bodyBounds = [description boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:NULL];
    
    return ceil(bodyBounds.size.height) + 22;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionFile:
            return NSLocalizedString(@"Linked file", nil);
            break;
        case kRoomInfoSectionSharedItems:
            return NSLocalizedString(@"Shared items", nil);
            break;
        case kRoomInfoSectionNotifications:
            return NSLocalizedString(@"Notifications", nil);
            break;
        case kRoomInfoSectionGuests:
            return NSLocalizedString(@"Guests access", nil);
            break;
        case kRoomInfoSectionConversation:
            return NSLocalizedString(@"Conversation settings", nil);
            break;
        case kRoomInfoSectionWebinar:
            return NSLocalizedString(@"Meeting settings", nil);
            break;
        case kRoomInfoSectionSIP:
            return NSLocalizedString(@"SIP dial-in", nil);
            break;
        default:
            break;
    }
    
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionParticipants:
        {
            NSString *title = [NSString localizedStringWithFormat:NSLocalizedString(@"%ld participants", nil), _roomParticipants.count];
            _headerView.label.text = [title uppercaseString];
            _headerView.button.hidden = (_room.canModerate) ? NO : YES;
            return _headerView;
        }
            break;
        default:
            break;
    }
    
    return nil;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionDescription:
            return 2;
            break;
        case kRoomInfoSectionNotifications:
        case kRoomInfoSectionFile:
        case kRoomInfoSectionSharedItems:
        case kRoomInfoSectionGuests:
        case kRoomInfoSectionConversation:
        case kRoomInfoSectionWebinar:
        case kRoomInfoSectionSIP:
            return 36;
            break;
        case kRoomInfoSectionParticipants:
            return 40;
            break;
        default:
            break;
    }
    
    return 25;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *chatnotificationLevelCellIdentifier = @"ChatNotificationLevelCellIdentifier";
    static NSString *callnotificationCellIdentifier = @"CallNotificationCellIdentifier";
    static NSString *allowGuestsCellIdentifier = @"AllowGuestsCellIdentifier";
    static NSString *passwordCellIdentifier = @"PasswordCellIdentifier";
    static NSString *shareLinkCellIdentifier = @"ShareLinkCellIdentifier";
    static NSString *resendInvitationsCellIdentifier = @"ResendInvitationsCellIdentifier";
    static NSString *previewFileCellIdentifier = @"PreviewFileCellIdentifier";
    static NSString *openFileCellIdentifier = @"OpenFileCellIdentifier";
    static NSString *lobbyCellIdentifier = @"LobbyCellIdentifier";
    static NSString *lobbyTimerCellIdentifier = @"LobbyTimerCellIdentifier";
    static NSString *sipCellIdentifier = @"SIPCellIdentifier";
    static NSString *sipNoPINCellIdentifier = @"SIPNoPINCellIdentifier";
    static NSString *sipMeetingIDCellIdentifier = @"SIPMeetingIDCellIdentifier";
    static NSString *sipUserPINCellIdentifier = @"SIPUserPINCellIdentifier";
    static NSString *clearHistoryCellIdentifier = @"ClearHistoryCellIdentifier";
    static NSString *leaveRoomCellIdentifier = @"LeaveRoomCellIdentifier";
    static NSString *deleteRoomCellIdentifier = @"DeleteRoomCellIdentifier";
    static NSString *sharedItemsCellIdentifier = @"SharedItemsCellIdentifier";
    static NSString *messageExpirationCellIdentifier = @"MessageExpirationCellIdentifier";
    static NSString *listableCellIdentifier = @"ListableCellIdentifier";
    static NSString *listableForEveryoneCellIdentifier = @"ListableForEveryoneCellIdentifier";
    static NSString *readOnlyStateCellIdentifier = @"ReadOnlyStateCellIdentifier";
    
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kRoomInfoSectionName:
        {
            RoomNameTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomNameCellIdentifier];
            if (!cell) {
                cell = [[RoomNameTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomNameCellIdentifier];
            }
            
            cell.roomNameTextField.text = _room.name;
            
            switch (_room.type) {
                case kNCRoomTypeOneToOne:
                {
                    cell.roomNameTextField.text = _room.displayName;
                    [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                          placeholderImage:nil success:nil failure:nil];
                    [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
                }
                    break;
                    
                case kNCRoomTypeGroup:
                    [cell.roomImage setImage:[UIImage imageNamed:@"group"]];
                    break;
                    
                case kNCRoomTypePublic:
                    [cell.roomImage setImage:[UIImage imageNamed:@"public"]];
                    break;
                    
                case kNCRoomTypeChangelog:
                {
                    cell.roomNameTextField.text = _room.displayName;
                    [cell.roomImage setImage:[UIImage imageNamed:@"changelog"]];
                    [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
                }
                    break;

                case kNCRoomTypeFormerOneToOne:
                    [cell.roomImage setImage:[UIImage imageNamed:@"user"]];
                    break;

                default:
                    break;
            }
            
            // Set objectType image
            if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
                [cell.roomImage setImage:[UIImage imageNamed:@"file-conv"]];
            } else if ([_room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
                [cell.roomImage setImage:[UIImage imageNamed:@"pass-conv"]];
            }
            
            if (_room.isNameEditable) {
                _roomNameTextField = cell.roomNameTextField;
                _roomNameTextField.delegate = self;
                [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
                cell.userInteractionEnabled = YES;
            } else {
                _roomNameTextField = nil;
                cell.userInteractionEnabled = NO;
            }
            
            if (_room.isFavorite) {
                [cell.favoriteImage setImage:[UIImage imageNamed:@"favorite-room"]];
            }
            
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
            break;
        case kRoomInfoSectionDescription:
        {
            RoomDescriptionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomDescriptionCellIdentifier];
            if (!cell) {
                cell = [[RoomDescriptionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomDescriptionCellIdentifier];
            }
            
            cell.textView.text = _room.roomDescription;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
            break;
        case kRoomInfoSectionNotifications:
        {
            NSArray *actions = [self getNotificationsActions];
            NotificationAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kNotificationActionChatNotifications:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:chatnotificationLevelCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:chatnotificationLevelCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Chat messages", nil);
                    cell.detailTextLabel.text = _room.notificationLevelString;
                    [cell.imageView setImage:[[UIImage imageNamed:@"notifications"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
                case kNotificationActionCallNotifications:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:callnotificationCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:callnotificationCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Calls", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _callNotificationSwitch;
                    _callNotificationSwitch.on = _room.notificationCalls;
                    [cell.imageView setImage:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionFile:
        {
            NSArray *actions = [self getFileActions];
            FileAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kFileActionPreview:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:previewFileCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:previewFileCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Preview", nil);
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    [cell.imageView setImage:[UIImage imageNamed:@"preview-file-settings"]];
                    
                    if (_fileDownloadIndicator) {
                        // Set download indicator in case we're already downloading a file
                        [cell setAccessoryView:_fileDownloadIndicator];
                    }
                    
                    return cell;
                }
                    break;
                case kFileActionOpenInFilesApp:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:openFileCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:openFileCellIdentifier];
                    }
                    
                    cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Open in %@", nil), filesAppName];
                    
                    UIImage *nextcloudActionImage = [[UIImage imageNamed:@"logo-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [cell.imageView setImage:nextcloudActionImage];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                                        
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionSharedItems:
        {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sharedItemsCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sharedItemsCellIdentifier];
            }
            
            cell.textLabel.text = NSLocalizedString(@"Images, files, voice messages…", nil);
            
            UIImage *nextcloudActionImage = [[UIImage imageNamed:@"folder-multiple-media"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [cell.imageView setImage:nextcloudActionImage];
            cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            
            return cell;
        }
            break;
        case kRoomInfoSectionGuests:
        {
            NSArray *actions = [self getGuestsActions];
            GuestAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kGuestActionPublicToggle:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:allowGuestsCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:allowGuestsCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Allow guests", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _publicSwitch;
                    _publicSwitch.on = (_room.type == kNCRoomTypePublic) ? YES : NO;
                    [cell.imageView setImage:[UIImage imageNamed:@"public-setting"]];
                    
                    return cell;
                }
                    break;
                    
                case kGuestActionPassword:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:passwordCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:passwordCellIdentifier];
                    }
                    
                    cell.textLabel.text = (_room.hasPassword) ? NSLocalizedString(@"Change password", nil) : NSLocalizedString(@"Set password", nil);
                    [cell.imageView setImage:(_room.hasPassword) ? [UIImage imageNamed:@"password-settings"] : [UIImage imageNamed:@"no-password-settings"]];
                    
                    return cell;
                }
                    break;

                case kGuestActionResendInvitations:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:resendInvitationsCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:resendInvitationsCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Resend invitations", nil);
                    
                    UIImage *nextcloudActionImage = [[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [cell.imageView setImage:nextcloudActionImage];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionConversation:
        {
            NSArray *actions = [self getConversationActions];
            ConversationAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kConversationActionMessageExpiration:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:messageExpirationCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:messageExpirationCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Message expiration", nil);
                    cell.detailTextLabel.text = _room.messageExpirationString;
                    [cell.imageView setImage:[[UIImage imageNamed:@"auto-delete"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
                case kConversationActionListable:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:listableCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:listableCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Open conversation to registered users", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _listableSwitch;
                    _listableSwitch.on = (_room.listable != NCRoomListableScopeParticipantsOnly);
                    [cell.imageView setImage:[[UIImage imageNamed:@"listable-conversation"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
                case kConversationActionListableForEveryone:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:listableForEveryoneCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:listableForEveryoneCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Also open to guest app users", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _listableForEveryoneSwitch;
                    _listableForEveryoneSwitch.on = (_room.listable == NCRoomListableScopeEveryone);
                    
                    // Still assign an image, but hide it to keep the margin the same as the other cells
                    [cell.imageView setImage:[[UIImage imageNamed:@"listable-conversation"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setHidden:YES];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
                case kConversationActionReadOnly:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:readOnlyStateCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:readOnlyStateCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Lock conversation", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _readOnlySwitch;
                    _readOnlySwitch.on = _room.readOnlyState;
                    [cell.imageView setImage:[[UIImage imageNamed:@"message-text-lock"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;

                case kConversationActionShareLink:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:shareLinkCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:shareLinkCellIdentifier];
                    }

                    cell.textLabel.text = NSLocalizedString(@"Share link", nil);
                    [cell.imageView setImage:[[UIImage imageNamed:@"share"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];

                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionWebinar:
        {
            NSArray *actions = [self getWebinarActions];
            WebinarAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kWebinarActionLobby:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:lobbyCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:lobbyCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Lobby", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbySwitch;
                    _lobbySwitch.on = (_room.lobbyState == NCRoomLobbyStateModeratorsOnly) ? YES : NO;
                    [cell.imageView setImage:[UIImage imageNamed:@"lobby"]];
                    
                    return cell;
                }
                    break;
                case kWebinarActionLobbyTimer:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:lobbyTimerCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:lobbyTimerCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Start time", nil);
                    cell.textLabel.adjustsFontSizeToFitWidth = YES;
                    cell.textLabel.minimumScaleFactor = 0.6;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbyDateTextField;
                    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
                    _lobbyDateTextField.text = _room.lobbyTimer > 0 ? [NCUtils readableDateTimeFromDate:date] : nil;
                    [cell.imageView setImage:[UIImage imageNamed:@"timer"]];
                    
                    return cell;
                }
                    break;
                case kWebinarActionSIP:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sipCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"SIP dial-in", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _sipSwitch;
                    _sipSwitch.on = _room.sipState > NCRoomSIPStateDisabled;
                    [cell.imageView setImage:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
                case kWebinarActionSIPNoPIN:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipNoPINCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sipNoPINCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Allow to dial-in without a pin", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _sipNoPINSwitch;
                    _sipNoPINSwitch.on = _room.sipState > NCRoomSIPStateEnabled;
                    
                    // Still assign an image, but hide it to keep the margin the same as the other cells
                    [cell.imageView setImage:[[UIImage imageNamed:@"phone"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setHidden:YES];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionSIP:
        {
            switch (indexPath.row) {
                case kSIPActionSIPInfo:
                {
                    RoomDescriptionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomDescriptionCellIdentifier];
                    if (!cell) {
                        cell = [[RoomDescriptionTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomDescriptionCellIdentifier];
                    }
                    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
                    NSDictionary *activeAccountSignalingConfig  = [[[NCSettingsController sharedInstance] signalingConfigutations] objectForKey:activeAccount.accountId];
                    cell.textView.text = [activeAccountSignalingConfig objectForKey:@"sipDialinInfo"];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    return cell;
                }
                    break;
                case kSIPActionMeetingId:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipMeetingIDCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sipMeetingIDCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Meeting ID", nil);
                    cell.detailTextLabel.text = _room.token;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    return cell;
                }
                    break;
                case kSIPActionPIN:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipUserPINCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sipUserPINCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Your PIN", nil);
                    cell.detailTextLabel.text = _room.attendeePin;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionParticipants:
        {
            NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
            ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
            if (!cell) {
                cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
            }
            
            // Display name
            cell.labelTitle.text = [self detailedNameForParticipant:participant];
            
            // Avatar
            if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
                [cell.contactImage setImage:[UIImage imageNamed:@"mail"]];
            } else if (participant.isGroup || participant.isCircle) {
                [cell.contactImage setImage:[UIImage imageNamed:@"group"]];
            } else if (participant.isGuest) {
                UIColor *guestAvatarColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
                NSString *avatarName = ([participant.displayName isEqualToString:@""]) ? @"?" : participant.displayName;
                [cell.contactImage setImageWithString:avatarName color:guestAvatarColor circular:true];
            } else {
                [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.participantId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                         placeholderImage:nil success:nil failure:nil];
                [cell.contactImage setContentMode:UIViewContentModeScaleToFill];
            }
            
            // Online status
            if (participant.isOffline) {
                cell.contactImage.alpha = 0.5;
                cell.labelTitle.alpha = 0.5;
                cell.userStatusMessageLabel.alpha = 0.5;
            } else {
                cell.contactImage.alpha = 1;
                cell.labelTitle.alpha = 1;
                cell.userStatusMessageLabel.alpha = 1;
            }
            
            // User status
            [cell setUserStatus:participant.status];
            
            //User status message
            [cell setUserStatusMessage:participant.statusMessage withIcon:participant.statusIcon];
            
            if (!participant.statusMessage || [participant.statusMessage isEqualToString:@""]) {
                if ([participant.status isEqualToString: kUserStatusDND]) {
                    [cell setUserStatusMessage:NSLocalizedString(@"Do not disturb", nil) withIcon:nil];
                } else if ([participant.status isEqualToString:kUserStatusAway]) {
                    [cell setUserStatusMessage: NSLocalizedString(@"Away", nil) withIcon:nil];
                }
            }
            
            // Call status
            if (participant.callIconImageName) {
                cell.accessoryView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:participant.callIconImageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                [cell.accessoryView setTintColor:[NCAppBranding placeholderColor]];
            } else {
                cell.accessoryView = nil;
            }
            
            cell.layoutMargins = UIEdgeInsetsMake(0, 72, 0, 0);
            
            return cell;
        }
            break;
        case kRoomInfoSectionDestructive:
        {
            NSArray *actions = [self getRoomDestructiveActions];
            DestructiveAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kDestructiveActionLeave:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:leaveRoomCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:leaveRoomCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Leave conversation", nil);
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[[UIImage imageNamed:@"exit-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setTintColor:[UIColor systemRedColor]];
                    
                    return cell;
                }
                    break;
                case kDestructiveActionClearHistory:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:clearHistoryCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:clearHistoryCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Delete all messages", nil);
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[[UIImage imageNamed:@"delete-chat"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setTintColor:[UIColor systemRedColor]];
                    
                    return cell;
                }
                    break;
                case kDestructiveActionDelete:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:deleteRoomCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:deleteRoomCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Delete conversation", nil);
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[[UIImage imageNamed:@"delete-forever"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setTintColor:[UIColor systemRedColor]];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kRoomInfoSectionName:
            break;
        case kRoomInfoSectionFile:
        {
            NSArray *actions = [self getFileActions];
            FileAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kFileActionPreview:
                    [self previewRoomFile:indexPath];
                    break;
                case kFileActionOpenInFilesApp:
                    [self openRoomFileInFilesApp:indexPath];
                    break;
            }
        }
            break;
        case kRoomInfoSectionSharedItems:
        {
            [self presentSharedItemsView];
        }
            break;
        case kRoomInfoSectionNotifications:
        {
            NSArray *actions = [self getNotificationsActions];
            NotificationAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kNotificationActionChatNotifications:
                    [self presentNotificationLevelSelector];
                    break;
                default:
                    break;
            }
        }
            break;
        case kRoomInfoSectionGuests:
        {
            NSArray *actions = [self getGuestsActions];
            GuestAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kGuestActionPassword:
                    [self showPasswordOptions];
                    break;
                case kGuestActionResendInvitations:
                    [self resendInvitations];
                    break;
                default:
                    break;
            }
        }
            break;
        case kRoomInfoSectionConversation:
        {
            NSArray *actions = [self getConversationActions];
            ConversationAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kConversationActionMessageExpiration:
                    [self presentMessageExpirationSelector];
                    break;
                case kConversationActionShareLink:
                    [self shareRoomLinkFromIndexPath:indexPath];
                    break;
                default:
                    break;
            }
        }
            break;
        case kRoomInfoSectionParticipants:
        {
            [self showOptionsForParticipantAtIndexPath:indexPath];
        }
            break;
        case kRoomInfoSectionDestructive:
        {
            NSArray *actions = [self getRoomDestructiveActions];
            DestructiveAction action = [[actions objectAtIndex:indexPath.row] intValue];
            [self showConfirmationDialogForDestructiveAction:action];
        }
            break;
        default:
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - NCChatFileControllerDelegate

- (void)fileControllerDidLoadFile:(NCChatFileController *)fileController withFileStatus:(NCChatFileStatus *)fileStatus
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_fileDownloadIndicator) {
            [self->_fileDownloadIndicator stopAnimating];
            [self->_fileDownloadIndicator removeFromSuperview];
            self->_fileDownloadIndicator = nil;
        }
            
        NSInteger fileSection = [[self getRoomInfoSections] indexOfObject:@(kRoomInfoSectionFile)];
        NSInteger previewRow = [[self getFileActions] indexOfObject:@(kFileActionPreview)];
        NSIndexPath *previewActionIndexPath = [NSIndexPath indexPathForRow:previewRow inSection:fileSection];
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:previewActionIndexPath];
        
        if (cell) {
            // Only show preview controller if cell is still visible
            self->_previewControllerFilePath = fileStatus.fileLocalPath;

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

            [self.navigationController pushViewController:preview animated:YES];
            
            // Make sure disclosure indicator is visible again (otherwise accessoryView is empty)
            cell.accessoryView = nil;
        }
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


@end
