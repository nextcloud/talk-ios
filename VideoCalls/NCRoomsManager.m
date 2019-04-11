//
//  NCRoomsManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomsManager.h"

#import "NCChatViewController.h"
#import "NewRoomTableViewController.h"
#import "RoomCreation2TableViewController.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCExternalSignalingController.h"
#import "NCRoomController.h"
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
@property (nonatomic, strong) NSString *joiningRoom;
@property (nonatomic, strong) NSURLSessionTask *joinRoomTask;


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
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatWithLocalNotification:) name:NCLocalNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChat:) name:NCPushNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForChat:) name:NCSelectedContactForChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceptCallForRoom:) name:CallKitManagerDidAnswerCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startCallForRoom:) name:CallKitManagerDidStartCallNotification object:nil];
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
    if (!roomController) {
        _joiningRoom = token;
        _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token withCompletionBlock:^(NSString *sessionId, NSError *error) {
            if (!error) {
                NCRoomController *controller = [[NCRoomController alloc] initForUser:sessionId inRoom:token];
                controller.inChat = !call;
                controller.inCall = call;
                [_activeRooms setObject:controller forKey:token];
                [userInfo setObject:controller forKey:@"roomController"];
                if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
                    [[NCExternalSignalingController sharedInstance] joinRoom:token withSessionId:sessionId];
                }
            } else {
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not join room. Error: %@", error.description);
            }
            _joiningRoom = nil;
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
    if (roomController) {
        _joiningRoom = [token copy];
        _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token withCompletionBlock:^(NSString *sessionId, NSError *error) {
            if (!error) {
                roomController.userSessionId = sessionId;
                roomController.inChat = YES;
                if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
                    [[NCExternalSignalingController sharedInstance] joinRoom:token withSessionId:sessionId];
                }
            } else {
                NSLog(@"Could not re-join room. Error: %@", error.description);
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
    
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController && !roomController.inCall && !roomController.inChat) {
        [roomController stopRoomController];
        [_activeRooms removeObjectForKey:token];
        
        [[NCAPIController sharedInstance] exitRoom:token withCompletionBlock:^(NSError *error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            if (!error) {
                if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
                    [[NCExternalSignalingController sharedInstance] leaveRoom:token];
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

- (void)updateRooms
{
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger statusCode) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            self.rooms = rooms;
            [userInfo setObject:rooms forKey:@"rooms"];
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
    [[NCAPIController sharedInstance] getRoomWithToken:token withCompletionBlock:^(NCRoom *room, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            [userInfo setObject:room forKey:@"room"];
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

- (NCRoom *)getRoomForId:(NSInteger)roomId
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.roomId == roomId) {
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
    if (roomController && roomController.inChat) {
        // User is already in that room
        return;
    } else {
        // Workaround until external signaling supports multi-room
        if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
            NSString *currentRoom = [NCExternalSignalingController sharedInstance].currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                [NCExternalSignalingController sharedInstance].currentRoom = nil;
            }
        }
        NCChatViewController *chatVC = [[NCChatViewController alloc] initForRoom:room];
        [[NCUserInterfaceController sharedInstance] presentChatViewController:chatVC];
        [self joinRoom:room.token forCall:NO];
    }
}

- (void)startChatWithRoomId:(NSInteger)callId
{
    NCRoom *room = [self getRoomForId:callId];
    if (room) {
        [self startChatInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithId:callId withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startChatInRoom:room];
            }
        }];
    }
}

- (void)startChatWithRoomToken:(NSString *)token
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [self startChatInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithToken:token withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startChatInRoom:room];
            }
        }];
    }
}

- (void)sendChatMessage:(NSString *)message toRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        [roomController sendChatMessage:message];
    } else {
        NSLog(@"Trying to send a message to a room where you are not active.");
    }
}

- (void)startReceivingChatMessagesInRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        [roomController startReceivingChatMessages];
    } else {
        NSLog(@"Trying to start receiving message from a room where you are not active.");
    }
}
- (void)stopReceivingChatMessagesInRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        [roomController stopReceivingChatMessages];
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
        _callViewController = [[CallViewController alloc] initCallInRoom:room asUser:[[NCSettingsController sharedInstance] ncUserDisplayName] audioOnly:!video];
        [_callViewController setModalTransitionStyle:UIModalTransitionStyleCrossDissolve];
        _callViewController.delegate = self;
        // Workaround until external signaling supports multi-room
        if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
            NSString *currentRoom = [NCExternalSignalingController sharedInstance].currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                [[NCUserInterfaceController sharedInstance] presentConversationsList];
                if (currentRoom) {
                    [self leaveChatInRoom:currentRoom];
                }
                [NCExternalSignalingController sharedInstance].currentRoom = nil;
            }
        }
        [[NCUserInterfaceController sharedInstance] presentCallViewController:_callViewController];
        [self joinRoom:room.token forCall:YES];
    } else {
        NSLog(@"Not starting call due to in another call.");
    }
}

- (void)joinCallWithCallId:(NSInteger)callId withVideo:(BOOL)video
{
    NCRoom *room = [self getRoomForId:callId];
    if (room) {
        [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithId:callId withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName];
            }
        }];
    }
}

- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithToken:token withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
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
        [[NCAPIController sharedInstance] getRoomWithToken:token withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
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
    [[CallKitManager sharedInstance] endCurrentCall];
    [self joinCallWithCallToken:room.token withVideo:YES];
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
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityNoPing]) {
        [self joinCallWithCallToken:pushNotification.roomToken withVideo:NO];
    } else {
        [self joinCallWithCallId:pushNotification.roomId withVideo:NO];
    }
}

- (void)joinVideoCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityNoPing]) {
        [self joinCallWithCallToken:pushNotification.roomToken withVideo:YES];
    } else {
        [self joinCallWithCallId:pushNotification.roomId withVideo:YES];
    }
}

- (void)joinChat:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityNoPing]) {
        [self startChatWithRoomToken:pushNotification.roomToken];
    } else {
        [self startChatWithRoomId:pushNotification.roomId];
    }
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
