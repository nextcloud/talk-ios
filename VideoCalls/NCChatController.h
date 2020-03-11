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
extern NSString * const NCChatControllerDidReceiveChatHistoryNotification;
extern NSString * const NCChatControllerDidReceiveChatMessagesNotification;
extern NSString * const NCChatControllerDidSendChatMessageNotification;
extern NSString * const NCChatControllerDidReceiveChatBlockedNotification;

@interface NCChatBlock : RLMObject

@property (nonatomic, strong) NSString *internalId; // same as room internal id
@property (nonatomic, assign) NSInteger oldestMessageId;
@property (nonatomic, assign) NSInteger newestMessageId;
@property (nonatomic, assign) BOOL hasHistory;

@end

@interface NCChatController : NSObject

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NSString *userSessionId;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) BOOL inChat;
@property (nonatomic, assign) BOOL hasHistory;

- (instancetype)initForRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo;
- (void)getInitialChatHistory:(NSInteger)lastReadMessage;
- (void)getChatHistoryFromMessagesId:(NSInteger)messageId;
- (void)startReceivingChatMessagesFromMessagesId:(NSInteger)messageId withTimeout:(BOOL)timeout;
- (void)stopReceivingChatMessages;
- (void)stopChatController;

@end
