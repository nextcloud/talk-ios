/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCChatController.h"

#import "NCAPIController.h"
#import "NCChatBlock.h"
#import "NCDatabaseManager.h"
#import "NCIntentController.h"
#import "NCRoomsManager.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCChatControllerDidReceiveInitialChatHistoryNotification           = @"NCChatControllerDidReceiveInitialChatHistoryNotification";
NSString * const NCChatControllerDidReceiveInitialChatHistoryOfflineNotification    = @"NCChatControllerDidReceiveInitialChatHistoryOfflineNotification";
NSString * const NCChatControllerDidReceiveChatHistoryNotification                  = @"NCChatControllerDidReceiveChatHistoryNotification";
NSString * const NCChatControllerDidReceiveChatMessagesNotification                 = @"NCChatControllerDidReceiveChatMessagesNotification";
NSString * const NCChatControllerDidSendChatMessageNotification                     = @"NCChatControllerDidSendChatMessageNotification";
NSString * const NCChatControllerDidReceiveChatBlockedNotification                  = @"NCChatControllerDidReceiveChatBlockedNotification";
NSString * const NCChatControllerDidReceiveNewerCommonReadMessageNotification       = @"NCChatControllerDidReceiveNewerCommonReadMessageNotification";
NSString * const NCChatControllerDidReceiveUpdateMessageNotification                = @"NCChatControllerDidReceiveUpdateMessageNotification";
NSString * const NCChatControllerDidReceiveHistoryClearedNotification               = @"NCChatControllerDidReceiveHistoryClearedNotification";
NSString * const NCChatControllerDidReceiveCallStartedMessageNotification           = @"NCChatControllerDidReceiveCallStartedMessageNotification";
NSString * const NCChatControllerDidReceiveCallEndedMessageNotification             = @"NCChatControllerDidReceiveCallEndedMessageNotification";
NSString * const NCChatControllerDidReceiveMessagesInBackgroundNotification         = @"NCChatControllerDidReceiveMessagesInBackgroundNotification";
NSString * const NCChatControllerDidReceiveThreadMessageNotification                = @"NCChatControllerDidReceiveThreadMessageNotification";

@interface NCChatController ()

@property (nonatomic, assign) BOOL stopChatMessagesPoll;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NSURLSessionTask *getHistoryTask;
@property (nonatomic, strong) NSURLSessionTask *pullMessagesTask;

@end

@implementation NCChatController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (self) {
        _room = room;
        _account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:_room.accountId];

        [[AllocationTracker shared] addAllocation:@"NCChatController"];
    }
    
    return self;
}

- (instancetype)initForThreadId:(NSInteger)threadId inRoom:(NCRoom *)room
{
    self = [super init];
    if (self) {
        _room = room;
        _threadId = threadId;
        _account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:_room.accountId];

        [[AllocationTracker shared] addAllocation:@"NCChatController"];
    }

    return self;
}

- (void)dealloc
{
    [[AllocationTracker shared] removeAllocation:@"NCChatController"];
}

- (BOOL)isThreadController
{
    return _threadId > 0;
}

- (BOOL)willBeVisibleMessage:(NCChatMessage *)message
{
    // Update messages are not visible in normal chats or thread views
    if ([message isUpdateMessage]) {
        return NO;
    }

    // Thread messages are not visible in normal chat views.
    if (![self isThreadController] && [message isThreadMessage]) {
        return NO;
    }

    // In thread controller mode we only receive thread messages,
    // so no check for non-thread messages is needed

    return YES;
}

#pragma mark - Database

- (RLMResults *)managedSortedBlocksForRoomOrThread
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"internalId = %@ AND threadId = 0", _room.internalId];
    if ([self isThreadController]) {
        predicate = [NSPredicate predicateWithFormat:@"internalId = %@ AND threadId = %ld", _room.internalId, (long)_threadId];
    }
    RLMResults *managedBlocks = [NCChatBlock objectsWithPredicate:predicate];
    return [managedBlocks sortedResultsUsingKeyPath:@"newestMessageId" ascending:YES];
}

- (NSArray *)chatBlocksForRoomOrThread
{
    RLMResults *managedSortedBlocks = [self managedSortedBlocksForRoomOrThread];
    // Create an unmanaged copy of the blocks
    NSMutableArray *sortedBlocks = [NSMutableArray new];
    for (NCChatBlock *managedBlock in managedSortedBlocks) {
        NCChatBlock *sortedBlock = [[NCChatBlock alloc] initWithValue:managedBlock];
        [sortedBlocks addObject:sortedBlock];
    }

    return sortedBlocks;
}

- (NSArray *)getBatchOfMessagesInBlock:(NCChatBlock *)chatBlock fromMessageId:(NSInteger)messageId included:(BOOL)included ensureIncludesMessageId:(NSInteger)ensuredMessageId
{
    NSInteger fromMessageId = messageId > 0 ? messageId : chatBlock.newestMessageId;
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId >= %ld AND messageId < %ld", _account.accountId, _room.token, (long)chatBlock.oldestMessageId, (long)fromMessageId];
    if (included) {
        query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId >= %ld AND messageId <= %ld", _account.accountId, _room.token, (long)chatBlock.oldestMessageId, (long)fromMessageId];
    }

    // Thread
    if ([self isThreadController]) {
        query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND threadId = %ld AND messageId >= %ld AND messageId < %ld", _account.accountId, _room.token, _threadId, (long)chatBlock.oldestMessageId, (long)fromMessageId];
        if (included) {
            query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND threadId = %ld AND messageId >= %ld AND messageId <= %ld", _account.accountId, _room.token, _threadId, (long)chatBlock.oldestMessageId, (long)fromMessageId];
        }
    }

    RLMResults *managedMessages = [NCChatMessage objectsWithPredicate:query];
    RLMResults *managedSortedMessages = [managedMessages sortedResultsUsingKeyPath:@"messageId" ascending:YES];
    // Create an unmanaged copy of the messages
    NSMutableArray *sortedMessages = [NSMutableArray new];
    NSInteger numberOfStoredVisibleMessages = 0;
    BOOL reachedEnsuredMessageId = false;

    if (ensuredMessageId <= 0) {
        // When there's no unreadMessageId we need to ensure being included, we just assume it's included to enforce the default limit
        reachedEnsuredMessageId = true;
    }

    // Iterate backwards and check if we gathered 100 visible messages (or more, if we need to include the unread marker)
    for (NSInteger i = (managedSortedMessages.count - 1); i >= 0; i--) {
        NCChatMessage *sortedMessage = [[NCChatMessage alloc] initWithValue:managedSortedMessages[i]];

        // Since we iterate backwords, insert the object at the beginning of the array to keep it sorted
        [sortedMessages insertObject:sortedMessage atIndex:0];

        if (sortedMessage.messageId == ensuredMessageId) {
            reachedEnsuredMessageId = true;
        }

        // We only count visible messages and we only count, if we already found the message that we need to ensure
        if (reachedEnsuredMessageId && [self willBeVisibleMessage:sortedMessage]) {
            numberOfStoredVisibleMessages += 1;
        }

        // Break in case we found the ensured message and we hit the visible message limit
        if (reachedEnsuredMessageId && numberOfStoredVisibleMessages >= kReceivedChatMessagesLimit) {
            break;
        }
    }

    NSLog(@"Returning batch of %ld messages", [sortedMessages count]);

    return sortedMessages;
}

- (NSArray *)getNewStoredMessagesInBlock:(NCChatBlock *)chatBlock sinceMessageId:(NSInteger)messageId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId > %ld AND messageId <= %ld", _account.accountId, _room.token, (long)messageId, (long)chatBlock.newestMessageId];

    if ([self isThreadController]) {
        query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND threadId = %ld AND messageId > %ld AND messageId <= %ld", _account.accountId, _room.token, _threadId, (long)messageId, (long)chatBlock.newestMessageId];
    }

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

- (void)storeMessages:(NSArray *)messages withRealm:(RLMRealm *)realm {
    // Add or update messages
    for (NSDictionary *messageDict in messages) {
        // messageWithDictionary takes care of setting a potential available parentId
        NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:_account.accountId];

        if (message.referenceId && ![message.referenceId isEqualToString:@""]) {
            NCChatMessage *managedTemporaryMessage = [NCChatMessage objectsWhere:@"referenceId = %@ AND isTemporary = true", message.referenceId].firstObject;
            if (managedTemporaryMessage) {
                [realm deleteObject:managedTemporaryMessage];
            }
        }
        
        NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", message.internalId].firstObject;
        if (managedMessage) {
            [NCChatMessage updateChatMessage:managedMessage withChatMessage:message isRoomLastMessage:NO];
        } else if (message) {
            [realm addObject:message];
        }

        if (message.isThreadCreatedMessage) {
            NCThread *thread = [NCThread createThreadFromMessage:message andAccountId:message.accountId];
            if (thread) {
                [realm addObject:thread];
            }
            // Do not use parent message for updating already stored message
            continue;
        }

        if (message.isThreadMessage) {
            [NCThread updateThreadWithThreadMessage:message];
        }

        NCChatMessage *parent = [NCChatMessage messageWithDictionary:[messageDict objectForKey:@"parent"] andAccountId:_account.accountId];
        NCChatMessage *managedParentMessage = [NCChatMessage objectsWhere:@"internalId = %@", parent.internalId].firstObject;
        if (managedParentMessage) {
            // updateChatMessage takes care of not setting a parentId to nil if there was one before
            [NCChatMessage updateChatMessage:managedParentMessage withChatMessage:parent isRoomLastMessage:NO];
        } else if (parent) {
            [realm addObject:parent];
        }
    }
}

- (void)storeMessages:(NSArray *)messages
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [self storeMessages:messages withRealm:realm];
    }];
}

- (BOOL)hasOlderStoredMessagesThanMessageId:(NSInteger)messageId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND messageId < %ld", _account.accountId, _room.token, (long)messageId];
    return [NCChatMessage objectsWithPredicate:query].count > 0;
}

- (void)removeAllStoredMessagesAndChatBlocks
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@", _account.accountId, _room.token];
        [realm deleteObjects:[NCChatMessage objectsWithPredicate:query]];
        [realm deleteObjects:[NCChatBlock objectsWithPredicate:query]];
    }];
}

- (void)removeExpiredMessages
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    NSInteger currentTimestamp = [[NSDate date] timeIntervalSince1970];
    [realm transactionWithBlock:^{
        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND expirationTimestamp > 0 AND expirationTimestamp <= %ld", _account.accountId, _room.token, currentTimestamp];
        [realm deleteObjects:[NCChatMessage objectsWithPredicate:query]];
    }];
}

- (void)updateLastChatBlockWithNewestKnown:(NSInteger)newestKnown
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedSortedBlocks = [self managedSortedBlocksForRoomOrThread];
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

    // Safety check: prevent storing a messageId older than the thread's first message as block's oldestMessageId when in a thread controller
    NSInteger oldestMessageKnown = [self isThreadController] && lastKnown < _threadId ? _threadId : lastKnown;

    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedSortedBlocks = [self managedSortedBlocksForRoomOrThread];
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
                    lastBlock.oldestMessageId = oldestMessageKnown;
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
            lastBlock.oldestMessageId = oldestMessageKnown;
        }
    }];
}

- (void)updateChatBlocksWithReceivedMessages:(NSArray *)messages newestKnown:(NSInteger)newestKnown andLastKnown:(NSInteger)lastKnown
{
    NSArray *sortedMessages = [self sortedMessagesFromMessageArray:messages];
    NCChatMessage *newestMessageReceived = sortedMessages.lastObject;
    NSInteger newestMessageKnown = newestKnown > 0 ? newestKnown : newestMessageReceived.messageId;
    // Safety check: prevent storing a messageId older than the thread's first message as block's oldestMessageId when in a thread controller
    NSInteger oldestMessageKnown = [self isThreadController] && lastKnown < _threadId ? _threadId : lastKnown;

    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        RLMResults *managedSortedBlocks = [self managedSortedBlocksForRoomOrThread];

        // Create new chat block
        NCChatBlock *newBlock = [[NCChatBlock alloc] init];
        newBlock.internalId = _room.internalId;
        newBlock.accountId = _room.accountId;
        newBlock.token = _room.token;
        newBlock.threadId = _threadId;
        newBlock.oldestMessageId = oldestMessageKnown;
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
        RLMResults *managedSortedBlocks = [self managedSortedBlocksForRoomOrThread];
        NCChatBlock *firstChatBlock = managedSortedBlocks.firstObject;
        firstChatBlock.hasHistory = NO;
    }];
}

- (void)transactionForMessageWithReferenceId:(NSString *)referenceId withBlock:(void(^)(NCChatMessage *message))block
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCChatMessage *managedChatMessage = [NCChatMessage objectsWhere:@"referenceId = %@ AND isTemporary = true", referenceId].firstObject;
        block(managedChatMessage);
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

- (NSArray<NCChatMessage *> * _Nonnull)getTemporaryMessages
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@ AND isTemporary = true", _account.accountId, _room.token];
    RLMResults *managedTemporaryMessages = [NCChatMessage objectsWithPredicate:query];
    RLMResults *managedSortedTemporaryMessages = [managedTemporaryMessages sortedResultsUsingKeyPath:@"timestamp" ascending:YES];
    
    // Mark temporary messages sent more than 12 hours ago as failed-to-send messages
    NSInteger twelveHoursAgoTimestamp = [[NSDate date] timeIntervalSince1970] - (60 * 60 * 12);

    for (NCChatMessage *temporaryMessage in managedTemporaryMessages) {
        if (temporaryMessage.timestamp < twelveHoursAgoTimestamp) {
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                temporaryMessage.isOfflineMessage = NO;
                temporaryMessage.sendingFailed = YES;
            }];
        }
    }

    // Create an unmanaged copy of the messages
    NSMutableArray *sortedMessages = [NSMutableArray new];
    for (NCChatMessage *managedMessage in managedSortedTemporaryMessages) {
        NCChatMessage *sortedMessage = [[NCChatMessage alloc] initWithValue:managedMessage];
        [sortedMessages addObject:sortedMessage];
    }
    
    return sortedMessages;
}

- (void)updateHistoryInBackgroundWithCompletionBlock:(UpdateHistoryInBackgroundCompletionBlock)block
{
    // If there's a pull task running right now, we should not interfere with that
    if (_pullMessagesTask && _pullMessagesTask.state == NSURLSessionTaskStateRunning) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(error);
        }

        return;
    }

    NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
    __block BOOL expired = NO;

    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"updateHistoryInBackgroundWithCompletionBlock" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called updateHistoryInBackgroundWithCompletionBlock"];
        expired = YES;

        // Make sure we actually end a running pullMessagesTask, because otherwise the completion handler might not be called in time
        [self->_pullMessagesTask cancel];
    }];

    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:lastChatBlock.newestMessageId inThread:_threadId history:NO includeLastMessage:NO timeout:NO lastCommonReadMessage:_room.lastCommonReadMessage setReadMarker:NO markNotificationsAsRead:NO forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode) {
        if (expired) {
            if (block) {
                block(error);
            }

            [bgTask stopBackgroundTask];

            return;
        }

        if (error) {
            NSLog(@"Could not get background chat history. Error: %@", error.description);
        } else {
            // Update chat blocks
            [self updateLastChatBlockWithNewestKnown:lastKnownMessage];

            // Store new messages
            if (messages.count > 0) {
                // In case we finish after the app already got active again, notify any potential view controller
                NSMutableDictionary *userInfo = [NSMutableDictionary new];
                [userInfo setObject:self->_room.token forKey:@"room"];

                for (NSDictionary *messageDict in messages) {
                    NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:self->_account.accountId];

                    if (message && [message.systemMessage isEqualToString:@"history_cleared"]) {
                        [self clearHistoryAndResetChatController];

                        [userInfo setObject:message forKey:@"historyCleared"];
                        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveHistoryClearedNotification
                                                                            object:self
                                                                          userInfo:userInfo];
                        return;
                    }
                }

                [self storeMessages:messages];
                [self checkLastCommonReadMessage:lastCommonReadMessage];

                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveMessagesInBackgroundNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }
        }

        if (block) {
            block(error);
        }

        [bgTask stopBackgroundTask];
    }];
}

- (void)checkForNewMessagesFromMessageId:(NSInteger)messageId
{
    NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
    NSArray *storedMessages = [self getNewStoredMessagesInBlock:lastChatBlock sinceMessageId:messageId];

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:self->_room.token forKey:@"room"];
    
    if (storedMessages.count > 0) {
        for (NCChatMessage *message in storedMessages) {
            // Notify if "call started" have been received
            if ([message.systemMessage isEqualToString:@"call_started"]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveCallStartedMessageNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }
            // Notify if "call eneded" have been received
            if ([message.systemMessage isEqualToString:@"call_ended"] ||
                [message.systemMessage isEqualToString:@"call_ended_everyone"] ||
                [message.systemMessage isEqualToString:@"call_missed"] ||
                [message.systemMessage isEqualToString:@"call_tried"]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveCallEndedMessageNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }
            // Notify if an "update messages" have been received
            if ([message isUpdateMessage]) {
                [userInfo setObject:message forKey:@"updateMessage"];
                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveUpdateMessageNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }
            // Notify if a "thread messages" have been received
            if ([message isThreadMessage]) {
                [userInfo setObject:message forKey:@"threadMessage"];
                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveThreadMessageNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }
            // Notify if "history cleared" has been received
            if ([message.systemMessage isEqualToString:@"history_cleared"]) {
                [userInfo setObject:message forKey:@"historyCleared"];
                [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveHistoryClearedNotification
                                                                    object:self
                                                                  userInfo:userInfo];
                return;
            }
        }
        
        [userInfo setObject:storedMessages forKey:@"messages"];
        [userInfo setObject:@(!_hasReceivedMessagesFromServer) forKey:@"firstNewMessagesAfterHistory"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatMessagesNotification
                                                            object:self
                                                          userInfo:userInfo];

        [self updateLastMessageIfNeededFromMessages:storedMessages];
    }
}

- (void)updateLastMessageIfNeededFromMessages:(NSArray *)storedMessages
{
    // Try to find the last non-update message - Messages are already sorted by messageId here
    NCChatMessage *lastNonUpdateMessage;
    NCChatMessage *lastMessage = [storedMessages lastObject];
    NCChatMessage *tempMessage;

    for (NSInteger i = (storedMessages.count - 1); i >= 0; i--) {
        tempMessage = [storedMessages objectAtIndex:i];

        if (![tempMessage isUpdateMessage]) {
            lastNonUpdateMessage = tempMessage;
            break;
        }
    }

    // Make sure we update the unread flags for the room (lastMessage can already be set, but there still might be unread flags)
    if (lastMessage && lastMessage.timestamp >= self->_room.lastActivity) {
        // Make sure our local reference to the room also has the correct lastActivity set
        if (lastNonUpdateMessage) {
            self->_room.lastActivity = lastNonUpdateMessage.timestamp;
        }

        // We always want to set the room to have no unread messages, optionally we also want to update the last message, if there's one
        [[NCRoomsManager sharedInstance] setNoUnreadMessagesForRoom:self->_room withLastMessage:lastNonUpdateMessage];
    }
}

- (void)getInitialChatHistoryForOfflineMode
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];

    NSInteger lastReadMessageId = 0;
    if ([[NCDatabaseManager sharedInstance] roomHasTalkCapability:kCapabilityChatReadMarker forRoom:self.room]) {
        lastReadMessageId = _room.lastReadMessage;
    }

    NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
    NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock fromMessageId:lastChatBlock.newestMessageId included:YES ensureIncludesMessageId:lastReadMessageId];
    [userInfo setObject:storedMessages forKey:@"messages"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveInitialChatHistoryOfflineNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)getInitialChatHistory
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];

    // Clear expired messages
    [self removeExpiredMessages];

    NSInteger lastReadMessageId = 0;
    // If the chat supports read markers and this is not a thread controller, start from the room's last read message.
    // In thread controllers, always start from the latest message (lastReadMessageId = 0) because the room's last read message
    // might be outdated and older than the thread's first message, which would lead to a 304 response.
    if ([[NCDatabaseManager sharedInstance] roomHasTalkCapability:kCapabilityChatReadMarker forRoom:self.room] && ![self isThreadController]) {
        lastReadMessageId = _room.lastReadMessage;
    }

    [self fetchHistoryUntilVisibleFromMessageId:lastReadMessageId forInitialChatHistory:YES isFirstIteration:YES completion:^(NSArray *messages, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode) {
        if (error) {
            if ([self isChatBeingBlocked:statusCode]) {
                [self notifyChatIsBlocked];
                return;
            }
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not get initial chat history. Error: %@", error.description);
        } else if (messages.count > 0) {
            [userInfo setObject:messages forKey:@"messages"];
            [self updateLastMessageIfNeededFromMessages:messages];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveInitialChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];

        [self checkLastCommonReadMessage:lastCommonReadMessage];
    }];
}

- (void)getHistoryBatchFromMessagesId:(NSInteger)messageId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];

    [self fetchHistoryUntilVisibleFromMessageId:messageId forInitialChatHistory:NO isFirstIteration:YES completion:^(NSArray *messages, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode) {
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
        } else if (messages.count > 0) {
            [userInfo setObject:messages forKey:@"messages"];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveChatHistoryNotification
                                                            object:self
                                                          userInfo:userInfo];
    }];
}


- (void)fetchHistoryUntilVisibleFromMessageId:(NSInteger)messageId forInitialChatHistory:(BOOL)forInitialChatHistory isFirstIteration:(BOOL)isFirstIteration completion:(void (^)(NSArray *messages, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode))completion
{
    NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;

    // First, try to load messages from local storage (DB)
    if (lastChatBlock) {
        BOOL canUseLocalStorage = NO;

        if (forInitialChatHistory) {
            // For initial chat history: make sure messageId is inside the last chat block
            canUseLocalStorage = (lastChatBlock.newestMessageId > 0 &&
                                  messageId >= lastChatBlock.oldestMessageId &&
                                  lastChatBlock.newestMessageId >= messageId);
        } else {
            // For history batch: just make sure messageId is newer than last chat block's oldest message
            canUseLocalStorage = (lastChatBlock.newestMessageId > 0 &&
                                  messageId >= lastChatBlock.oldestMessageId);
        }

        if (canUseLocalStorage) {
            // For initial chat history: always get batch from last chat block's newest message, even if it's not the first iteration.
            // For history batch: get batch from the passed messageId. If it's not the first iteration, we will just skip invisible messages
            // from previous iterations and not pass them to the chat view.
            NSArray *storedMessages = [self getBatchOfMessagesInBlock:lastChatBlock
                                                        fromMessageId:forInitialChatHistory ? lastChatBlock.newestMessageId : messageId
                                                             included:forInitialChatHistory
                                              ensureIncludesMessageId:forInitialChatHistory ? messageId : 0];

            for (NCChatMessage *message in storedMessages) {
                // Since the passed messageId might not be the lowest one, we update it here to ensure we request the missing messages
                if (message.messageId < messageId) {
                    messageId = message.messageId;
                }

                // If there is at least one visible message, we can stop fetching messages and pass them
                if ([self willBeVisibleMessage:message]) {
                    completion(storedMessages, 0, nil, 0);
                    return;
                }
            }
        }
    }

    // If no messages are found or visible in last chat block, fall back to fetching them from the server
    _getHistoryTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token
                                                                fromLastMessageId:messageId
                                                                         inThread:_threadId
                                                                          history:YES
                                                               includeLastMessage:forInitialChatHistory
                                                                          timeout:NO
                                                            lastCommonReadMessage:_room.lastCommonReadMessage
                                                                    setReadMarker:YES
                                                          markNotificationsAsRead:YES
                                                                       forAccount:_account
                                                              withCompletionBlock:^(NSArray *messages,
                                                                                    NSInteger lastKnownMessage,
                                                                                    NSInteger lastCommonReadMessage,
                                                                                    NSError *error,
                                                                                    NSInteger statusCode) {
        if (self->_stopChatMessagesPoll) {
            return;
        }

        // Error handling
        if (error) {
            completion(nil, 0, error, statusCode);
            return;
        }

        // Update chat blocks
        // Only store a new block when getting initial history and we are in the first iteration.
        // Otherwise, only update the chat blocks with history messages ("backwards").
        if (forInitialChatHistory && isFirstIteration) {
            [self updateChatBlocksWithReceivedMessages:messages newestKnown:messageId andLastKnown:lastKnownMessage];
        } else {
            [self updateChatBlocksWithLastKnown:lastKnownMessage];
        }

        // Store new messages
        if (messages.count > 0) {
            [self storeMessages:messages];

            NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
            // For initial chat history: always get batch from last chat block's newest message, even if it's not the first iteration.
            // For history batch: get batch from the passed messageId. If it's not the first iteration, we will just skip invisible messages
            // from previous iterations and not pass them to the chat view.
            NSArray *history = [self getBatchOfMessagesInBlock:lastChatBlock
                                                 fromMessageId:forInitialChatHistory ? lastChatBlock.newestMessageId : messageId
                                                      included:forInitialChatHistory
                                       ensureIncludesMessageId:forInitialChatHistory ? messageId : 0];

            for (NCChatMessage *message in history) {
                if ([self willBeVisibleMessage:message]) {
                    completion(history, lastCommonReadMessage, nil, 0);
                    return;
                }
            }

            // Recursively fetch messages until finding visible ones
            [self fetchHistoryUntilVisibleFromMessageId:lastKnownMessage
                                  forInitialChatHistory:forInitialChatHistory
                                       isFirstIteration:NO
                                             completion:completion];
            return;
        }

        completion(@[], 0, nil, 0);
    }];
}

- (void)getHistoryBatchOfflineFromMessagesId:(NSInteger)messageId
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_room.token forKey:@"room"];
    
    NSArray *chatBlocks = [self chatBlocksForRoomOrThread];
    NSMutableArray *historyBatch = [NSMutableArray new];
    if (chatBlocks.count > 0) {
        for (NSInteger i = chatBlocks.count - 1; i >= 0; i--) {
            NCChatBlock *currentBlock = chatBlocks[i];
            BOOL noMoreMessagesToRetrieveInBlock = NO;
            if (currentBlock.oldestMessageId < messageId) {
                NSArray *storedMessages = [self getBatchOfMessagesInBlock:currentBlock fromMessageId:messageId included:NO ensureIncludesMessageId:0];
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
                NSArray *storedMessages = [self getBatchOfMessagesInBlock:previousBlock fromMessageId:previousBlock.newestMessageId included:YES ensureIncludesMessageId:0];
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
    _pullMessagesTask = [[NCAPIController sharedInstance] receiveChatMessagesOfRoom:_room.token fromLastMessageId:messageId inThread:_threadId history:NO includeLastMessage:NO timeout:timeout lastCommonReadMessage:_room.lastCommonReadMessage setReadMarker:YES markNotificationsAsRead:YES forAccount:_account withCompletionBlock:^(NSArray *messages, NSInteger lastKnownMessage, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode) {
        if (self->_stopChatMessagesPoll) {
            return;
        }

        if (error) {
            if ([self isChatBeingBlocked:statusCode]) {
                [self notifyChatIsBlocked];
                return;
            }

            if (statusCode == 429) {
                [NCUtils log:@"Brute-force protected, received 429 while receiving messages. No further polling."];
                return;
            }

            if (statusCode != 304) {
                NSLog(@"Could not get new chat messages. Error: %@", error.description);
            }
        } else {
            // Update last chat block
            [self updateLastChatBlockWithNewestKnown:lastKnownMessage];
            
            // Store new messages
            if (messages.count > 0) {
                [self storeMessages:messages];
                [self checkForNewMessagesFromMessageId:messageId];

                for (NSDictionary *messageDict in messages) {
                    NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:self->_account.accountId];

                    // When we receive a "history_cleared" message, we don't continue here, as otherwise
                    // we would request new message, but instead, we need to request the inital history again
                    if ([message.systemMessage isEqualToString:@"history_cleared"]) {
                        return;
                    }
                }
            }
        }

        self->_hasReceivedMessagesFromServer = YES;

        [self checkLastCommonReadMessage:lastCommonReadMessage];
        
        if (error.code != -999) {
            NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
            [self startReceivingChatMessagesFromMessagesId:lastChatBlock.newestMessageId withTimeout:YES];
        }
    }];
}

- (void)startReceivingNewChatMessages
{
    NCChatBlock *lastChatBlock = [self chatBlocksForRoomOrThread].lastObject;
    [self startReceivingChatMessagesFromMessagesId:lastChatBlock.newestMessageId withTimeout:NO];
}

- (void)stopReceivingNewChatMessages
{
    _stopChatMessagesPoll = YES;
    [_pullMessagesTask cancel];
}

- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCChatControllerSendMessage" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called - sendChatMessage"];
    }];

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:message forKey:@"message"];

    __block NSInteger retryCount;

    if (referenceId) {
        // Reset offline message flag before retrying to send to prevent race conditions and
        // possible ending up with multiple identical messages sent
        [self transactionForMessageWithReferenceId:referenceId withBlock:^(NCChatMessage *message) {
            message.isOfflineMessage = NO;
            retryCount = message.offlineMessageRetryCount;
        }];
    }

    [[NCAPIController sharedInstance] sendChatMessage:message toRoom:_room.token threadTitle:nil replyTo:replyTo referenceId:referenceId silently:silently forAccount:_account withCompletionBlock:^(NSError *error) {
        if (referenceId) {
            [userInfo setObject:referenceId forKey:@"referenceId"];
        }

        if (error) {
            [userInfo setObject:error forKey:@"error"];

            if (referenceId) {
                if (retryCount >= 5) {
                    // After 5 retries, we assume sending is not possible
                    [self transactionForMessageWithReferenceId:referenceId withBlock:^(NCChatMessage *message) {
                        message.sendingFailed = YES;
                        message.isOfflineMessage = NO;
                    }];

                } else {
                    [self transactionForMessageWithReferenceId:referenceId withBlock:^(NCChatMessage *message) {
                        message.sendingFailed = NO;
                        message.isOfflineMessage = YES;
                        message.offlineMessageRetryCount = (++retryCount);
                    }];

                    [userInfo setObject:@(YES) forKey:@"isOfflineMessage"];
                }
            }

            [NCUtils log:[NSString stringWithFormat:@"Could not send chat message. Error: %@", error.description]];
        } else {
            [[NCIntentController sharedInstance] donateSendMessageIntentForRoom:self->_room];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidSendChatMessageNotification
                                                            object:self
                                                          userInfo:userInfo];

        [bgTask stopBackgroundTask];
    }];
}

- (void)sendChatMessage:(NCChatMessage *)message {
    if ([message.messageType isEqualToString:kMessageTypeVoiceMessage]) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

        [[NCAPIController sharedInstance] uniqueNameForFileUploadWithName:message.message
                                                             originalName:YES
                                                               forAccount:activeAccount
                                                      withCompletionBlock:^(NSString *fileServerURL, NSString *fileServerPath, NSInteger _, NSString *__) {
            if (fileServerURL && fileServerPath) {
                NSMutableDictionary *talkMetaData = [NSMutableDictionary new];
                [talkMetaData setObject:@"voice-message" forKey:@"messageType"];

                if (message.parentMessageId > 0) {
                    [talkMetaData setObject:@(message.parentMessageId) forKey:@"replyTo"];
                }

                if ([self isThreadController]) {
                    [talkMetaData setObject:@(self.threadId) forKey:@"threadId"];
                }

                [ChatFileUploader uploadFileWithLocalPath:message.file.fileStatus.fileLocalPath
                                            fileServerURL:fileServerURL
                                           fileServerPath:fileServerPath
                                             talkMetaData:talkMetaData
                                         temporaryMessage:message
                                                     room:self.room
                                               completion:^(NSInteger statusCode, NSString *errorMessage) {
                    switch (statusCode) {
                        case 200:
                            NSLog(@"Successfully uploaded and shared voice message.");
                            break;
                        case 403:
                            NSLog(@"Failed to share voice message.");
                            break;
                        case 404:
                        case 409:
                            NSLog(@"Failed to check or create attachment folder.");
                            break;
                        case 507:
                            NSLog(@"User storage quota exceeded.");
                            break;
                        default:
                            NSLog(@"Failed to upload voice message with error code: %ld", (long)statusCode);
                            break;
                    }
                }];
            } else {
                NSLog(@"Could not find unique name for voice message file.");
            }
        }];
    } else {
        [self sendChatMessage:message.sendingMessage replyTo:message.parentMessageId referenceId:message.referenceId silently:message.isSilent];
    }
}

- (void)checkLastCommonReadMessage:(NSInteger)lastCommonReadMessage
{
    if (lastCommonReadMessage > 0) {
        BOOL newerCommonReadReceived = lastCommonReadMessage > self->_room.lastCommonReadMessage;
        
        if (newerCommonReadReceived) {
            self->_room.lastCommonReadMessage = lastCommonReadMessage;
            [[NCRoomsManager sharedInstance] updateLastCommonReadMessage:lastCommonReadMessage forRoom:self->_room];
            
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            [userInfo setObject:self->_room.token forKey:@"room"];
            [userInfo setObject:@(lastCommonReadMessage) forKey:@"lastCommonReadMessage"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidReceiveNewerCommonReadMessageNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    }
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
    self.hasReceivedMessagesFromServer = NO;
}

- (void)clearHistoryAndResetChatController
{
    [_pullMessagesTask cancel];
    [self removeAllStoredMessagesAndChatBlocks];
    _room.lastReadMessage = 0;
}

- (BOOL)hasHistoryFromMessageId:(NSInteger)messageId
{
    NCChatBlock *firstChatBlock = [self chatBlocksForRoomOrThread].firstObject;
    if (firstChatBlock && firstChatBlock.oldestMessageId == messageId) {
        return firstChatBlock.hasHistory;
    }
    return YES;
}

- (void)getMessageContextForMessageId:(NSInteger)messageId withLimit:(NSInteger)limit withCompletionBlock:(GetMessagesContextCompletionBlock)block
{
    [[NCAPIController sharedInstance] getMessageContextInRoom:self.room.token forMessageId:messageId withLimit:limit forAccount:self.account withCompletionBlock:^(NSArray *messages, NSError *error, NSInteger statusCode) {
        if (error) {
            if (block) {
                block(nil);
            }

            return;
        }

        NSMutableArray *chatMessages = [[NSMutableArray alloc] initWithCapacity:messages.count];

        for (NSDictionary *messageDict in messages) {
            NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict andAccountId:self.account.accountId];
            [chatMessages addObject:message];

            if (!message.file) {
                continue;
            }

            // Try to get the stored preview height from our database, when the message is already stored
            NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", message.internalId].firstObject;

            if (managedMessage && managedMessage.file && managedMessage.file.previewImageHeight > 0) {
                message.file.previewImageHeight = managedMessage.file.previewImageHeight;
            }
        }

        if (block) {
            block(chatMessages);
        }
    }];
}

@end
