/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "WSMessage.h"
#import "NextcloudTalk-Swift.h"

static NSTimeInterval kSendMessageTimeoutInterval = 15;

@interface WSMessage ()

@property NSTimer *timeoutTimer;
@property NSURLSessionWebSocketTask *webSocketTask;

@end

@implementation WSMessage

- (instancetype)initWithMessage:(NSDictionary *)message
{
    self = [super init];
    if (self) {
        self.message = message;
    }
    return self;
}

- (instancetype)initWithMessage:(NSDictionary *)message withCompletionBlock:(SendMessageCompletionBlock)block
{
    self = [self initWithMessage:message];
    if (self) {
        self.completionBlock = block;
    }
    return self;
}

- (void)setMessageId:(NSString *)messageId
{
    _messageId = messageId;

    NSMutableDictionary *newMessageDict = [[NSMutableDictionary alloc] initWithDictionary:_message];
    [newMessageDict setObject:messageId forKey:@"id"];
    _message = newMessageDict;
}

- (BOOL)isHelloMessage
{
    if ([[_message objectForKey:@"type"] isEqualToString:@"hello"]) {
        return YES;
    }

    return NO;
}

- (BOOL)isJoinMessage
{
    if ([[_message objectForKey:@"type"] isEqualToString:@"room"]) {
        return YES;
    }

    return NO;
}

- (void)setMessageTimeout
{
    // NSTimer uses the runloop of the current thread. Only the main thread guarantees a runloop, so make sure we dispatch it to main!
    // This is mainly a problem for the "hello message", because it's send from a NSURL delegate and the timer sometimes fails to run
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kSendMessageTimeoutInterval target:self selector:@selector(executeCompletionBlockWithSocketError) userInfo:nil repeats:NO];
    });
}

- (void)ignoreCompletionBlock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock = nil;
        [self->_timeoutTimer invalidate];
    });
}

- (void)executeCompletionBlockWithStatus:(NCExternalSignalingSendMessageStatus)status
{
    // As the timer was create on the main thread, it needs to be invalidated on the main thread as well
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionBlock) {
            self.completionBlock(self.webSocketTask, status);
            self.completionBlock = nil;
            [self->_timeoutTimer invalidate];
        }
    });
}

- (void)executeCompletionBlockWithSocketError
{
    [self executeCompletionBlockWithStatus:SendMessageSocketError];
}

- (NSString *)webSocketMessage
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_message
                                                       options:0
                                                         error:&error];
    if (!jsonData) {
        NSLog(@"Error creating websocket message: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (void)sendMessageWithWebSocket:(NSURLSessionWebSocketTask *)webSocketTask
{
    self.webSocketTask = webSocketTask;

    if (self.completionBlock) {
        [self setMessageTimeout];
    }

    //NSLog(@"Sending: %@", self.webSocketMessage);
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:self.webSocketMessage];
    [webSocketTask sendMessage:message completionHandler:^(NSError * _Nullable error) {
        if (error && self.completionBlock) {
            [self executeCompletionBlockWithSocketError];
        }
    }];
}

@end
