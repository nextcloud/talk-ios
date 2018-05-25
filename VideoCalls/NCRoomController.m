//
//  NCRoomController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomController.h"

#import "NCAPIController.h"

NSString * const NCRoomControllerDidReceiveChatMessagesNotification = @"NCRoomControllerDidReceiveChatMessagesNotification";

@interface NCRoomController ()

@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, assign) NSInteger lastMessageId;
@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) NSURLSessionTask *pingRoomTask;
@property (nonatomic, strong) NSURLSessionTask *pullMessagesTask;

@end

@implementation NCRoomController

- (instancetype)initForUser:(NSString *)sessionId inRoom:(NSString *)token
{
    self = [super init];
    if (self) {
        _userSessionId = sessionId;
        _roomToken = token;
        _lastMessageId = -1;
        [self startPingRoom];
    }
    
    return self;
}

#pragma mark - Ping room

- (void)pingRoom
{
    _pingRoomTask = [[NCAPIController sharedInstance] pingCall:_roomToken withCompletionBlock:^(NSError *error) {
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
    [_pullMessagesTask cancel];
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_lastMessageId history:NO withCompletionBlock:^(NSMutableArray *messages, NSError *error) {
        if (_stopChatMessagesPoll) {
            return;
        }
        if (messages.count > 0) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            NCChatMessage *lastMessage = messages.lastObject;
            _lastMessageId = lastMessage.messageId;
            [userInfo setObject:messages forKey:@"messages"];
            [userInfo setObject:_roomToken forKey:@"room"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatMessagesNotification
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

- (void)sendChatMessage:(NSString *)message
{
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_roomToken displayName:nil withCompletionBlock:^(NSError *error) {
        //TODO: Error handling
    }];
}

@end
