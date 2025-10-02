/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCChatMessage.h"

typedef void (^UpdateHistoryInBackgroundCompletionBlock)(NSError *error);
typedef void (^GetMessagesContextCompletionBlock)(NSArray<NCChatMessage *> * _Nullable messages);

@class NCRoom;

extern NSString * const NCChatControllerDidReceiveInitialChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveInitialChatHistoryOfflineNotification;;
extern NSString * const NCChatControllerDidReceiveChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveChatMessagesNotification;
extern NSString * const NCChatControllerDidSendChatMessageNotification;
extern NSString * const NCChatControllerDidReceiveChatBlockedNotification;
extern NSString * const NCChatControllerDidReceiveNewerCommonReadMessageNotification;
extern NSString * const NCChatControllerDidReceiveUpdateMessageNotification;
extern NSString * const NCChatControllerDidReceiveHistoryClearedNotification;
extern NSString * const NCChatControllerDidReceiveCallStartedMessageNotification;
extern NSString * const NCChatControllerDidReceiveCallEndedMessageNotification;
extern NSString * const NCChatControllerDidReceiveMessagesInBackgroundNotification;
extern NSString * const NCChatControllerDidReceiveThreadMessageNotification;

@interface NCChatController : NSObject

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, assign) NSInteger threadId;
@property (nonatomic, assign) BOOL hasReceivedMessagesFromServer;

- (instancetype)initForRoom:(NCRoom *)room;
- (instancetype)initForThreadId:(NSInteger)threadId inRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently;
- (void)sendChatMessage:(NCChatMessage *)message;
- (NSArray<NCChatMessage *> * _Nonnull)getTemporaryMessages;
- (void)getInitialChatHistory;
- (void)getInitialChatHistoryForOfflineMode;
- (void)getHistoryBatchFromMessagesId:(NSInteger)messageId;
- (void)getHistoryBatchOfflineFromMessagesId:(NSInteger)messageId;
- (BOOL)hasOlderStoredMessagesThanMessageId:(NSInteger)messageId;
- (void)checkForNewMessagesFromMessageId:(NSInteger)messageId;
- (void)updateHistoryInBackgroundWithCompletionBlock:(UpdateHistoryInBackgroundCompletionBlock)block;
- (void)startReceivingNewChatMessages;
- (void)stopReceivingNewChatMessages;
- (void)stopChatController;
- (void)clearHistoryAndResetChatController;
- (void)removeExpiredMessages;
- (BOOL)hasHistoryFromMessageId:(NSInteger)messageId;
- (void)storeMessages:(NSArray *)messages withRealm:(RLMRealm *)realm;
- (void)getMessageContextForMessageId:(NSInteger)messageId withLimit:(NSInteger)limit withCompletionBlock:(GetMessagesContextCompletionBlock)block;

@end
