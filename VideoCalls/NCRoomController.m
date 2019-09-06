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
NSString * const NCRoomControllerDidReceiveChatBlockedNotification          = @"NCRoomControllerDidReceiveChatBlockedNotification";

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

- (void)getInitialChatHistory:(NSInteger)lastReadMessage
{
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:lastReadMessage history:YES includeLastMessage:YES withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
        if (_stopChatMessagesPoll) {
            return;
        }
        _oldestMessageId = lastKnownMessage;
        
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (error) {
            if ([self isChatBeingBlocked:statusCode]) {
                [self notifyChatIsBlocked];
                return;
            }
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not get initial chat history. Error: %@", error.description);
        }
        if (messages.count > 0) {
            NCChatMessage *lastMessage = messages.lastObject;
            _newestMessageId = lastMessage.messageId;
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
        if (!error) {
            [self startReceivingChatMessages];
        }
    }];
}

- (void)getChatHistoryFromMessagesId:(NSInteger)messageId
{
    _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_oldestMessageId history:YES includeLastMessage:NO withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
        if (statusCode == 304) {
            _hasHistory = NO;
        }
        _oldestMessageId = lastKnownMessage > 0 ? lastKnownMessage : _oldestMessageId;
        
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (error) {
            if ([self isChatBeingBlocked:statusCode]) {
                [self notifyChatIsBlocked];
                return;
            }
            [userInfo setObject:error forKey:@"error"];
            if (statusCode != 304) {
                NSLog(@"Could not get chat history. Error: %@", error.description);
            }
        }
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
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:_newestMessageId history:NO includeLastMessage:NO withCompletionBlock:^(NSMutableArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
        if (_stopChatMessagesPoll) {
            return;
        }
        _newestMessageId = lastKnownMessage > 0 ? lastKnownMessage : _newestMessageId;
        
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (error) {
            if ([self isChatBeingBlocked:statusCode]) {
                [self notifyChatIsBlocked];
                return;
            }
            if (statusCode != 304) {
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not get new chat messages. Error: %@", error.description);
            }
        }
        if (messages.count > 0) {
            [userInfo setObject:messages forKey:@"messages"];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatMessagesNotification
                                                            object:self
                                                          userInfo:userInfo];
        if (error.code != -999) {
            [self startReceivingChatMessages];
        }
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
            NSLog(@"Could not send chat message. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidSendChatMessageNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}

- (BOOL)isChatBeingBlocked:(NSInteger)statusCode
{
    if (statusCode == 412) {
        return YES;
    }
    return NO;
}

- (void)notifyChatIsBlocked
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_roomToken forKey:@"room"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatBlockedNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)stopRoomController
{
    [self stopPingRoom];
    [self stopReceivingChatMessages];
    [self stopReceivingChatHistory];
}

@end
