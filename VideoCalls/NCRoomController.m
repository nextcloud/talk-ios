//
//  NCRoomController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomController.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"

NSString * const NCRoomControllerDidReceiveInitialChatHistoryNotification   = @"NCRoomControllerDidReceiveInitialChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatHistoryNotification          = @"NCRoomControllerDidReceiveChatHistoryNotification";
NSString * const NCRoomControllerDidReceiveChatMessagesNotification         = @"NCRoomControllerDidReceiveChatMessagesNotification";
NSString * const NCRoomControllerDidSendChatMessageNotification             = @"NCRoomControllerDidSendChatMessageNotification";
NSString * const NCRoomControllerDidReceiveChatBlockedNotification          = @"NCRoomControllerDidReceiveChatBlockedNotification";

@interface NCRoomController ()

@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) NSURLSessionTask *getHistoryTask;
@property (nonatomic, strong) NSURLSessionTask *pullMessagesTask;

@end

@implementation NCRoomController

- (instancetype)initForAccountId:(NSString *)accountId withSessionId:(NSString *)sessionId inRoom:(NSString *)token
{
    self = [super init];
    if (self) {
        _accountId = accountId;
        _account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
        _userSessionId = sessionId;
        _roomToken = token;
        _room = [[NCRoomsManager sharedInstance] roomWithToken:token forAccountId:accountId];
        _hasHistory = YES;
    }
    
    return self;
}

#pragma mark - Database

- (NSArray *)getStoredMessagesFromMessageId:(NSInteger)messageId included:(BOOL)included
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId < %ld", _account.accountId, _room.token, (long)messageId];
    if (included) {
        query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId <= %ld", _account.accountId, _room.token, (long)messageId];
    }
    RLMResults *managedMessages = [NCChatMessage objectsWithPredicate:query];
    RLMResults *managedSortedMessages = [managedMessages sortedResultsUsingKeyPath:@"messageId" ascending:YES];
    // Create an unmanaged copy of the messages
    NSMutableArray *sortedMessages = [NSMutableArray new];
    NSInteger startingIndex = managedSortedMessages.count - kReceivedChatMessagesLimit;
    startingIndex = (startingIndex < 0) ? 0 : startingIndex;
    for (NSInteger i = startingIndex; i < managedSortedMessages.count; i++) {
        NCChatMessage *sortedMessage = [[NCChatMessage alloc] initWithValue:managedSortedMessages[i]];
        [sortedMessages addObject:sortedMessage];
    }
    
    return sortedMessages;
}

- (NSArray *)getNewStoredMessagesSinceMessageId:(NSInteger)messageId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId > %ld", _account.accountId, _room.token, (long)messageId];
    RLMResults *managedMessages = [NCChatMessage objectsWithPredicate:query];
    RLMResults *managedSortedMessages = [managedMessages sortedResultsUsingKeyPath:@"messageId" ascending:YES];
    // Create an unmanaged copy of the messages
    NSMutableArray *sortedMessages = [NSMutableArray new];
    for (NCChatMessage *managedMessage in managedSortedMessages) {
        NCChatMessage *sortedMessage = [[NCChatMessage alloc] initWithValue:managedMessage];
        [sortedMessages addObject:sortedMessage];
    }
    
    return sortedMessages;
}

- (void)storeMessages:(NSArray *)messages
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        // Add or update messages
        for (NSDictionary *messageDict in messages) {
            NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:_account.accountId];
            NCChatMessage *parent = [NCChatMessage messageWithDictionary:[messageDict objectForKey:@"parent"] andAccountId:_account.accountId];
            message.parentId = parent.internalId;
            
            NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", message.internalId].firstObject;
            if (managedMessage) {
                [NCChatMessage updateChatMessage:managedMessage withChatMessage:message];
            } else if (message) {
                [realm addObject:message];
            }
            
            NCChatMessage *managedParentMessage = [NCChatMessage objectsWhere:@"internalId = %@", parent.internalId].firstObject;
            if (managedParentMessage) {
                [NCChatMessage updateChatMessage:managedParentMessage withChatMessage:parent];
            } else if (parent) {
                [realm addObject:parent];
            }
        }
    }];
}

- (void)updateOldestAndNewestStoredMessagesForRoom
{
    NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", _room.internalId].firstObject;
    RLMResults *managedMessages = [NCChatMessage objectsWhere:@"accountId = %@ AND token = %@", _account.accountId, _room.token];
    RLMResults *managedSortedMessages = [managedMessages sortedResultsUsingKeyPath:@"messageId" ascending:YES];
    NCChatMessage *firstMessage = managedSortedMessages.firstObject;
    NCChatMessage *lastMessage = managedSortedMessages.lastObject;
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        managedRoom.oldestMessageReceived = firstMessage.messageId;
        managedRoom.newestMessageReceived = lastMessage.messageId;
    }];
    _room = [[NCRoom alloc] initWithValue:managedRoom];
}

#pragma mark - Chat

- (void)getInitialChatHistory:(NSInteger)lastReadMessage
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_roomToken forKey:@"room"];
    
    if (_room.newestMessageReceived >= lastReadMessage) {
        NSArray *storedMessages = [self getStoredMessagesFromMessageId:lastReadMessage included:YES];
        [userInfo setObject:storedMessages forKey:@"messages"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
        [self startReceivingChatMessagesFromMessagesId:_room.newestMessageReceived withTimeout:NO];
    } else {
        _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:lastReadMessage history:YES includeLastMessage:YES timeout:NO forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
            if (_stopChatMessagesPoll) {
                return;
            }
            if (error) {
                if ([self isChatBeingBlocked:statusCode]) {
                    [self notifyChatIsBlocked];
                    return;
                }
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not get initial chat history. Error: %@", error.description);
            }
            if (messages.count > 0) {
                [self storeMessages:messages];
                NSArray *storedMessages = [self getStoredMessagesFromMessageId:lastReadMessage included:YES];
                [userInfo setObject:storedMessages forKey:@"messages"];
                [self updateOldestAndNewestStoredMessagesForRoom];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveInitialChatHistoryNotification
                                                                object:self
                                                              userInfo:userInfo];
            if (!error) {
                [self startReceivingChatMessagesFromMessagesId:_room.newestMessageReceived withTimeout:NO];
            }
        }];
    }
}

- (void)getChatHistoryFromMessagesId:(NSInteger)messageId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_roomToken forKey:@"room"];
    
    if (_room.oldestMessageReceived > 0 && _room.oldestMessageReceived < messageId) {
        NSArray *storedMessages = [self getStoredMessagesFromMessageId:messageId included:NO];
        [userInfo setObject:storedMessages forKey:@"messages"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else {
        _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:messageId history:YES includeLastMessage:NO timeout:NO forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
            if (statusCode == 304) {
                _hasHistory = NO;
            }
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
                [self storeMessages:messages];
                NSArray *storedMessages = [self getStoredMessagesFromMessageId:messageId included:NO];
                [userInfo setObject:storedMessages forKey:@"messages"];
                [self updateOldestAndNewestStoredMessagesForRoom];
                
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatHistoryNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    }
}

- (void)stopReceivingChatHistory
{
    [_getHistoryTask cancel];
}

- (void)startReceivingChatMessagesFromMessagesId:(NSInteger)messageId withTimeout:(BOOL)timeout
{
    _stopChatMessagesPoll = NO;
    [_pullMessagesTask cancel];
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_roomToken fromLastMessageId:messageId history:NO includeLastMessage:NO timeout:timeout forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
        if (_stopChatMessagesPoll) {
            return;
        }
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
            [self storeMessages:messages];
            NSArray *storedMessages = [self getNewStoredMessagesSinceMessageId:messageId];
            [userInfo setObject:storedMessages forKey:@"messages"];
            [self updateOldestAndNewestStoredMessagesForRoom];
        }
        [userInfo setObject:_roomToken forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomControllerDidReceiveChatMessagesNotification
                                                            object:self
                                                          userInfo:userInfo];
        if (error.code != -999) {
            [self startReceivingChatMessagesFromMessagesId:_room.newestMessageReceived withTimeout:YES];
        }
    }];
}

- (void)stopReceivingChatMessages
{
    _stopChatMessagesPoll = YES;
    [_pullMessagesTask cancel];
}

- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:message forKey:@"message"];
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_roomToken displayName:nil replyTo:replyTo forAccount:_account withCompletionBlock:^(NSError *error) {
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
    [self stopReceivingChatMessages];
    [self stopReceivingChatHistory];
}

@end
