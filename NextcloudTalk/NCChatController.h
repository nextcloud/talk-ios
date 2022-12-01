/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

#import "NCChatMessage.h"

typedef void (^UpdateHistoryInBackgroundCompletionBlock)(NSError *error);

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

@interface NCChatController : NSObject

@property (nonatomic, strong) NCRoom *room;

- (instancetype)initForRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently;
- (void)sendChatMessage:(NCChatMessage *)message;
- (NSMutableArray *)getTemporaryMessages;
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

@end
