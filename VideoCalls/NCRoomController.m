//
//  NCRoomController.m
//  VideoCalls
//
//  Created by Ivan Sein on 25.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomController.h"

#import "NCAPIController.h"
#import "NCChatMessage.h"

@interface NCRoomController ()

@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, assign) NSInteger lastMessageId;
@property (nonatomic, assign) BOOL stopChatMessagesPoll;

@end

@implementation NCRoomController

- (instancetype)initWithDelegate:(id<NCRoomControllerDelegate>)delegate inRoom:(NCRoom *)room;
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _room = room;
        _lastMessageId = -1;
    }
    return self;
}

- (void)joinRoomWithCompletionBlock:(RoomControllerCompletionBlock)block
{
    [[NCAPIController sharedInstance] joinRoom:_room.token withCompletionBlock:^(NSString *sessionId, NSError *error) {
        if (!error) {
            self.userSessionId = sessionId;
            [self startPingRoom];
            [self startReceivingChatMessages];
        } else {
            NSLog(@"Could not join room. Error: %@", error.description);
        }
        
        if (block) block(error);
    }];
}

- (void)leaveRoomWithCompletionBlock:(RoomControllerCompletionBlock)block
{
    [self stopPingRoom];
    [self stopReceivingChatMessages];
    
    [[NCAPIController sharedInstance] exitRoom:_room.token withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Could not exit room. Error: %@", error.description);
        }
        if (block) block(error);
    }];
}

#pragma mark - Ping call

- (void)pingRoom
{
    [[NCAPIController sharedInstance] pingCall:_room.token withCompletionBlock:^(NSError *error) {
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
    [_pingTimer invalidate];
    _pingTimer = nil;
}

#pragma mark - Chat

- (void)startReceivingChatMessages
{
    _stopChatMessagesPoll = NO;
    [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:_lastMessageId history:NO withCompletionBlock:^(NSMutableArray *messages, NSError *error) {
        if (_stopChatMessagesPoll) {
            return;
        }
        if (messages.count > 0) {
            NCChatMessage *lastMessage = messages.lastObject;
            _lastMessageId = lastMessage.messageId;
        }
        [self.delegate roomController:self didReceiveChatMessages:messages];
        [self startReceivingChatMessages];
    }];
}

- (void)stopReceivingChatMessages
{
    _stopChatMessagesPoll = YES;
}

- (void)sendChatMessage:(NSString *)message
{
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_room.token displayName:nil withCompletionBlock:^(NSError *error) {
        //TODO: Error handling
    }];
}



@end
