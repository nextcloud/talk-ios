//
//  NCChatController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

@class NCRoom;

extern NSString * const NCChatControllerDidReceiveInitialChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveInitialChatHistoryOfflineNotification;;
extern NSString * const NCChatControllerDidReceiveChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveChatMessagesNotification;
extern NSString * const NCChatControllerDidSendChatMessageNotification;
extern NSString * const NCChatControllerDidReceiveChatBlockedNotification;
extern NSString * const NCChatControllerDidRemoveTemporaryMessagesNotification;

@interface NCChatBlock : RLMObject

@property (nonatomic, strong) NSString *internalId; // same as room internal id
@property (nonatomic, assign) NSInteger oldestMessageId;
@property (nonatomic, assign) NSInteger newestMessageId;
@property (nonatomic, assign) BOOL hasHistory;

@end

@interface NCChatController : NSObject

@property (nonatomic, strong) NCRoom *room;

- (instancetype)initForRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId;
- (void)getInitialChatHistory;
- (void)getInitialChatHistoryForOfflineMode;
- (void)getHistoryBatchFromMessagesId:(NSInteger)messageId;
- (void)getHistoryBatchOfflineFromMessagesId:(NSInteger)messageId;
- (void)startReceivingNewChatMessages;
- (void)stopReceivingNewChatMessages;
- (void)stopChatController;
- (BOOL)hasHistoryFromMessageId:(NSInteger)messageId;

@end
