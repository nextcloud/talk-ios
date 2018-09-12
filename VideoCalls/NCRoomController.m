//
//  NCRoomController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomController.h"

#import "NCAPIController.h"
#import "NCSettingsController.h"
#import "NCExternalSignalingController.h"

NSString * const NCRoomControllerDidReceiveInitialChatHistoryNotification   = @"NCRoomControllerDidReceiveInitialChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatHistoryNotification          = @"NCRoomControllerDidReceiveChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatMessagesNotification         = @"NCRoomControllerDidReceiveChatMessagesNotification";

@interface NCRoomController ()

@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, assign) NSInteger lastMessageId;
@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) NSURLSessionTask *pingRoomTask;
@property (nonatomic, strong) NSURLSessionTask *getHistoryTask;
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
        if (![[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityNoPing]) {
            [self startPingRoom];
        }
        if ([[NCExternalSignalingController sharedInstance] isEnabled]) {
            [[NCExternalSignalingController sharedInstance] joinRoom:token withSessionId:sessionId];
        }
    }
    
    return self;
}

#pragma mark - Ping room

- (void)pingRoom
{
    _pingRoomTask = [[NCAPIController sharedInstance] pingCall:_roomToken withCompletionBlock:nil];
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

- (void)getInitialChatHistory
{
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_lastMessageId history:YES withCompletionBlock:^(NSMutableArray *messages, NSError *error) {
        if (_stopChatMessagesPoll) {
            return;
        }
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        NSInteger messagesCount = messages.count;
        if (messagesCount > 0) {
            NCChatMessage *lastMessage = messages.lastObject;
            _lastMessageId = lastMessage.messageId;
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
        _hasHistory = (messagesCount == 200);
        [self startReceivingChatMessages];
    }];
}

- (void)getChatHistoryFromMessagesId:(NSInteger)messageId
{
    _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:messageId history:YES withCompletionBlock:^(NSMutableArray *messages, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        NSInteger messagesCount = messages.count;
        if (messagesCount > 0) {
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
        _hasHistory = (messagesCount == 200);
    }];
}

- (void)stopReceivingChatHistory
{
    [_getHistoryTask cancel];
}

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

- (void)stopRoomController
{
    [self stopPingRoom];
    [self stopReceivingChatMessages];
    [self stopReceivingChatHistory];
}

@end
