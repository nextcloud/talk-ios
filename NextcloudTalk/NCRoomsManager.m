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
#import "NCExternalSignalingController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NotificationCenterNotifications.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidUpdateRoomsNotification           = @"NCRoomsManagerDidUpdateRoomsNotification";
NSString * const NCRoomsManagerDidUpdateRoomNotification            = @"NCRoomsManagerDidUpdateRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";

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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Room

- (void)updateRoomsUpdatingUserStatus:(BOOL)updateStatus onlyLastModified:(BOOL)onlyLastModified
{
    [self updateRoomsUpdatingUserStatus:updateStatus onlyLastModified:onlyLastModified withCompletionBlock:nil];
}

- (void)updateRoomsAndChatsUpdatingUserStatus:(BOOL)updateStatus onlyLastModified:(BOOL)onlyLastModified withCompletionBlock:(UpdateRoomsAndChatsCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (onlyLastModified && [activeAccount.lastReceivedModifiedSince integerValue] == 0) {
        if (block) {
            block(nil);
        }
        return;
    }

    [self updateRoomsUpdatingUserStatus:updateStatus onlyLastModified:onlyLastModified withCompletionBlock:^(NSArray *roomsWithNewMessages, TalkAccount *account, NSError *error) {
        if (error) {
            if (block) {
                block(error);
            }
            
            return;
        }
        
        NSLog(@"Finished rooms update with %lu rooms with new messages", [roomsWithNewMessages count]);
        dispatch_group_t chatUpdateGroup = dispatch_group_create();
        
        // When in low power mode, we only update the conversation list and don't load new messages for each room
        if (![NSProcessInfo processInfo].isLowPowerModeEnabled && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatKeepNotifications forAccountId:account.accountId]) {
            for (NCRoom *room in roomsWithNewMessages) {
                dispatch_group_enter(chatUpdateGroup);

                NSLog(@"Updating room %@", room.internalId);
                NCChatController *chatController;

                if (self.chatViewController && self.chatViewController.chatController && [self.chatViewController.room.internalId isEqualToString:room.internalId]) {
                    // If there's already a chatController for this room, don't create a new one
                    chatController = self.chatViewController.chatController;
                } else {
                    chatController = [[NCChatController alloc] initForRoom:room];
                }

                [chatController updateHistoryInBackgroundWithCompletionBlock:^(NSError *error) {
                    NSLog(@"Finished updating room %@", room.internalId);
                    dispatch_group_leave(chatUpdateGroup);
                }];
            }
        }
                
        dispatch_group_notify(chatUpdateGroup, dispatch_get_main_queue(), ^{
            // Notify backgroundFetch that we're finished
            if (block) {
                block(nil);
            }
        });
    }];
}

- (void)updateRoomsUpdatingUserStatus:(BOOL)updateStatus onlyLastModified:(BOOL)onlyLastModified withCompletionBlock:(UpdateRoomsCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSInteger modifiedSince = onlyLastModified ? [activeAccount.lastReceivedModifiedSince integerValue] : 0;
    [[NCAPIController sharedInstance] getRoomsForAccount:activeAccount updateStatus:updateStatus modifiedSince:modifiedSince completionBlock:^(NSArray * _Nullable rooms, NSError * _Nullable error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        NSMutableArray *roomsWithNewMessages = [NSMutableArray new];

        if (!error) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateRoomsTransaction" expirationHandler:^(BGTaskHelper *task) {
                NSString *logMessage = [NSString stringWithFormat:@"ExpirationHandler called NCUpdateRoomsTransaction, number of rooms %ld", rooms.count];
                [NCUtils log:logMessage];
            }];

            RLMRealm *realm = [RLMRealm defaultRealm];
            NSInteger updateTimestamp = [[NSDate date] timeIntervalSince1970];
            [realm transactionWithBlock:^{
                // Add or update rooms
                for (NSDictionary *roomDict in rooms) {
                    BOOL roomContainsNewMessages = [self updateRoomWithDict:roomDict withAccount:activeAccount withTimestamp:updateTimestamp withRealm:realm];

                    if (roomContainsNewMessages) {
                        NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                        [roomsWithNewMessages addObject:room];
                    }
                }
            }];
            // Only delete rooms if it was a complete rooms update (not using modifiedSince)
            if (!onlyLastModified) {
                [realm transactionWithBlock:^{
                    // Delete old rooms
                    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND lastUpdate != %ld", activeAccount.accountId, (long)updateTimestamp];
                    RLMResults *managedRoomsToBeDeleted = [NCRoom objectsWithPredicate:query];
                    // Delete messages and chat blocks from old rooms
                    for (NCRoom *managedRoom in managedRoomsToBeDeleted) {
                        NSPredicate *query2 = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@", activeAccount.accountId, managedRoom.token];
                        [realm deleteObjects:[NCChatMessage objectsWithPredicate:query2]];
                        [realm deleteObjects:[NCChatBlock objectsWithPredicate:query2]];

                        if ([managedRoom isFederated]) {
                            NSPredicate *federatedCapabilities = [NSPredicate predicateWithFormat:@"accountId = %@ AND remoteServer = %@ AND roomToken = %@", activeAccount.accountId, managedRoom.remoteServer, managedRoom.token];
                            [realm deleteObjects:[FederatedCapabilities objectsWithPredicate:federatedCapabilities]];
                        }
                    }
                    [realm deleteObjects:managedRoomsToBeDeleted];
                }];
            }

            [bgTask stopBackgroundTask];
        } else {
            [userInfo setObject:error forKey:@"error"];
            [NCUtils log:[NSString stringWithFormat:@"Could not update rooms. Error: %@", error.description]];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomsNotification
                                                            object:self
                                                          userInfo:userInfo];
        
        if (block) {
            block(roomsWithNewMessages, activeAccount, error);
        }
    }];
}

- (void)updateRoom:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token completionBlock:^(NSDictionary *roomDict, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                [self updateRoomWithDict:roomDict withAccount:activeAccount withTimestamp:[[NSDate date] timeIntervalSince1970] withRealm:realm];
                NSLog(@"Room updated");
            }];
            NCRoom *updatedRoom = [[NCDatabaseManager sharedInstance] roomWithToken:token forAccountId:activeAccount.accountId];

            if (updatedRoom) {
                // It seems to be somehow possible to have the updatedRoom be nil as seen in AppStore crashes
                [userInfo setObject:updatedRoom forKey:@"room"];
            }
        } else {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not update rooms. Error: %@", error.description);
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomNotification
                                                            object:self
                                                          userInfo:userInfo];

        if (block) {
            block(roomDict, error);
        }
    }];
}

- (BOOL)updateRoomWithDict:(NSDictionary *)roomDict withAccount:(TalkAccount *)activeAccount withTimestamp:(NSInteger)timestamp withRealm:(RLMRealm *)realm
{
    BOOL roomContainsNewMessages = NO;
    
    NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
    room.lastUpdate = timestamp;

    NCChatMessage *lastMessage = nil;
    NSDictionary *messageDict = [roomDict objectForKey:@"lastMessage"];
    if (!room.isFederated) {
        // TODO: Move handling to NCRoom roomWithDictionary?
        lastMessage = [NCChatMessage messageWithDictionary:messageDict andAccountId:activeAccount.accountId];
        room.lastMessageId = lastMessage.internalId;
    }
    
    NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
    if (managedRoom) {
        if (room.lastActivity > managedRoom.lastActivity) {
            roomContainsNewMessages = YES;
        }
        
        [NCRoom updateRoom:managedRoom withRoom:room];
    } else if (room) {
        [realm addObject:room];
    }

    if (lastMessage) {
        NCChatMessage *managedLastMessage = [NCChatMessage objectsWhere:@"internalId = %@", lastMessage.internalId].firstObject;
        if (managedLastMessage) {
            [NCChatMessage updateChatMessage:managedLastMessage withChatMessage:lastMessage isRoomLastMessage:YES];
        } else {
            NCChatController *chatController = [[NCChatController alloc] initForRoom:room];
            [chatController storeMessages:@[messageDict] withRealm:realm];
        }
    }
    
    return roomContainsNewMessages;
}

- (void)updatePendingMessage:(NSString *)message forRoom:(NCRoom *)room
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"updatePendingMessage" expirationHandler:nil];
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.pendingMessage = message;
        }
    }];
    [bgTask stopBackgroundTask];
}

- (void)updateLastReadMessage:(NSInteger)lastReadMessage forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.lastReadMessage = lastReadMessage;
        }
    }];
}

- (void)updateLastMessage:(NCChatMessage *)message withNoUnreadMessages:(BOOL)noUnreadMessages forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.lastMessageId = message.internalId;
            managedRoom.lastActivity = message.timestamp;
            
            if (noUnreadMessages) {
                managedRoom.unreadMention = NO;
                managedRoom.unreadMentionDirect = NO;
                managedRoom.unreadMessages = 0;
            }
        }
    }];
}

- (void)updateLastCommonReadMessage:(NSInteger)messageId forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom && messageId > managedRoom.lastCommonReadMessage) {
            managedRoom.lastCommonReadMessage = messageId;
        }
    }];
}

#pragma mark - Chat

- (void)startChatInRoom:(NCRoom *)room
{
    if (_callViewController) {
        NSLog(@"Not starting chat due to in a call.");
        return;
    }

    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (!roomController) {
        // Workaround until external signaling supports multi-room
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if (extSignalingController) {
            NSString *currentRoom = extSignalingController.currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                // is no longer the room we want to leave (so no message is sent to the external signaling server).
                extSignalingController.currentRoom = nil;
            }
        }
    }
    
    if (!_chatViewController || ![_chatViewController.room.token isEqualToString:room.token]) {
        // Leave the previous chat
        //[[NCRoomsManager sharedInstance].chatViewController leaveChat];

        NSLog(@"Creating new chat view controller.");
        _chatViewController = [[ChatViewController alloc] initForRoom:room withAccount:activeAccount];
        if (_highlightMessageDict && [[_highlightMessageDict objectForKey:@"token"] isEqualToString:room.token]) {
            _chatViewController.highlightMessageId = [[_highlightMessageDict objectForKey:@"messageId"] integerValue];
            _highlightMessageDict = nil;
        }
        [[NCUserInterfaceController sharedInstance] presentChatViewController:_chatViewController];
    } else {
        NSLog(@"Not creating new chat room: chatViewController for room %@ does already exist.", room.token);

        // Still make sure the current room is highlighted
        [[NCUserInterfaceController sharedInstance].roomsTableViewController setSelectedRoomToken:_chatViewController.room.token];
    }
}

- (void)startChatWithRoomToken:(NSString *)token
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NCRoom *room = [[NCDatabaseManager sharedInstance] roomWithToken:token forAccountId:activeAccount.accountId];
    if (room) {
        [self startChatInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token completionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                [self startChatInRoom:room];
            }
        }];
    }
}

- (void)leaveChatInRoom:(NSString *)token;
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        roomController.inChat = NO;
    }
    
    [self leaveRoom:token];
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

- (void)leaveCallInRoom:(NSString *)token
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        roomController.inCall = NO;
    }

    [self leaveRoom:token];
}

- (void)callDidEndInRoomWithToken:(NSString *)token
{
    [self leaveCallInRoom:token];

    [[CallKitManager sharedInstance] endCall:token withStatusCode:0];
    
    if ([_chatViewController.room.token isEqualToString:token]) {
        [_chatViewController resumeChat];
    }
}

#pragma mark - Switch to

- (void)prepareSwitchToAnotherRoomFromRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block
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
        [[NCAPIController sharedInstance] exitRoom:token forAccount:activeAccount withCompletionBlock:block];
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

- (void)callViewController:(CallViewController *)viewController wantsToSwitchCallFromCall:(NSString *)from toRoom:(NSString *)to
{
    if (_callViewController == viewController) {
        [[CallKitManager sharedInstance] switchCallFrom:from toCall:to];
    }
}

- (void)callViewControllerDidFinish:(CallViewController *)viewController
{
    if (_callViewController == viewController) {
        NSString *token = [_callViewController.room.token copy];
        _callViewController = nil;
        [self callDidEndInRoomWithToken:token];
        // Keep connection alive temporarily when a call was finished while the app in the background
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
            AppDelegate *appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
            [appDelegate keepExternalSignalingConnectionAliveTemporarily];
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
    if (connectionState == kConnectionStateConnected) {
        [self resendOfflineMessagesWithCompletionBlock:nil];
    }
}

@end
