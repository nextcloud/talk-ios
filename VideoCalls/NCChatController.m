//
//  NCChatController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatController.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"

NSString * const NCChatControllerDidReceiveInitialChatHistoryNotification           = @"NCChatControllerDidReceiveInitialChatHistoryNotification";
NSString * const NCChatControllerDidReceiveInitialChatHistoryOfflineNotification    = @"NCChatControllerDidReceiveInitialChatHistoryOfflineNotification";
NSString * const NCChatControllerDidReceiveChatHistoryNotification                  = @"NCChatControllerDidReceiveChatHistoryNotification";
NSString * const NCChatControllerDidReceiveChatMessagesNotification                 = @"NCChatControllerDidReceiveChatMessagesNotification";
NSString * const NCChatControllerDidSendChatMessageNotification                     = @"NCChatControllerDidSendChatMessageNotification";
NSString * const NCChatControllerDidReceiveChatBlockedNotification                  = @"NCChatControllerDidReceiveChatBlockedNotification";
NSString * const NCChatControllerDidRemoveTemporaryMessagesNotification             = @"NCChatControllerDidRemoveTemporaryMessagesNotification";

@interface NCChatController ()

@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NSURLSessionTask *getHistoryTask;
@property (nonatomic, strong) NSURLSessionTask *pullMessagesTask;

@end

@implementation NCChatBlock
@end

@implementation NCChatController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (self) {
        _room = room;
        _account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:_room.accountId];
    }
    
    return self;
}

#pragma mark - Database

- (NSArray *)chatBlocksForRoom
{
    RLMResults *managedBlocks = [NCChatBlock objectsWhere:@"internalId = %@", _room.internalId];
    RLMResults *managedSortedBlocks = [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
    // Create an unmanaged copy of the blocks
    NSMutableArray *sortedBlocks = [NSMutableArray new];
    for (NCChatBlock *managedBlock in managedSortedBlocks) {
        NCChatBlock *sortedBlock = [[NCChatBlock alloc] initWithValue:managedBlock];
        [sortedBlocks addObject:sortedBlock];
    }
    
    return sortedBlocks;
}

- (NSArray *)getBatchOfMessagesInBlock:(NCChatBlock *)chatBlock fromMessageId:(NSInteger)messageId included:(BOOL)included
{
    NSInteger fromMessageId = messageId > 0 ? messageId : chatBlock.newestMessageId;
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId >= %ld AND messageId < %ld", _account.accountId, _room.token, (long)chatBlock.oldestMessageId, (long)fromMessageId];
    if (included) {
        query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId >= %ld AND messageId <= %ld", _account.accountId, _room.token, (long)chatBlock.oldestMessageId, (long)fromMessageId];
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

- (NSArray *)getNewStoredMessagesInBlock:(NCChatBlock *)chatBlock sinceMessageId:(NSInteger)messageId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId > %ld AND messageId <= %ld", _account.accountId, _room.token, (long)messageId, (long)chatBlock.newestMessageId];
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
        NSMutableArray *removedTemporaryMessages = [NSMutableArray new];
        // Add or update messages
        for (NSDictionary *messageDict in messages) {
            NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:_account.accountId];
            NCChatMessage *parent = [NCChatMessage messageWithDictionary:[messageDict objectForKey:@"parent"] andAccountId:_account.accountId];
            message.parentId = parent.internalId;
            
            if (message.referenceId && ![message.referenceId isEqualToString:@""]) {
                NCChatMessage *managedTemporaryMessage = [NCChatMessage objectsWhere:@"referenceId = %@", message.referenceId].firstObject;
                if (managedTemporaryMessage) {
                    [realm deleteObject:managedTemporaryMessage];
                    // Create a unmanaged copy of message, since 'message' will point to a managed object when added to the DB.
                    NCChatMessage *unmanagedMessage = [[NCChatMessage alloc] initWithValue:message];
                    [removedTemporaryMessages addObject:unmanagedMessage];
                }
            }
            
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
        // Send notification with removed temprary messages
        if (removedTemporaryMessages.count > 0) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            [userInfo setObject:_room.token forKey:@"room"];
            [userInfo setObject:removedTemporaryMessages forKey:@"messages"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidRemoveTemporaryMessagesNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    }];
}

- (void)updateLastChatBlockWithNewestKnown:(NSInteger)newestKnown
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedBlocks = [NCChatBlock objectsWhere:@"internalId = %@", _room.internalId];
        RLMResults *managedSortedBlocks = [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
        NCChatBlock *lastBlock = managedSortedBlocks.lastObject;
        if (newestKnown > 0) {
            lastBlock.newestMessageId = newestKnown;
        }
    }];
}

- (void)updateChatBlocksWithLastKnown:(NSInteger)lastKnown
{
    if (lastKnown <= 0) {
        return;
    }
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedBlocks = [NCChatBlock objectsWhere:@"internalId = %@", _room.internalId];
        RLMResults *managedSortedBlocks = [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
        NCChatBlock *lastBlock = managedSortedBlocks.lastObject;
        // There is more than one chat block stored
        if (managedSortedBlocks.count > 1) {
            for (NSInteger i = managedSortedBlocks.count - 2; i >= 0; i--) {
                NCChatBlock *block = managedSortedBlocks[i];
                // Merge blocks if the lastKnown message is inside the current block
                if (lastKnown >= block.oldestMessageId && lastKnown <= block.newestMessageId) {
                    lastBlock.oldestMessageId = block.oldestMessageId;
                    [realm deleteObject:block];
                    break;
                // Update lastBlock if the lastKnown message is between the 2 blocks
                } else if (lastKnown > block.newestMessageId) {
                    lastBlock.oldestMessageId = lastKnown;
                    break;
                // The current block is completely included in the retrieved history
                // This could happen if we vary the message limit when fetching messages
                // Delete included block
                } else if (lastKnown < block.oldestMessageId) {
                    [realm deleteObject:block];
                }
            }
        // There is just one chat block stored
        } else {
            lastBlock.oldestMessageId = lastKnown;
        }
    }];
}

- (void)updateChatBlocksWithReceivedMessages:(NSArray *)messages newestKnown:(NSInteger)newestKnown andLastKnown:(NSInteger)lastKnown
{
    NSArray *sortedMessages = [self sortedMessagesFromMessageArray:messages];
    NCChatMessage *newestMessageReceived = sortedMessages.lastObject;
    NSInteger newestMessageKnown = newestKnown > 0 ? newestKnown : newestMessageReceived.messageId;
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedBlocks = [NCChatBlock objectsWhere:@"internalId = %@", _room.internalId];
        RLMResults *managedSortedBlocks = [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
        
        // Create new chat block
        NCChatBlock *newBlock = [[NCChatBlock alloc] init];
        newBlock.internalId = _room.internalId;
        newBlock.accountId = _room.accountId;
        newBlock.token = _room.token;
        newBlock.oldestMessageId = lastKnown;
        newBlock.newestMessageId = newestMessageKnown;
        newBlock.hasHistory = YES;
        
        // There is at least one chat block stored
        if (managedSortedBlocks.count > 0) {
            for (NSInteger i = managedSortedBlocks.count - 1; i >= 0; i--) {
                NCChatBlock *block = managedSortedBlocks[i];
                // Merge blocks if the lastKnown message is inside the current block
                if (lastKnown >= block.oldestMessageId && lastKnown <= block.newestMessageId) {
                    block.newestMessageId = newestMessageKnown;
                    break;
                // Add new block if it didn't reach the previous block
                } else if (lastKnown > block.newestMessageId) {
                    [realm addObject:newBlock];
                    break;
                // The current block is completely included in the retrieved history
                // This could happen if we vary the message limit when fetching messages
                // Delete included block
                } else if (lastKnown < block.oldestMessageId) {
                    [realm deleteObject:block];
                }
            }
        // No chat blocks stored yet, add new chat block
        } else {
            [realm addObject:newBlock];
        }
    }];
}

- (void)updateHistoryFlagInFirstBlock
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedBlocks = [NCChatBlock objectsWhere:@"internalId = %@", _room.internalId];
        RLMResults *managedSortedBlocks = [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
        NCChatBlock *firstChatBlock = managedSortedBlocks.firstObject;
        firstChatBlock.hasHistory = NO;
    }];
}

- (void)setSendingFailedToMessageWithReferenceId:(NSString *)referenceId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCChatMessage *managedChatMessage = [NCChatMessage objectsWhere:@"referenceId = %@", referenceId].firstObject;
        managedChatMessage.sendingFailed = YES;
    }];
}

- (NSArray *)sortedMessagesFromMessageArray:(NSArray *)messages
{
    NSMutableArray *sortedMessages = [[NSMutableArray alloc] initWithCapacity:messages.count];
    for (NSDictionary *messageDict in messages) {
        NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict];
        [sortedMessages addObject:message];
    }
    // Sort by messageId
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"messageId" ascending:YES];
    NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
    [sortedMessages sortUsingDescriptors:descriptors];
    
    return sortedMessages;
}

#pragma mark - Chat

- (NSMutableArray *)getTemporaryMessages
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND isTemporary = true", _account.accountId, _room.token];
    RLMResults *managedTemporaryMessages = [NCChatMessage objectsWithPredicate:query];
    RLMResults *managedSortedTemporaryMessages = [managedTemporaryMessages sortedResultsUsingKeyPath:@"timestamp" ascending:YES];
    // Create an unmanaged copy of the messages
    NSMutableArray *sortedMessages = [NSMutableArray new];
    for (NCChatMessage *managedMessage in managedSortedTemporaryMessages) {
        NCChatMessage *sortedMessage = [[NCChatMessage alloc] initWithValue:managedMessage];
        [sortedMessages addObject:sortedMessage];
    }
    
    return sortedMessages;
}

- (void)getInitialChatHistory
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];
    
    NSInteger lastReadMessageId = 0;
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityChatReadMarker]) {
        lastReadMessageId = _room.lastReadMessage;
    }
    
    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
    if (lastChatBlock.newestMessageId > 0 && lastChatBlock.newestMessageId >= lastReadMessageId) {
        NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:lastChatBlock.newestMessageId included:YES];
        [userInfo setObject:storedMessages forKey:@"messages"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else {
        _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:lastReadMessageId history:YES includeLastMessage:YES timeout:NO forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
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
            } else {
                // Update chat blocks
                [self updateChatBlocksWithReceivedMessages:messages newestKnown:lastReadMessageId andLastKnown:lastKnownMessage];
                // Store new messages
                if (messages.count > 0) {
                    [self storeMessages:messages];
                    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
                    NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:lastReadMessageId included:YES];
                    [userInfo setObject:storedMessages forKey:@"messages"];
                }
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveInitialChatHistoryNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    }
}

- (void)getInitialChatHistoryForOfflineMode
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];
    
    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
    NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:lastChatBlock.newestMessageId included:YES];
    [userInfo setObject:storedMessages forKey:@"messages"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveInitialChatHistoryOfflineNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)getHistoryBatchFromMessagesId:(NSInteger)messageId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];
    
    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
    if (lastChatBlock && lastChatBlock.oldestMessageId < messageId) {
        NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:messageId included:NO];
        [userInfo setObject:storedMessages forKey:@"messages"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else {
        _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:messageId history:YES includeLastMessage:NO timeout:NO forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
            if (statusCode == 304) {
                [self updateHistoryFlagInFirstBlock];
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
            } else {
                // Update chat blocks
                [self updateChatBlocksWithLastKnown:lastKnownMessage];
                // Store new messages
                if (messages.count > 0) {
                    [self storeMessages:messages];
                    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
                    NSArray *historyBatch = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:messageId included:NO];
                    [userInfo setObject:historyBatch forKey:@"messages"];
                }
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatHistoryNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    }
}

- (void)getHistoryBatchOfflineFromMessagesId:(NSInteger)messageId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];
    
    NSArray *chatBlocks = [self chatBlocksForRoom];
    NSMutableArray *historyBatch = [NSMutableArray new];
    if (chatBlocks.count > 0) {
        for (NSInteger i = chatBlocks.count - 1; i >= 0; i--) {
            NCChatBlock *currentBlock = chatBlocks[i];
            BOOL noMoreMessagesToRetrieveInBlock = NO;
            if (currentBlock.oldestMessageId < messageId) {
                NSArray *storedMessages = [self getBatchOfMessagesInBlock:currentBlock fromMessageId:messageId included:NO];
                historyBatch = [[NSMutableArray alloc] initWithArray:storedMessages];
                if (storedMessages.count > 0) {
                    break;
                } else {
                    // We use this flag in case the rest of the messages in current block
                    // are system messages invisible for the user.
                    noMoreMessagesToRetrieveInBlock = YES;
                }
            }
            if (i > 0 && (currentBlock.oldestMessageId == messageId || noMoreMessagesToRetrieveInBlock)) {
                NCChatBlock *previousBlock = chatBlocks[i - 1];
                NSArray *storedMessages = [self getBatchOfMessagesInBlock:previousBlock fromMessageId:previousBlock.newestMessageId included:YES];
                historyBatch = [[NSMutableArray alloc] initWithArray:storedMessages];
                [userInfo setObject:@(YES) forKey:@"shouldAddBlockSeparator"];
                break;
            }
        }
    }
    
    if (historyBatch.count == 0) {
        [userInfo setObject:@(YES) forKey:@"noMoreStoredHistory"];
    }
    
    [userInfo setObject:historyBatch forKey:@"messages"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatHistoryNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)stopReceivingChatHistory
{
    [_getHistoryTask cancel];
}

- (void)startReceivingChatMessagesFromMessagesId:(NSInteger)messageId withTimeout:(BOOL)timeout
{
    _stopChatMessagesPoll = NO;
    [_pullMessagesTask cancel];
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:messageId history:NO includeLastMessage:NO timeout:timeout forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode) {
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
        } else {
            // Update last chat block
            [self updateLastChatBlockWithNewestKnown:lastKnownMessage];
            // Store new messages
            if (messages.count > 0) {
                [self storeMessages:messages];
                NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
                NSArray *storedMessages = [self getNewStoredMessagesInBlock:lastChatBlock sinceMessageId:messageId];
                [userInfo setObject:storedMessages forKey:@"messages"];
            }
        }
        [userInfo setObject:_room.token forKey:@"room"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatMessagesNotification
                                                            object:self
                                                          userInfo:userInfo];
        if (error.code != -999) {
            NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
            [self startReceivingChatMessagesFromMessagesId:lastChatBlock.newestMessageId withTimeout:YES];
        }
    }];
}

- (void)startReceivingNewChatMessages
{
    NCChatBlock *lastChatBlock = [self chatBlocksForRoom].lastObject;
    [self startReceivingChatMessagesFromMessagesId:lastChatBlock.newestMessageId withTimeout:NO];
}

- (void)stopReceivingNewChatMessages
{
    _stopChatMessagesPoll = YES;
    [_pullMessagesTask cancel];
}

- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:message forKey:@"message"];
    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_room.token displayName:nil replyTo:replyTo referenceId:referenceId forAccount:_account withCompletionBlock:^(NSError *error) {
        if (referenceId) {
            [userInfo setObject:referenceId forKey:@"referenceId"];
        }
        if (error) {
            [userInfo setObject:error forKey:@"error"];
            if (referenceId) {
                [self setSendingFailedToMessageWithReferenceId:referenceId];
            }
            NSLog(@"Could not send chat message. Error: %@", error.description);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidSendChatMessageNotification
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
    [userInfo setObject:_room.token forKey:@"room"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatBlockedNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)stopChatController
{
    [self stopReceivingNewChatMessages];
    [self stopReceivingChatHistory];
}

- (BOOL)hasHistoryFromMessageId:(NSInteger)messageId
{
    NCChatBlock *firstChatBlock = [self chatBlocksForRoom].firstObject;
    if (firstChatBlock && firstChatBlock.oldestMessageId == messageId) {
        return firstChatBlock.hasHistory;
    }
    return YES;
}

@end
