/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCRoomsManager.h"

#import <Realm/Realm.h>

#import "AppDelegate.h"
#import "CallKitManager.h"
#import "NCChatBlock.h"
#import "NCChatController.h"
#import "NCChatMessage.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NotificationCenterNotifications.h"

#import "NextcloudTalk-Swift.h"


static NSInteger kNotJoiningAnymoreStatusCode = 999;

@interface NCRoomsManager () <CallViewControllerDelegate>



@end

@implementation NCRoomController

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[AllocationTracker shared] addAllocation:@"NCRoomController"];
    }
    return self;
}

- (void)dealloc
{
    [[AllocationTracker shared] removeAllocation:@"NCRoomController"];
}

@end

@implementation NCRoomsManager

+ (NCRoomsManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCRoomsManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _activeRooms = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatWithLocalNotification:) name:NCLocalNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChat:) name:NCPushNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectedUserForChat:) name:NCSelectedUserForChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceptCallForRoom:) name:CallKitManagerDidAnswerCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startCallForRoom:) name:CallKitManagerDidStartCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkForCallUpgrades:) name:CallKitManagerDidEndCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChat:) name:NSNotification.NCChatViewControllerReplyPrivatelyNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatOfForwardedMessage:) name:NSNotification.NCChatViewControllerForwardNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChat:) name:NSNotification.NCChatViewControllerTalkToUserNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChatWithURL:) name:NCURLWantsToOpenConversationNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatHighlightingMessage:) name:NCPresentChatHighlightingMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NSNotification.NCConnectionStateHasChangedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



#pragma mark - Call

- (void)startCall:(BOOL)video inRoom:(NCRoom *)room withVideoEnabled:(BOOL)enabled asInitiator:(BOOL)initiator silently:(BOOL)silently recordingConsent:(BOOL)recordingConsent andVoiceChatMode:(BOOL)voiceChatMode
{
    if (!_callViewController) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        _callViewController = [[CallViewController alloc] initFor:room asUser:activeAccount.userDisplayName audioOnly:!video];
        _callViewController.videoDisabledAtStart = !enabled;
        _callViewController.voiceChatModeAtStart = voiceChatMode;
        _callViewController.initiator = initiator;
        _callViewController.silentCall = silently;
        _callViewController.recordingConsent = recordingConsent;
        [_callViewController setModalTransitionStyle:UIModalTransitionStyleCrossDissolve];
        _callViewController.delegate = self;

        NSString *chatViewControllerRoomToken = _chatViewController.room.token;
        NSString *joiningRoomToken = room.token;

        // Workaround until external signaling supports multi-room
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if (extSignalingController) {
            NSString *extSignalingRoomToken = extSignalingController.currentRoom;

            if (![extSignalingRoomToken isEqualToString:joiningRoomToken]) {
                // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                // is no longer the room we want to leave (so no message is sent to the external signaling server).
                extSignalingController.currentRoom = nil;
            }
        }

        // Make sure the external signaling contoller is connected.
        // Could be that the call has been received while the app was inactive or in the background,
        // so the external signaling controller might be disconnected at this point.
        if ([extSignalingController disconnected]) {
            [extSignalingController forceConnect];
        }

        if (_chatViewController) {
            if ([chatViewControllerRoomToken isEqualToString:joiningRoomToken]) {
                // We're in the chat of the room we want to start a call, so stop chat for now
                [_chatViewController stopChat];
            } else {
                // We're in a different chat, so make sure we leave the chat and go back to the conversation list
                [_chatViewController leaveChat];
                [[NCUserInterfaceController sharedInstance] presentConversationsList];
            }
        }

        [[NCUserInterfaceController sharedInstance] presentCallViewController:_callViewController withCompletionBlock:^{
            [self joinRoom:room.token forCall:YES];
        }];
    } else {
        NSLog(@"Not starting call due to in another call.");
    }
}

- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video asInitiator:(BOOL)initiator recordingConsent:(BOOL)recordingConsent
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token completionBlock:^(NSDictionary *roomDict, NSError *error) {
        if (!error) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
            [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName asInitiator:initiator silently:YES recordingConsent:recordingConsent withAccountId:activeAccount.accountId];
        }
    }];
}

- (BOOL)isCallOngoingWithCallToken:(NSString *)token
{
    if (!self.callViewController) {
        return false;
    }

    return [self.callViewController.room.token isEqualToString:token];
}

- (void)startCallWithCallToken:(NSString *)token withVideo:(BOOL)video enabledAtStart:(BOOL)enabled asInitiator:(BOOL)initiator silently:(BOOL)silently recordingConsent:(BOOL)recordingConsent andVoiceChatMode:(BOOL)voiceChatMode
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token completionBlock:^(NSDictionary *roomDict, NSError *error) {
        if (!error) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
            [self startCall:video inRoom:room withVideoEnabled:enabled asInitiator:initiator silently:silently recordingConsent:recordingConsent andVoiceChatMode:voiceChatMode];
        }
    }];
}

- (void)checkForPendingToStartCalls
{
    if (_pendingToStartCallToken) {
        // Pending calls can only happen when answering a new call. That's why we start with video disabled at start and in voice chat mode.
        // We also can start call silently because we are joining an already started call so no need to notify.
        [self startCallWithCallToken:_pendingToStartCallToken withVideo:_pendingToStartCallHasVideo enabledAtStart:NO asInitiator:NO silently:YES recordingConsent:NO andVoiceChatMode:YES];
        _pendingToStartCallToken = nil;
    }
}

- (BOOL)areThereActiveCalls
{
    for (NCRoomController *roomController in [_activeRooms allValues]) {
        if (roomController.inCall) {
            return YES;
        }
    }
    return NO;
}

- (void)upgradeCallToVideoCall:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inCall = NO;
    }
    _upgradeCallToken = room.token;
    [[CallKitManager sharedInstance] endCall:room.token withStatusCode:0];
}

#pragma mark - Switch to

- (void)prepareSwitchToAnotherRoomFromRoom:(NSString *)token withCompletionBlock:(PrepareSwitchRoomCompletionBlock)block
{
    if ([_chatViewController.room.token isEqualToString:token]) {
        [_chatViewController leaveChat];
        [[NCUserInterfaceController sharedInstance] popToConversationsList];
    }
    
    // Remove room controller and exit room
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        [_activeRooms removeObjectForKey:token];
        [[NCAPIController sharedInstance] exitRoom:token forAccount:activeAccount completionBlock:block];
    } else {
        NSLog(@"Couldn't find a room controller from the room we are switching from");
        block(nil);
    }
}

#pragma mark - CallViewControllerDelegate

- (void)callViewControllerWantsToBeDismissed:(CallViewController *)viewController
{
    if (_callViewController == viewController && ![viewController isBeingDismissed]) {
        [viewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)callViewControllerWantsVideoCallUpgrade:(CallViewController *)viewController
{
    NCRoom *room = _callViewController.room;
    if (_callViewController == viewController) {
        _callViewController = nil;
        [self upgradeCallToVideoCall:room];
    }
}

- (void)callViewController:(CallViewController *)viewController wantsToSwitchFromRoom:(NSString *)from toRoom:(NSString *)to
{
    if (_callViewController == viewController) {
        [[CallKitManager sharedInstance] switchCallFrom:from toCall:to];
    }
}

- (void)callViewControllerDidFinish:(CallViewController *)viewController
{
    if (_callViewController == viewController) {
        NCRoom *room = _callViewController.room;
        NSString *token = room.token;

        _callViewController = nil;

        NCRoomController *roomController = [_activeRooms objectForKey:token];
        if (roomController) {
            roomController.inCall = NO;
        }

        [self leaveRoom:token];

        [[CallKitManager sharedInstance] endCall:token withStatusCode:0];

        if ([_chatViewController.room.token isEqualToString:token]) {
            [_chatViewController resumeChat];
        }

        // Keep connection alive temporarily when a call was finished while the app in the background
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
            AppDelegate *appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
            [appDelegate keepExternalSignalingConnectionAliveTemporarily];
        }

        // If this is an event room and we are a moderator, we allow direct deletion
        if ([room canModerate] && [room isEvent]) {
            [self deleteEventRoomWithConfirmationAfterCall:room];
        }
    }
}

#pragma mark - Notifications

- (void)checkForCallUpgrades:(NSNotification *)notification
{
    if (_upgradeCallToken) {
        NSString *token = [_upgradeCallToken copy];
        _upgradeCallToken = nil;
        // Add some delay so CallKit doesn't fail requesting new call
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
            [self joinCallWithCallToken:token withVideo:YES asInitiator:NO recordingConsent:YES];
        });
    }
}

- (void)checkForAccountChange:(NSString *)accountId
{
    // Change account if notification is from another account
    if (accountId && ![[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:accountId]) {
        // Leave chat before changing accounts
        if ([[NCRoomsManager sharedInstance] chatViewController]) {
            [[[NCRoomsManager sharedInstance] chatViewController] leaveChat];
        }
        // Set notification account active
        [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:accountId];
    }
}

- (void)acceptCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    BOOL waitForCallEnd = [[notification.userInfo objectForKey:@"waitForCallEnd"] boolValue];
    BOOL hasVideo = [[notification.userInfo objectForKey:@"hasVideo"] boolValue];
    BOOL activeCalls = [self areThereActiveCalls];
    if (!waitForCallEnd || (!activeCalls && !_leaveRoomTask)) {
        // Calls that have been answered start with video disabled by default, in voice chat mode and silently (without notification).
        [self startCallWithCallToken:roomToken withVideo:hasVideo enabledAtStart:NO asInitiator:NO silently:YES recordingConsent:NO andVoiceChatMode:YES];
    } else {
        _pendingToStartCallToken = roomToken;
        _pendingToStartCallHasVideo = hasVideo;
    }
}

- (void)startCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    BOOL isVideoEnabled = [[notification.userInfo objectForKey:@"isVideoEnabled"] boolValue];
    BOOL initiator = [[notification.userInfo objectForKey:@"initiator"] boolValue];
    BOOL silentCall = [[notification.userInfo objectForKey:@"silentCall"] boolValue];
    BOOL recordingConsent = [[notification.userInfo objectForKey:@"recordingConsent"] boolValue];
    [self startCallWithCallToken:roomToken withVideo:isVideoEnabled enabledAtStart:YES asInitiator:initiator silently:silentCall recordingConsent:recordingConsent andVoiceChatMode:NO];
}

- (void)joinAudioCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:NO asInitiator:NO recordingConsent:NO];
}

- (void)joinVideoCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:YES asInitiator:NO recordingConsent:NO];
}

- (void)joinChat:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    if (pushNotification.threadId > 0) {
        _showThreadPushNotification = pushNotification;
    }
    [self startChatWithRoomToken:pushNotification.roomToken];
}

- (void)joinOrCreateChatWithUser:(NSString *)userId usingAccountId:(NSString *)accountId
{
    NSArray *accountRooms = [[NCDatabaseManager sharedInstance] roomsForAccountId:accountId withRealm:nil];

    for (NCRoom *room in accountRooms) {
        if (room.type == kNCRoomTypeOneToOne && [room.name isEqualToString:userId]) {
            // Room already exists -> join the room
            [self startChatWithRoomToken:room.token];
            
            return;
        }
    }
    
    // Did not find a one-to-one room for this user -> create a new one
    [[NCAPIController sharedInstance] createRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withInvite:userId
                                                    ofType:kNCRoomTypeOneToOne
                                                   andName:nil
                    completionBlock:^(NCRoom *room, NSError *error) {
                        if (!error) {
                            [self startChatWithRoomToken:room.token];
                             NSLog(@"Room %@ with %@ created", room.token, userId);
                         } else {
                             NSLog(@"Failed creating a room with %@", userId);
                         }
                    }];
}

- (void)joinOrCreateChat:(NSNotification *)notification
{
    NSString *actorId = [notification.userInfo objectForKey:@"actorId"];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self joinOrCreateChatWithUser:actorId usingAccountId:activeAccount.accountId];
}

- (void)joinOrCreateChatWithURL:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSString *withUser = [notification.userInfo objectForKey:@"withUser"];
    NSString *roomToken = [notification.userInfo objectForKey:@"withRoomToken"];
    [self checkForAccountChange:accountId];

    if (withUser) {
        [self joinOrCreateChatWithUser:withUser usingAccountId:accountId];
    } else if (roomToken) {
        [self startChatWithRoomToken:roomToken];
    } // else: no chat specified, only change account
}

- (void)joinChatOfForwardedMessage:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSString *token = [notification.userInfo objectForKey:@"token"];
    [self checkForAccountChange:accountId];
    [self startChatWithRoomToken:token];
}

- (void)joinChatWithLocalNotification:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (roomToken) {
        NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
        [self checkForAccountChange:accountId];
        [self startChatWithRoomToken:roomToken];
        
        // In case this notification occurred because of a failed chat-sending event, make sure the text is not lost
        // Note: This will override any stored pending message
        NSString *responseUserText = [notification.userInfo objectForKey:@"responseUserText"];
        if (_chatViewController && responseUserText) {
            [_chatViewController setChatMessage:responseUserText];
        }
    }
}

- (void)joinChatHighlightingMessage:(NSNotification *)notification
{
    _highlightMessageDict = notification.userInfo;
    NSString *token = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:token];
}

- (void)selectedUserForChat:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}

- (void)roomCreated:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];

    // Try to send offline message when the connection state changes to connected again
    if (connectionState == ConnectionStateConnected) {
        [self resendOfflineMessagesWithCompletionBlock:nil];
    }
}

@end
