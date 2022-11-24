/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
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

#import "WSMessage.h"

static NSTimeInterval kSendMessageTimeoutInterval = 15;

@interface WSMessage ()

@property NSTimer *timeoutTimer;

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

- (void)setMessageTimeout
{
    // NSTimer uses the runloop of the current thread. Only the main thread guarantees a runloop, so make sure we dispatch it to main!
    // This is mainly a problem for the "hello message", because it's send from a NSURL delegate and the timer sometimes fails to run
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kSendMessageTimeoutInterval target:self selector:@selector(executeCompletionBlockWithError) userInfo:nil repeats:NO];
    });
}

- (void)executeCompletionBlock:(NSError *)error
{
    if (self.completionBlock) {
        self.completionBlock(error);
        self.completionBlock = nil;
        [_timeoutTimer invalidate];
    }
}

- (void)ignoreCompletionBlock
{
    _completionBlock = nil;
    [_timeoutTimer invalidate];
}

- (void)executeCompletionBlockWithSuccess
{
    [self executeCompletionBlock:nil];
}

- (void)executeCompletionBlockWithError
{
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
    [self executeCompletionBlock:error];
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

@end
