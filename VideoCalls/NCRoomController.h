//
//  NCRoomController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NCRoomController;

extern NSString * const NCRoomControllerDidReceiveChatMessagesNotification;

@interface NCRoomController : NSObject

@property (nonatomic, strong) NSString *userSessionId;
@property (nonatomic, strong) NSString *roomToken;

- (instancetype)initForUser:(NSString *)sessionId inRoom:(NSString *)token;
- (void)startPingRoom;
- (void)stopPingRoom;
- (void)sendChatMessage:(NSString *)message;
- (void)startReceivingChatMessages;
- (void)stopReceivingChatMessages;

@end
