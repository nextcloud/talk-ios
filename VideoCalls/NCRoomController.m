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

NSString * const NCRoomControllerDidReceiveInitialChatHistoryNotification   = @"NCRoomControllerDidReceiveInitialChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatHistoryNotification          = @"NCRoomControllerDidReceiveChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatMessagesNotification         = @"NCRoomControllerDidReceiveChatMessagesNotification";
NSString * const NCRoomControllerDidSendChatMessageNotification             = @"NCRoomControllerDidSendChatMessageNotification";

@interface NCRoomController ()

@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, assign) NSInteger oldestMessageId;
@property (nonatomic, assign) NSInteger newestMessageId;
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
        _oldestMessageId = -1;
        _newestMessageId = -1;
        _hasHistory = YES;
        if (![[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityNoPing]) {
            [self startPingRoom];
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
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_oldestMessageId history:YES withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSInteger statusCode) {
        if (_stopChatMessagesPoll) {
            return;
        }
        _oldestMessageId = lastKnownMessage;
        
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (messages.count > 0) {
            NCChatMessage *lastMessage = messages.lastObject;
            _newestMessageId = lastMessage.messageId;
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
        [self startReceivingChatMessages];
    }];
}

- (void)getChatHistoryFromMessagesId:(NSInteger)messageId
{
    _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_oldestMessageId history:YES withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSInteger statusCode) {
        if (statusCode == 304) {
            _hasHistory = NO;
        }
        _oldestMessageId = lastKnownMessage > 0 ? lastKnownMessage : _oldestMessageId;
        
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (messages.count > 0) {
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
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
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_newestMessageId history:NO withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSInteger statusCode) {
        if (_stopChatMessagesPoll) {
            return;
        }
        _newestMessageId = lastKnownMessage > 0 ? lastKnownMessage : _newestMessageId;
        
        if (messages.count > 0) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
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
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:message forKey:@"message"];
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_roomToken displayName:nil withCompletionBlock:^(NSError *error) {
        if (error) {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not join room. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidSendChatMessageNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}

- (void)stopRoomController
{
    [self stopPingRoom];
    [self stopReceivingChatMessages];
    [self stopReceivingChatHistory];
}

@end
