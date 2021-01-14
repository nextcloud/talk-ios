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

@class NCRoom;

extern NSString * const NCChatControllerDidReceiveInitialChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveInitialChatHistoryOfflineNotification;;
extern NSString * const NCChatControllerDidReceiveChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveChatMessagesNotification;
extern NSString * const NCChatControllerDidSendChatMessageNotification;
extern NSString * const NCChatControllerDidReceiveChatBlockedNotification;
extern NSString * const NCChatControllerDidReceiveNewerCommonReadMessageNotification;

@interface NCChatBlock : RLMObject

@property (nonatomic, strong) NSString *internalId; // accountId@token (same as room internal id)
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, assign) NSInteger oldestMessageId;
@property (nonatomic, assign) NSInteger newestMessageId;
@property (nonatomic, assign) BOOL hasHistory;

@end

@interface NCChatController : NSObject

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, assign) NSInteger lastCommonReadMessage;

- (instancetype)initForRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId;
- (NSMutableArray *)getTemporaryMessages;
- (void)getInitialChatHistory;
- (void)getInitialChatHistoryForOfflineMode;
- (void)getHistoryBatchFromMessagesId:(NSInteger)messageId;
- (void)getHistoryBatchOfflineFromMessagesId:(NSInteger)messageId;
- (void)startReceivingNewChatMessages;
- (void)stopReceivingNewChatMessages;
- (void)stopChatController;
- (BOOL)hasHistoryFromMessageId:(NSInteger)messageId;
- (void)storeMessages:(NSArray *)messages withRealm:(RLMRealm *)realm;

@end
