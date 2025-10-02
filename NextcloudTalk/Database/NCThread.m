/**
 * SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCThread.h"

#import "NCChatMessage.h"

@interface NCThread () {
    NCChatMessage *firstMessageFromDict;
    NCChatMessage *lastMessageFromDict;
}

@end

@implementation NCThread

+ (NSString *)primaryKey {
    return @"internalId";
}

+ (instancetype)threadWithDictionary:(NSDictionary *)threadInfoDict andAccountId:(NSString *)accountId
{
    if (!threadInfoDict || ![threadInfoDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *threadDict = [threadInfoDict objectForKey:@"thread"];
    NSDictionary *threadAttendeeDict = [threadInfoDict objectForKey:@"attendee"];

    NCThread *thread = [[NCThread alloc] init];
    thread.accountId = accountId;
    thread.roomToken = [threadDict objectForKey:@"roomToken"];
    thread.threadId = [[threadDict objectForKey:@"id"] integerValue];
    thread.internalId = [NSString stringWithFormat:@"%@@%@@%ld", accountId, thread.roomToken, (long)thread.threadId];
    thread.title = [threadDict objectForKey:@"title"];
    thread.lastActivity = [[threadDict objectForKey:@"lastActivity"] integerValue];
    thread.numReplies = [[threadDict objectForKey:@"numReplies"] integerValue];
    thread.notificationLevel = [[threadAttendeeDict objectForKey:@"notificationLevel"] integerValue];

    NCChatMessage *firstMessage = [NCChatMessage messageWithDictionary:[threadInfoDict objectForKey:@"first"] andAccountId:accountId];
    thread->firstMessageFromDict = firstMessage;
    thread.firstMessageId = firstMessage.internalId;

    NCChatMessage *lastMessage = [NCChatMessage messageWithDictionary:[threadInfoDict objectForKey:@"last"] andAccountId:accountId];
    thread->lastMessageFromDict = lastMessage;
    thread.lastMessageId = lastMessage.internalId;

    return thread;
}

+ (instancetype)createThreadFromMessage:(NCChatMessage *)message andAccountId:(NSString *)accountId
{
    if (![message.systemMessage isEqualToString:@"thread_created"]) {
        return nil;
    }

    NCThread *managedThread = [NCThread objectsWhere:@"accountId = %@ AND roomToken = %@ AND threadId = %ld", message.accountId, message.token, (long)message.threadId].firstObject;
    if (managedThread) {
        return nil;
    }

    NCThread *thread = [[NCThread alloc] init];
    thread.accountId = message.accountId;
    thread.roomToken = message.token;
    thread.threadId = message.threadId;
    thread.title = message.threadTitle;
    thread.internalId = [NSString stringWithFormat:@"%@@%@@%ld", accountId, thread.roomToken, (long)thread.threadId];

    thread.firstMessageId = message.parentId;

    thread.updatedWithMessageId = message.messageId;

    return thread;
}

+ (void)updateThread:(NCThread *)managedThread withThread:(NCThread *)thread
{
    managedThread.title = thread.title;
    managedThread.lastActivity = thread.lastActivity;
    managedThread.numReplies = thread.numReplies;
    managedThread.notificationLevel = thread.notificationLevel;
    managedThread.firstMessageId = thread.firstMessageId;
    managedThread.lastMessageId = thread.lastMessageId;
}

+ (void)updateThreadWithThreadMessage:(NCChatMessage *)message
{
    NCThread *managedThread = [NCThread objectsWhere:@"accountId = %@ AND roomToken = %@ AND threadId = %ld", message.accountId, message.token, (long)message.threadId].firstObject;

    // Do not update if there is no thread stored yet or the thread has been updated by a newer message
    if (!managedThread || managedThread.updatedWithMessageId > message.messageId) {
        return;
    }

    managedThread.title = message.threadTitle;
    managedThread.numReplies = message.threadReplies;
    managedThread.updatedWithMessageId = message.messageId;
}

+ (nullable instancetype)threadWithThreadId:(NSInteger)threadId inRoom:(NSString *)roomToken forAccountId:(NSString *)accountId
{
    NCThread *managedThread = [NCThread objectsWhere:@"accountId = %@ AND roomToken = %@ AND threadId = %ld", accountId, roomToken, (long)threadId].firstObject;
    if (managedThread) {
        return [[NCThread alloc] initWithValue:managedThread];
    }
    return nil;
}

+ (void)storeOrUpdateThreads:(NSArray *)threads
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        for (NCThread *thread in threads) {
            NCThread *managedThread = [NCThread objectsWhere:@"internalId = %@", thread.internalId].firstObject;
            if (managedThread) {
                [self updateThread:managedThread withThread:thread];
            } else {
                [realm addObject:thread];
            }
        }
    }];
}

- (NCChatMessage *)firstMessage
{
    NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", self.firstMessageId].firstObject;
    if (managedMessage) {
        return [[NCChatMessage alloc] initWithValue:managedMessage];
    }

    return self->firstMessageFromDict;
}

- (NCChatMessage *)lastMessage
{
    NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", self.lastMessageId].firstObject;
    if (managedMessage) {
        return [[NCChatMessage alloc] initWithValue:managedMessage];
    }

    return self->lastMessageFromDict;
}

@end
