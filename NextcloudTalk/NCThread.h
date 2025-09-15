/**
 * SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@class NCChatMessage;

@interface NCThread : RLMObject

@property (nonatomic, strong) NSString *internalId; // accountId@token@threadId
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, assign) NSInteger threadId;
@property (nonatomic, strong) NSString *roomToken;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, assign) NSInteger lastActivity;
@property (nonatomic, assign) NSInteger numReplies;
@property (nonatomic, assign) NSInteger notificationLevel;
@property (nonatomic, strong) NSString *firstMessageId;
@property (nonatomic, strong) NSString *lastMessageId;
@property (nonatomic, assign) NSInteger updatedWithMessageId;

+ (instancetype)threadWithDictionary:(NSDictionary *)threadInfoDict andAccountId:(NSString *)accountId;
+ (instancetype)createThreadFromMessage:(NCChatMessage *)message andAccountId:(NSString *)accountId;
+ (nullable instancetype)threadWithThreadId:(NSInteger)threadId inRoom:(NSString *)roomToken forAccountId:(NSString *)accountId;
+ (void)storeOrUpdateThreads:(NSArray *)threads;
+ (void)updateThreadWithThreadMessage:(NCChatMessage *)message;

- (NCChatMessage * _Nullable)firstMessage;
- (NCChatMessage * _Nullable)lastMessage;

@end
NS_ASSUME_NONNULL_END
