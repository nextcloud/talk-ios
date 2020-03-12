//
//  NCRoomsManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomsManager.h"

#import <Realm/Realm.h>

#import "NCChatViewController.h"
#import "NewRoomTableViewController.h"
#import "RoomCreation2TableViewController.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCChatMessage.h"
#import "NCExternalSignalingController.h"
#import "NCChatController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "CallKitManager.h"

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidUpdateRoomsNotification           = @"NCRoomsManagerDidUpdateRoomsNotification";
NSString * const NCRoomsManagerDidUpdateRoomNotification            = @"NCRoomsManagerDidUpdateRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";

@interface NCRoomsManager () <CallViewControllerDelegate>

@property (nonatomic, strong) NSMutableArray *rooms;
@property (nonatomic, strong) NSMutableDictionary *activeRooms; //roomToken -> roomController
@property (nonatomic, strong) NSMutableDictionary *chatControllers; //roomInternalId -> chatController
@property (nonatomic, strong) NSString *joiningRoom;
@property (nonatomic, strong) NSURLSessionTask *joinRoomTask;
@property (nonatomic, strong) NSMutableDictionary *joinRoomAttempts; //roomToken -> attempts
@property (nonatomic, strong) NSString *upgradeCallToken;


@end

@implementation NCRoomController
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
        _rooms = [[NSMutableArray alloc] init];
        _activeRooms = [[NSMutableDictionary alloc] init];
        _chatControllers = [[NSMutableDictionary alloc] init];
        _joinRoomAttempts = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatWithLocalNotification:) name:NCLocalNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChat:) name:NCPushNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForChat:) name:NCSelectedContactForChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceptCallForRoom:) name:CallKitManagerDidAnswerCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startCallForRoom:) name:CallKitManagerDidStartCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkForCallUpgrades:) name:CallKitManagerDidEndCallNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Room

- (void)joinRoom:(NSString *)token forCall:(BOOL)call
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (!roomController) {
        _joiningRoom = token;
        _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token forAccount:activeAccount withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger statusCode) {
            if (!_joiningRoom) {
                NSLog(@"Not joining the room any more. Ignore response.");
                return;
            }
            if (!error) {
                NCRoomController *controller = [[NCRoomController alloc] init];
                controller.inChat = !call;
                controller.inCall = call;
                [_activeRooms setObject:controller forKey:token];
                [_joinRoomAttempts removeObjectForKey:token];
                [userInfo setObject:controller forKey:@"roomController"];
                NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
                if ([extSignalingController isEnabled]) {
                    [extSignalingController joinRoom:token withSessionId:sessionId];
                }
            } else {
                NSInteger joinAttempts = [[_joinRoomAttempts objectForKey:token] integerValue];
                if (joinAttempts < 3) {
                    NSLog(@"Error joining room, retrying. %ld", (long)joinAttempts);
                    joinAttempts += 1;
                    [_joinRoomAttempts setObject:@(joinAttempts) forKey:token];
                    [self joinRoom:token forCall:call];
                    return;
                }
                [userInfo setObject:error forKey:@"error"];
                [userInfo setObject:@(statusCode) forKey:@"statusCode"];
                NSLog(@"Could not join room. Status code: %ld. Error: %@", (long)statusCode, error.description);
            }
            _joiningRoom = nil;
            [userInfo setObject:token forKey:@"token"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidJoinRoomNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    } else {
        if (call) {
            roomController.inCall = YES;
        } else {
            roomController.inChat = YES;
        }
        [userInfo setObject:token forKey:@"token"];
        [userInfo setObject:roomController forKey:@"roomController"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidJoinRoomNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
}

- (void)joinRoom:(NSString *)token
{
    [self joinRoom:token forCall:NO];
}

- (void)rejoinRoom:(NSString *)token
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (roomController) {
        _joiningRoom = [token copy];
        _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token forAccount:activeAccount withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger statusCode) {
            if (!error) {
                roomController.userSessionId = sessionId;
                roomController.inChat = YES;
                NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
                if ([extSignalingController isEnabled]) {
                    [extSignalingController joinRoom:token withSessionId:sessionId];
                }
            } else {
                NSLog(@"Could not re-join room. Status code: %ld. Error: %@", (long)statusCode, error.description);
            }
            _joiningRoom = nil;
        }];
    }
}

- (void)leaveRoom:(NSString *)token
{
    // Check if leaving the room we are joining
    if ([_joiningRoom isEqualToString:token]) {
        _joiningRoom = nil;
        [_joinRoomTask cancel];
    }
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    // Stop and remove chat controller
    NCRoom *room = [self roomWithToken:token forAccountId:activeAccount.accountId];
    NCChatController *chatController = [_chatControllers objectForKey:room.internalId];
    [chatController stopChatController];
    [_chatControllers removeObjectForKey:room.internalId];
    // Remove room controller and exit room
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController && !roomController.inCall && !roomController.inChat) {
        [_activeRooms removeObjectForKey:token];
        [[NCAPIController sharedInstance] exitRoom:token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            if (!error) {
                NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
                if ([extSignalingController isEnabled]) {
                    [extSignalingController leaveRoom:token];
                }
            } else {
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not exit room. Error: %@", error.description);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidLeaveRoomNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    }
}

- (NSArray *)roomsForAccountId:(NSString *)accountId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    RLMResults *managedRooms = [NCRoom objectsWithPredicate:query];
    // Create an unmanaged copy of the rooms
    NSMutableArray *unmanagedRooms = [NSMutableArray new];
    for (NCRoom *managedRoom in managedRooms) {
        NCRoom *unmanagedRoom = [[NCRoom alloc] initWithValue:managedRoom];
        [unmanagedRooms addObject:unmanagedRoom];
    }
    // Sort by favorites
    NSSortDescriptor *favoriteSorting = [NSSortDescriptor sortDescriptorWithKey:@"" ascending:YES comparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NCRoom *first = (NCRoom*)obj1;
        NCRoom *second = (NCRoom*)obj2;
        BOOL favorite1 = first.isFavorite;
        BOOL favorite2 = second.isFavorite;
        if (favorite1 != favorite2) {
            return favorite2 - favorite1;
        }
        return NSOrderedSame;
    }];
    // Sort by lastActivity
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastActivity" ascending:NO];
    NSArray *descriptors = [NSArray arrayWithObjects:favoriteSorting, valueDescriptor, nil];
    [unmanagedRooms sortUsingDescriptors:descriptors];
    
    return unmanagedRooms;
}

- (NCChatController *)chatContollerForRoom:(NCRoom *)room
{
    NCChatController *chatController = [_chatControllers objectForKey:room.internalId];
    if (!chatController) {
        chatController = [[NCChatController alloc] initForRoom:room];
        [_chatControllers setObject:chatController forKey:room.internalId];
    }
    return chatController;
}

- (NCRoom *)roomWithToken:(NSString *)token forAccountId:(NSString *)accountId
{
    NCRoom *unmanagedRoom = nil;
    NSPredicate *query = [NSPredicate predicateWithFormat:@"token = %@ AND accountId = %@", token, accountId];
    NCRoom *managedRoom = [NCRoom objectsWithPredicate:query].firstObject;
    if (managedRoom) {
        unmanagedRoom = [[NCRoom alloc] initWithValue:managedRoom];
    }
    return unmanagedRoom;
}

- (void)updateRooms
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomsForAccount:activeAccount withCompletionBlock:^(NSArray *rooms, NSError *error, NSInteger statusCode) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                // Add or update rooms
                NSInteger updateTimestamp = [[NSDate date] timeIntervalSince1970];
                for (NSDictionary *roomDict in rooms) {
                    NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                    NCChatMessage *lastMessage = [NCChatMessage messageWithDictionary:[roomDict objectForKey:@"lastMessage"] andAccountId:activeAccount.accountId];
                    room.lastUpdate = updateTimestamp;
                    room.lastMessageId = lastMessage.internalId;
                    
                    NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
                    if (managedRoom) {
                        [NCRoom updateRoom:managedRoom withRoom:room];
                    } else if (room) {
                        [realm addObject:room];
                    }
                    
                    NCChatMessage *managedLastMessage = [NCChatMessage objectsWhere:@"internalId = %@", lastMessage.internalId].firstObject;
                    if (managedLastMessage) {
                        [NCChatMessage updateChatMessage:managedLastMessage withChatMessage:lastMessage];
                    } else if (lastMessage) {
                        [realm addObject:lastMessage];
                    }
                }
                // Delete old rooms
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND lastUpdate != %ld", activeAccount.accountId, (long)updateTimestamp];
                [realm deleteObjects:[NCRoom objectsWithPredicate:query]];
                NSLog(@"Rooms updated");
            }];
        } else {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not update rooms. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomsNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}

- (void)updateRoom:(NSString *)token
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            [userInfo setObject:[NCRoom roomWithDictionary:roomDict] forKey:@"room"];
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                NCChatMessage *lastMessage = [NCChatMessage messageWithDictionary:[roomDict objectForKey:@"lastMessage"] andAccountId:activeAccount.accountId];
                room.lastUpdate = [[NSDate date] timeIntervalSince1970];
                room.lastMessageId = lastMessage.internalId;
                
                NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
                if (managedRoom) {
                    [NCRoom updateRoom:managedRoom withRoom:room];
                } else if (room) {
                    [realm addObject:room];
                }
                
                NCChatMessage *managedLastMessage = [NCChatMessage objectsWhere:@"internalId = %@", lastMessage.internalId].firstObject;
                if (managedLastMessage) {
                    [NCChatMessage updateChatMessage:managedLastMessage withChatMessage:lastMessage];
                } else if (lastMessage) {
                    [realm addObject:lastMessage];
                }
                NSLog(@"Room updated");
            }];
        } else {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not update rooms. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}

- (NCRoom *)getRoomForToken:(NSString *)token
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.token == token) {
            room = localRoom;
        }
    }
    return room;
}

#pragma mark - Chat

- (void)startChatInRoom:(NCRoom *)room
{
    if (_callViewController) {
        NSLog(@"Not starting chat due to in a call.");
        return;
    }
    
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (!roomController) {
        // Workaround until external signaling supports multi-room
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if ([extSignalingController isEnabled]) {
            NSString *currentRoom = extSignalingController.currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                extSignalingController.currentRoom = nil;
            }
        }
    }
    
    if (!_chatViewController || ![_chatViewController.room.token isEqualToString:room.token]) {
        _chatViewController = [[NCChatViewController alloc] initForRoom:room];
        [[NCUserInterfaceController sharedInstance] presentChatViewController:_chatViewController];
    }
}

- (void)startChatWithRoomToken:(NSString *)token
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [self startChatInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict];
                [self startChatInRoom:room];
            }
        }];
    }
}

- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo toRoom:(NCRoom *)room
{
    NCChatController *chatController = [_chatControllers objectForKey:room.internalId];
    if (chatController) {
        [chatController sendChatMessage:message replyTo:replyTo];
    } else {
        NSLog(@"Trying to send a message to a room where you are not active.");
    }
}

- (void)stopReceivingChatMessagesInRoom:(NCRoom *)room
{
    NCChatController *chatController = [_chatControllers objectForKey:room.internalId];
    if (chatController) {
        [chatController stopReceivingNewChatMessages];
    } else {
        NSLog(@"Trying to stop receiving message from a room where you are not active.");
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

- (void)startCall:(BOOL)video inRoom:(NCRoom *)room
{
    if (!_callViewController) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        _callViewController = [[CallViewController alloc] initCallInRoom:room asUser:activeAccount.userDisplayName audioOnly:!video];
        [_callViewController setModalTransitionStyle:UIModalTransitionStyleCrossDissolve];
        _callViewController.delegate = self;
        // Workaround until external signaling supports multi-room
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if ([extSignalingController isEnabled]) {
            NSString *currentRoom = extSignalingController.currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                [[NCUserInterfaceController sharedInstance] presentConversationsList];
                if (currentRoom) {
                    [self leaveChatInRoom:currentRoom];
                }
                extSignalingController.currentRoom = nil;
            }
        }
        [[NCUserInterfaceController sharedInstance] presentCallViewController:_callViewController];
        [self joinRoom:room.token forCall:YES];
    } else {
        NSLog(@"Not starting call due to in another call.");
    }
}

- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict];
                [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName];
            }
        }];
    }
}

- (void)startCallWithCallToken:(NSString *)token withVideo:(BOOL)video
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [self startCall:video inRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict];
                [self startCall:video inRoom:room];
            }
        }];
    }
}

- (void)upgradeCallToVideoCall:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inCall = NO;
    }
    _upgradeCallToken = room.token;
    [[CallKitManager sharedInstance] endCurrentCall];
}

- (void)callDidEndInRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inCall = NO;
    }
    [[CallKitManager sharedInstance] endCurrentCall];
    [self leaveRoom:room.token];
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

- (void)callViewControllerDidFinish:(CallViewController *)viewController
{
    if (_callViewController == viewController) {
        [self callDidEndInRoom:_callViewController.room];
        _callViewController = nil;
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
            [self joinCallWithCallToken:token withVideo:YES];
        });
    }
}

- (void)acceptCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    [self startCallWithCallToken:roomToken withVideo:NO];
}

- (void)startCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    BOOL isVideoEnabled = [[notification.userInfo objectForKey:@"isVideoEnabled"] boolValue];
    [self startCallWithCallToken:roomToken withVideo:isVideoEnabled];
}

- (void)joinAudioCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:NO];
}

- (void)joinVideoCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:YES];
}

- (void)joinChat:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self startChatWithRoomToken:pushNotification.roomToken];
}

- (void)joinChatWithLocalNotification:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (roomToken) {
        [self startChatWithRoomToken:roomToken];
    }
}

- (void)userSelectedContactForChat:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}

- (void)roomCreated:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}


@end
