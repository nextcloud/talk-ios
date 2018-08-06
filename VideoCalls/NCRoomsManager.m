//
//  NCRoomsManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomsManager.h"

#import "NCChatViewController.h"
#import "ContactsTableViewController.h"
#import "RoomCreation2TableViewController.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCRoomController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidUpdateRoomsNotification           = @"NCRoomsManagerDidUpdateRoomsNotification";
NSString * const NCRoomsManagerDidUpdateRoomNotification            = @"NCRoomsManagerDidUpdateRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";

@interface NCRoomsManager () <CallViewControllerDelegate>

@property (nonatomic, strong) NSMutableArray *rooms;
@property (nonatomic, strong) NSMutableDictionary *activeRooms; //roomToken -> roomController


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
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChat:) name:NCPushNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForVoiceCall:) name:NCSelectedContactForVoiceCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForVideoCall:) name:NCSelectedContactForVideoCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForChat:) name:NCSelectedContactForChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Room

- (void)joinRoom:(NCRoom *)room forCall:(BOOL)call
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    if (!roomController) {
        [[NCAPIController sharedInstance] joinRoom:room.token withCompletionBlock:^(NSString *sessionId, NSError *error) {
            if (!error) {
                NCRoomController *controller = [[NCRoomController alloc] initForUser:sessionId inRoom:room.token];
                controller.inChat = !call;
                controller.inCall = call;
                [_activeRooms setObject:controller forKey:room.token];
                [userInfo setObject:controller forKey:@"roomController"];
            } else {
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not join room. Error: %@", error.description);
            }
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

- (void)leaveRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController && !roomController.inCall && !roomController.inChat) {
        [roomController stopRoomController];
        [_activeRooms removeObjectForKey:room.token];
        
        [[NCAPIController sharedInstance] exitRoom:room.token withCompletionBlock:^(NSError *error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            if (error) {
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
        [[NCUserInterfaceController sharedInstance] presentConversationsViewController];
    } else {
        NCChatViewController *chatVC = [[NCChatViewController alloc] initForRoom:room];
        [[NCUserInterfaceController sharedInstance] presentChatViewController:chatVC];
        [self joinRoom:room forCall:NO];
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

- (void)leaveChatInRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inChat = NO;
        [self leaveRoom:room];
    }
}

#pragma mark - Call

- (void)startCall:(BOOL)video inRoom:(NCRoom *)room
{
    if (!_callViewController) {
        _callViewController = [[CallViewController alloc] initCallInRoom:room asUser:[[NCSettingsController sharedInstance] ncUserDisplayName] audioOnly:!video];
        _callViewController.delegate = self;
        [[NCUserInterfaceController sharedInstance] presentCallViewController:_callViewController];
        
        [self joinRoom:room forCall:YES];
    } else {
        NSLog(@"Not starting call due to in another call.");
    }
}

- (void)joinCallWithCallId:(NSInteger)callId withVideo:(BOOL)video
{
    NCRoom *room = [self getRoomForId:callId];
    if (room) {
        [self startCall:video inRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithId:callId withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startCall:video inRoom:room];
            }
        }];
    }
}

- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video
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

- (void)callDidEndInRoom:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inCall = NO;
        [self leaveRoom:room];
    }
}

#pragma mark - CallViewControllerDelegate

- (void)callViewControllerWantsToBeDismissed:(CallViewController *)viewController
{
    if (_callViewController == viewController && ![viewController isBeingDismissed]) {
        [viewController dismissViewControllerAnimated:YES completion:nil];
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

- (void)userSelectedContactForVoiceCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self joinCallWithCallToken:roomToken withVideo:NO];
}

- (void)userSelectedContactForVideoCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self joinCallWithCallToken:roomToken withVideo:YES];
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
