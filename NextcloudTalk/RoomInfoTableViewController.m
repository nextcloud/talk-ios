/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "RoomInfoTableViewController.h"

@import NextcloudKit;

#import <QuickLook/QuickLook.h>

#import "UIView+Toast.h"
#import "JDStatusBarNotification.h"

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
    kConversationActionBannedActors,
    kConversationActionListable,
    kConversationActionListableForEveryone,
    kConversationActionMentionPermission,
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
    kModificationErrorChatNotifications = 0,
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
    kModificationErrorMessageExpiration,
    kModificationErrorRoomDescription,
    kModificationErrorBanActor,
    kModificationErrorMentionPermissions,
} ModificationError;

typedef enum FileAction {
    kFileActionPreview = 0,
    kFileActionOpenInFilesApp
} FileAction;

@interface RoomInfoTableViewController () <UITextFieldDelegate, AddParticipantsTableViewControllerDelegate, NCChatFileControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) ChatViewController *chatViewController;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;;
@property (nonatomic, strong) UISwitch *publicSwitch;
@property (nonatomic, strong) UISwitch *listableSwitch;
@property (nonatomic, strong) UISwitch *listableForEveryoneSwitch;
@property (nonatomic, strong) UISwitch *mentionPermissionsSwitch;
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
@property (nonatomic, strong) UIAlertAction *banAction;

@property (nonatomic, weak) UITextField *setPasswordTextField;
@property (nonatomic, weak) UITextField *banInternalNoteTextField;

@end

@implementation RoomInfoTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    return [self initForRoom:room fromChatViewController:nil];
}

- (instancetype)initForRoom:(NCRoom *)room fromChatViewController:(ChatViewController *)chatViewController
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
    
    self.navigationItem.title = NSLocalizedString(@"Conversation settings", nil);
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

    _mentionPermissionsSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_mentionPermissionsSwitch addTarget: self action: @selector(mentionPermissionsValueChanged:) forControlEvents:UIControlEventValueChanged];

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
    [self.tableView registerNib:[UINib nibWithNibName:RoomNameTableViewCell.nibName bundle:nil] forCellReuseIdentifier:RoomNameTableViewCell.identifier];
    [self.tableView registerClass:TextViewTableViewCell.class forCellReuseIdentifier:TextViewTableViewCell.identifier];

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
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRichObjectListMedia] &&
        ![self.room isFederated]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionSharedItems]];
    }
    // Notifications section
    if ([self getNotificationsActions].count > 0) {
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
    if (!_hideDestructiveActions) {
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

    if (_room.type == kNCRoomTypeChangelog || _room.type == kNCRoomTypeNoteToSelf) {
        return actions;
    }

    // Chat notifications levels action
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels]) {
        [actions addObject:[NSNumber numberWithInt:kNotificationActionChatNotifications]];
    }
    // Call notifications action
    if ([[NCDatabaseManager sharedInstance] roomHasTalkCapability:kCapabilityNotificationCalls forRoom:self.room] && 
        [[NCDatabaseManager sharedInstance] roomTalkCapabilitiesForRoom:self.room].callEnabled &&
        ![self.room isFederated]) {
        
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
    if ([_room supportsMessageExpirationModeration]) {
        [actions addObject:[NSNumber numberWithInt:kConversationActionMessageExpiration]];
    }

    // Banning actors
    if ([_room supportsBanningModeration]) {
        [actions addObject:[NSNumber numberWithInt:kConversationActionBannedActors]];
    }

    if (_room.canModerate) {
        // Listable room action
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityListableRooms]) {
            [actions addObject:[NSNumber numberWithInt:kConversationActionListable]];
            
            if (_room.listable != NCRoomListableScopeParticipantsOnly && [[NCSettingsController sharedInstance] isGuestsAppEnabled]) {
                [actions addObject:[NSNumber numberWithInt:kConversationActionListableForEveryone]];
            }
        }

        // Mention permission
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityMentionPermissions]) {
            [actions addObject:[NSNumber numberWithInt:kConversationActionMentionPermission]];
        }

        // Read only room action
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityReadOnlyRooms]) {
            [actions addObject:[NSNumber numberWithInt:kConversationActionReadOnly]];
        }
    }

    if (_room.type != kNCRoomTypeChangelog && _room.type != kNCRoomTypeNoteToSelf) {
        [actions addObject:[NSNumber numberWithInt:kConversationActionShareLink]];
    }
    
    return [NSArray arrayWithArray:actions];
}

- (NSIndexPath *)getIndexPathForConversationAction:(ConversationAction)action
{
    NSInteger section = [self getSectionForRoomInfoSection:kRoomInfoSectionConversation];
    NSIndexPath *actionIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
    NSInteger actionRow = [[self getConversationActions] indexOfObject:[NSNumber numberWithInt:action]];
    if(NSNotFound != actionRow) {
        actionIndexPath = [NSIndexPath indexPathForRow:actionRow inSection:section];
    }
    return actionIndexPath;
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
    if (_room.isLeavable && _room.type != kNCRoomTypeNoteToSelf) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionLeave]];
    }
    // Clear history
    if ((_room.canModerate || _room.type == kNCRoomTypeNoteToSelf) &&
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityClearHistory]) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionClearHistory]];
    }
    // Delete room
    if (_room.canModerate || _room.type == kNCRoomTypeNoteToSelf) {
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

        case kModificationErrorRoomDescription:
            errorDescription = NSLocalizedString(@"Could not set conversation description", nil);
            break;

        case kModificationErrorBanActor:
            errorDescription = NSLocalizedString(@"Could not ban participant", nil);
            break;

        case kModificationErrorMentionPermissions:
            errorDescription = NSLocalizedString(@"Could not change mention permissions of the conversation", nil);
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
    UIAlertAction *action = [UIAlertAction actionWithTitle:[NCRoom stringForNotificationLevel:level]
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
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[self getIndexPathForConversationAction:kConversationActionMessageExpiration]];

    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (UIAlertAction *)actionForMessageExpiration:(NCMessageExpiration)messageExpiration
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:[NCRoom stringForMessageExpiration:messageExpiration]
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

        weakSelf.setPasswordTextField = textField;
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
            [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:toastText dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
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
            [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"Call notification sent", nil) dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
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
    [[NCUserInterfaceController sharedInstance] presentShareLinkDialogForRoom:_room inViewContoller:self forIndexPath:indexPath];
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

- (void)setMentionPermissions:(NCRoomMentionPermissions)permissions
{
    if (permissions == _room.mentionPermissions) {
        return;
    }

    [self setModifyingRoomUI];

    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] setMentionPermissions:permissions forRoom:_room.token forAccount:activeAccount completionBlock:^(NSError * _Nullable error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token withCompletionBlock:nil];
        } else {
            NSLog(@"Error setting room mention permissions state: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorMentionPermissions];
        }

        self->_mentionPermissionsSwitch.enabled = true;
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

            [NCUtils openFileInNextcloudAppOrBrowserWithPath:filePath withFileLink:fileLink];
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

- (void)presentNameInfoViewController
{
    RoomAvatarInfoTableViewController *vc = [[RoomAvatarInfoTableViewController alloc] initWithRoom:_room];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)presentBannedActorsViewController
{
    BannedActorTableViewController *vc = [[BannedActorTableViewController alloc] initWithRoom:_room];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)clearHistory
{
    [[NCAPIController sharedInstance] clearChatHistoryInRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *messageDict, NSError *error, NSInteger statusCode) {
        if (!error) {
            NSLog(@"Chat history cleared.");
            [[JDStatusBarNotificationPresenter sharedPresenter] presentWithText:NSLocalizedString(@"All messages were deleted", nil) dismissAfterDelay:5.0 includedStyle:JDStatusBarNotificationIncludedStyleSuccess];
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
        [demoteFromModerator setValue:[UIImage systemImageNamed:@"person"] forKey:@"image"];
        [optionsActionSheet addAction:demoteFromModerator];
    } else if (canParticipantBeModerated && participant.canBePromoted) {
        UIAlertAction *promoteToModerator = [UIAlertAction actionWithTitle:NSLocalizedString(@"Promote to moderator", nil)
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self promoteToModerator:participant];
                                                                   }];
        [promoteToModerator setValue:[UIImage systemImageNamed:@"crown"] forKey:@"image"];
        [optionsActionSheet addAction:promoteToModerator];
    }
    
    if (canParticipantBeNotifiedAboutCall) {
        UIAlertAction *sendCallNotification = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send call notification", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self sendCallNotificationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [sendCallNotification setValue:[UIImage systemImageNamed:@"bell"] forKey:@"image"];
        [optionsActionSheet addAction:sendCallNotification];
    }
    
    if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
        UIAlertAction *resendInvitation = [UIAlertAction actionWithTitle:NSLocalizedString(@"Resend invitation", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self resendInvitationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [resendInvitation setValue:[UIImage systemImageNamed:@"envelope"] forKey:@"image"];
        [optionsActionSheet addAction:resendInvitation];
    }
    
    if (canParticipantBeModerated) {
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityBanV1] && !participant.isGroup && !participant.isCircle && !participant.isFederated) {
            NSString *banTitle = NSLocalizedString(@"Ban participant", nil);

            UIAlertAction *banParticipant = [UIAlertAction actionWithTitle:banTitle
                                                                        style:UIAlertActionStyleDestructive
                                                                      handler:^void (UIAlertAction *action) {
                [self banParticipant:participant];
            }];
            [banParticipant setValue:[UIImage systemImageNamed:@"person.badge.minus"] forKey:@"image"];
            [optionsActionSheet addAction:banParticipant];
        }

        // Remove participant
        NSString *title = NSLocalizedString(@"Remove participant", nil);
        if (participant.isGroup) {
            title = NSLocalizedString(@"Remove group and members", nil);
        } else if (participant.isCircle) {
            title = NSLocalizedString(@"Remove team and members", nil);
        }
        UIAlertAction *removeParticipant = [UIAlertAction actionWithTitle:title
                                                                    style:UIAlertActionStyleDestructive
                                                                  handler:^void (UIAlertAction *action) {
                                                                      [self removeParticipant:participant];
                                                                  }];
        [removeParticipant setValue:[UIImage systemImageNamed:@"trash"] forKey:@"image"];
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

- (void)banParticipant:(NCRoomParticipant *)participant
{
    UIAlertController *internalNoteController =
    [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Ban %@", @"e.g. Ban John Doe"), participant.displayName]
                                        message:NSLocalizedString(@"Add an internal note about this ban", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [internalNoteController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = NSLocalizedString(@"Internal note", @"Internal note about why a user/guest was banned");
        textField.delegate = weakSelf;

        weakSelf.banInternalNoteTextField = textField;
    }];

    _banAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ban", @"Ban a user/guest") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *internalNote = [[internalNoteController textFields][0] text];
        NSString *trimmedInternalNote = [internalNote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        [self setModifyingRoomUI];
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

        [[NCAPIController sharedInstance] banActorFor:activeAccount.accountId in:self->_room.token with:participant.actorType with:participant.actorId with:trimmedInternalNote completionBlock:^(BOOL success) {
            if (success) {
                [self removeParticipant:participant];
            } else {
                [self showRoomModificationError:kModificationErrorBanActor];
            }
        }];
    }];

    [internalNoteController addAction:_banAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [internalNoteController addAction:cancelAction];

    [self presentViewController:internalNoteController animated:YES completion:nil];
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
    if (participant.canModerate && (_room.type == kNCRoomTypeOneToOne || _room.type == kNCRoomTypeFormerOneToOne || _room.type == kNCRoomTypeNoteToSelf)) {
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

#pragma mark - Mention permissions switch

- (void)mentionPermissionsValueChanged:(id)sender
{
    _mentionPermissionsSwitch.enabled = NO;
    if (_mentionPermissionsSwitch.on) {
        [self setMentionPermissions:NCRoomMentionPermissionsEveryone];
    } else {
        [self setMentionPermissions:NCRoomMentionPermissionsModeratorsOnly];
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

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Prevent crashing undo bug
    // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
    if (range.length + range.location > textField.text.length) {
        return NO;
    }

    // Set maximum character length
    NSUInteger newLength = [textField.text length] + [string length] - range.length;

    NSUInteger allowedLength = 200;

    if (textField == _banInternalNoteTextField) {
        allowedLength = 4000;
    }

    BOOL hasAllowedLength = newLength <= allowedLength;

    // An internal note on banning is optional, so only enable/disable password confirmation button
    if (hasAllowedLength && textField == _setPasswordTextField) {
        NSString *newValue = [[textField.text stringByReplacingCharactersInRange:range withString:string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        _setPasswordAction.enabled = (newValue.length > 0);
    }

    return hasAllowedLength;
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
    static NSString *bannedActorsCellIdentifier = @"BannedActorsCellIdentifier";
    static NSString *listableCellIdentifier = @"ListableCellIdentifier";
    static NSString *listableForEveryoneCellIdentifier = @"ListableForEveryoneCellIdentifier";
    static NSString *mentionPermissionsCellIdentifier = @"mentionPermissionsCellIdentifier";
    static NSString *readOnlyStateCellIdentifier = @"ReadOnlyStateCellIdentifier";
    
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kRoomInfoSectionName:
        {
            RoomNameTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RoomNameTableViewCell.identifier];
            if (!cell) {
                cell = [[RoomNameTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RoomNameTableViewCell.identifier];
            }
            
            cell.roomNameTextField.text = _room.name;

            if (_room.type == kNCRoomTypeOneToOne || _room.type == kNCRoomTypeFormerOneToOne || _room.type == kNCRoomTypeChangelog) {
                cell.roomNameTextField.text = _room.displayName;
            }

            [cell.roomImage setAvatarFor:_room];

            if (_room.hasCall) {
                [cell.favoriteImage setTintColor:[UIColor systemRedColor]];
                [cell.favoriteImage setImage:[UIImage systemImageNamed:@"video.fill"]];
            } else if (_room.isFavorite) {
                [cell.favoriteImage setTintColor:[UIColor systemYellowColor]];
                [cell.favoriteImage setImage:[UIImage systemImageNamed:@"star.fill"]];
            }

            cell.roomNameTextField.userInteractionEnabled = NO;

            if (_room.canModerate || _room.type == kNCRoomTypeNoteToSelf) {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.userInteractionEnabled = YES;
            } else {
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.userInteractionEnabled = NO;
            }
            
            return cell;
        }
            break;
        case kRoomInfoSectionDescription:
        {
            TextViewTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:TextViewTableViewCell.identifier];
            if (!cell) {
                cell = [[TextViewTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:TextViewTableViewCell.identifier];
            }
            
            cell.textView.text = _room.roomDescription;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
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
                    cell.textLabel.numberOfLines = 0;
                    cell.detailTextLabel.text = _room.notificationLevelString;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"bell"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _callNotificationSwitch;
                    _callNotificationSwitch.on = _room.notificationCalls;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"phone"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"eye"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    
                    UIImage *nextcloudActionImage = [[UIImage imageNamed:@"logo-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [cell.imageView setImage:nextcloudActionImage];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                                        
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
            cell.textLabel.numberOfLines = 0;
            [cell.imageView setImage:[UIImage systemImageNamed:@"photo.on.rectangle.angled"]];
            cell.imageView.tintColor = [UIColor secondaryLabelColor];
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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _publicSwitch;
                    _publicSwitch.on = (_room.type == kNCRoomTypePublic) ? YES : NO;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"link"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    [cell.imageView setImage:(_room.hasPassword) ? [UIImage systemImageNamed:@"lock"] : [UIImage systemImageNamed:@"lock.open"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    
                    [cell.imageView setImage:[UIImage systemImageNamed:@"envelope"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.detailTextLabel.text = _room.messageExpirationString;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"timer"]];
                     cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
                    return cell;
                }
                    break;
                case kConversationActionBannedActors:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:bannedActorsCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:bannedActorsCellIdentifier];
                    }

                    cell.textLabel.text = NSLocalizedString(@"Banned users and guests", nil);
                    cell.textLabel.numberOfLines = 0;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"person.badge.minus"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _listableSwitch;
                    _listableSwitch.on = (_room.listable != NCRoomListableScopeParticipantsOnly);
                    [cell.imageView setImage:[UIImage systemImageNamed:@"list.bullet"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _listableForEveryoneSwitch;
                    _listableForEveryoneSwitch.on = (_room.listable == NCRoomListableScopeEveryone);
                    
                    // Still assign an image, but hide it to keep the margin the same as the other cells
                    [cell.imageView setImage:[UIImage systemImageNamed:@"list.bullet"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    [cell.imageView setHidden:YES];

                    return cell;
                }
                    break;
                case kConversationActionMentionPermission:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:mentionPermissionsCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:mentionPermissionsCellIdentifier];
                    }

                    cell.textLabel.text = NSLocalizedString(@"Allow participants to mention @all", @"'@all' should not be translated");
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _mentionPermissionsSwitch;
                    _mentionPermissionsSwitch.on = (_room.mentionPermissions == NCRoomMentionPermissionsEveryone);
                    [cell.imageView setImage:[UIImage systemImageNamed:@"at.circle"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];

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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _readOnlySwitch;
                    _readOnlySwitch.on = _room.readOnlyState;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"lock.square"]];
                     cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"square.and.arrow.up"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];

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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbySwitch;
                    _lobbySwitch.on = (_room.lobbyState == NCRoomLobbyStateModeratorsOnly) ? YES : NO;
                    [cell.imageView setImage:[[UIImage imageNamed:@"lobby"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.textLabel.adjustsFontSizeToFitWidth = YES;
                    cell.textLabel.minimumScaleFactor = 0.6;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbyDateTextField;
                    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
                    _lobbyDateTextField.text = _room.lobbyTimer > 0 ? [NCUtils readableDateTimeFromDate:date] : nil;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"calendar.badge.clock"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _sipSwitch;
                    _sipSwitch.on = _room.sipState > NCRoomSIPStateDisabled;
                    [cell.imageView setImage:[UIImage systemImageNamed:@"phone"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    
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
                    cell.textLabel.numberOfLines = 0;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _sipNoPINSwitch;
                    _sipNoPINSwitch.on = _room.sipState > NCRoomSIPStateEnabled;
                    
                    // Still assign an image, but hide it to keep the margin the same as the other cells
                    [cell.imageView setImage:[UIImage systemImageNamed:@"phone"]];
                    cell.imageView.tintColor = [UIColor secondaryLabelColor];
                    [cell.imageView setHidden:YES];
                    
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
                    TextViewTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:TextViewTableViewCell.identifier];
                    if (!cell) {
                        cell = [[TextViewTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:TextViewTableViewCell.identifier];
                    }
                    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
                    SignalingSettings *activeAccountSignalingConfig = [[[NCSettingsController sharedInstance] signalingConfigurations] objectForKey:activeAccount.accountId];

                    if (activeAccountSignalingConfig.sipDialinInfo) {
                        cell.textView.text = activeAccountSignalingConfig.sipDialinInfo;
                    } else {
                        cell.textView.text = @"";
                    }

                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    return cell;
                }
                    break;
                case kSIPActionMeetingId:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipMeetingIDCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sipMeetingIDCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Meeting ID", nil);
                    cell.textLabel.numberOfLines = 0;
                    UILabel *valueLabel = [UILabel new];
                    valueLabel.text = _room.token;
                    valueLabel.textColor = [UIColor secondaryLabelColor];
                    [valueLabel sizeToFit];
                    cell.accessoryView = valueLabel;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    
                    return cell;
                }
                    break;
                case kSIPActionPIN:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sipUserPINCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sipUserPINCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Your PIN", nil);
                    cell.textLabel.numberOfLines = 0;
                    UILabel *valueLabel = [UILabel new];
                    valueLabel.text = _room.attendeePin;
                    valueLabel.textColor = [UIColor secondaryLabelColor];
                    [valueLabel sizeToFit];
                    cell.accessoryView = valueLabel;
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
            [cell.contactImage setActorAvatarForId:participant.actorId withType:participant.actorType withDisplayName:participant.displayName withRoomToken:self.room.token];

            // User status
            [cell setUserStatus:participant.status];
            
            // User status message
            [cell setUserStatusMessage:participant.statusMessage withIcon:participant.statusIcon];
            
            if (!participant.statusMessage || [participant.statusMessage isEqualToString:@""]) {
                if ([participant.status isEqualToString: kUserStatusDND]) {
                    [cell setUserStatusMessage:NSLocalizedString(@"Do not disturb", nil) withIcon:nil];
                } else if ([participant.status isEqualToString:kUserStatusAway]) {
                    [cell setUserStatusMessage: NSLocalizedString(@"Away", nil) withIcon:nil];
                }
            }

            // Federated users
            if (participant.isFederated) {
                UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithPointSize:14];
                UIImage *publicRoomImage = [UIImage systemImageNamed:@"globe"];
                publicRoomImage = [publicRoomImage imageWithTintColor:[UIColor labelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
                publicRoomImage = [publicRoomImage imageByApplyingSymbolConfiguration:conf];
                [cell setUserStatusIconWithImage:publicRoomImage];
            }

            // Online status
            if (participant.isOffline) {
                cell.contactImage.alpha = 0.5;
                cell.labelTitle.alpha = 0.5;
                cell.userStatusMessageLabel.alpha = 0.5;
                cell.userStatusImageView.alpha = 0.5;
            } else {
                cell.contactImage.alpha = 1;
                cell.labelTitle.alpha = 1;
                cell.userStatusMessageLabel.alpha = 1;
                cell.userStatusImageView.alpha = 1;
            }

            // Call status
            if (participant.callIconImageName) {
                cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:participant.callIconImageName]];
                [cell.accessoryView setTintColor:[UIColor secondaryLabelColor]];
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
                    cell.textLabel.numberOfLines = 0;
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[UIImage systemImageNamed:@"arrow.right.square"]];
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
                    cell.textLabel.numberOfLines = 0;
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    if (@available(iOS 16.0, *)) {
                        [cell.imageView setImage:[UIImage systemImageNamed:@"eraser"]];
                    } else {
                        [cell.imageView setImage:[UIImage systemImageNamed:@"trash"]];
                    }
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
                    cell.textLabel.numberOfLines = 0;
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[UIImage systemImageNamed:@"trash"]];
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
        case kRoomInfoSectionDescription:
        {
            if (_room.canModerate || _room.type == kNCRoomTypeNoteToSelf) {
                [self presentNameInfoViewController];
            }
        }
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
                case kConversationActionBannedActors:
                    [self presentBannedActorsViewController];
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
