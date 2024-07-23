/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCExternalSignalingController.h"

@interface WSMessage : NSObject

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSDictionary *message;
@property (nonatomic, copy) SendMessageCompletionBlock completionBlock;

- (instancetype)initWithMessage:(NSDictionary *)message;
- (instancetype)initWithMessage:(NSDictionary *)message withCompletionBlock:(SendMessageCompletionBlock)block;
- (NSString *)webSocketMessage;
- (BOOL)isHelloMessage;
- (BOOL)isJoinMessage;
- (void)setMessageTimeout;
- (void)ignoreCompletionBlock;
- (void)executeCompletionBlockWithStatus:(NCExternalSignalingSendMessageStatus)status;
- (void)sendMessageWithWebSocket:(NSURLSessionWebSocketTask *)webSocketTask;

@end
