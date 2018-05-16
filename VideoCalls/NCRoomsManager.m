//
//  NCRoomsManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomsManager.h"

#import "CallViewController.h"
#import "NCAPIController.h"
#import "NCChatMessage.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";

@interface NCRoomsManager ()

@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, assign) NSInteger lastMessageId;
@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) NSURLSessionTask *pingRoomTask;
@property (nonatomic, strong) NSURLSessionTask *pullMessagesTask;

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
        _currentRoom = nil;
    }
    
    return self;
}

- (void)joinRoom:(NCRoom *)room
{
    _currentRoom = room;
    _lastMessageId = -1;
    [[NCAPIController sharedInstance] joinRoom:room.token withCompletionBlock:^(NSString *sessionId, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            self.userSessionId = sessionId;
            [self startPingRoom];
            [self startReceivingChatMessages];
        } else {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not join room. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidJoinRoomNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}

- (void)leaveRoom:(NCRoom *)room
{
    [self stopPingRoom];
    [self stopReceivingChatMessages];
    
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

#pragma mark - Ping call

- (void)pingRoom
{
    _pingRoomTask = [[NCAPIController sharedInstance] pingCall:_currentRoom.token withCompletionBlock:^(NSError *error) {
        //TODO: Error handling
    }];
}

- (void)startPingRoom
{
    [self pingRoom];
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:5.0  target:self selector:@selector(pingRoom) userInfo:nil repeats:YES];
}

- (void)stopPingRoom
{
    [_pingRoomTask cancel];
    [_pingTimer invalidate];
    _pingTimer = nil;
}

#pragma mark - Chat

- (void)startReceivingChatMessages
{
    _stopChatMessagesPoll = NO;
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_currentRoom.token fromLastMessageId:_lastMessageId history:NO withCompletionBlock:^(NSMutableArray *messages, NSError *error) {
        if (_stopChatMessagesPoll) {
            return;
        }
        if (messages.count > 0) {
            NCChatMessage *lastMessage = messages.lastObject;
            _lastMessageId = lastMessage.messageId;
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:messages forKey:@"messages"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidReceiveChatMessagesNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
        [self startReceivingChatMessages];
    }];
}

- (void)stopReceivingChatMessages
{
    _stopChatMessagesPoll = YES;
    [_pullMessagesTask cancel];
}

- (void)sendChatMessage:(NSString *)message toRoom:(NCRoom *)room
{
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:room.token displayName:nil withCompletionBlock:^(NSError *error) {
        //TODO: Error handling
    }];
}

- (void)startCall:(BOOL)video inRoom:(NCRoom *)room
{
    CallViewController *callVC = [[CallViewController alloc] initCallInRoom:room asUser:[[NCSettingsController sharedInstance] ncUserDisplayName] audioOnly:!video withSessionId:_userSessionId];
    [[NCUserInterfaceController sharedInstance] presentCallViewController:callVC];
}

@end
