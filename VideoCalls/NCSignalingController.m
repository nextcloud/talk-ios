//
//  NCSignalingController.m
//  VideoCalls
//
//  Created by Ivan Sein on 01.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCSignalingController.h"

#import "NCAPIController.h"

@interface NCSignalingController()
{
    BOOL _shouldStopPullingMessages;
    NSTimer *_pingTimer;
}

@end

@implementation NCSignalingController

- (void)startPullingSignalingMessages
{
    _shouldStopPullingMessages = NO;
    [self pullSignalingMessages];
}

- (void)stopPullingSignalingMessages
{
    _shouldStopPullingMessages = YES;
}

- (void)pullSignalingMessages
{
    [[NCAPIController sharedInstance] pullSignalingMessagesWithCompletionBlock:^(NSDictionary *messages, NSError *error, NSInteger errorCode) {
        if (_shouldStopPullingMessages) {
            return;
        }
        NSArray *messagesArray = [[messages objectForKey:@"ocs"] objectForKey:@"data"];
        for (NSDictionary *message in messagesArray) {
            if ([self.observer respondsToSelector:@selector(signalingController:didReceiveSignalingMessage:)]) {
                [self.observer signalingController:self didReceiveSignalingMessage:message];
            }
        }
        [self pullSignalingMessages];
    }];
}

- (void)sendSignalingMessages:(NSArray *)messages
{
    [[NCAPIController sharedInstance] sendSignalingMessages:[self messagesJSONSerialization:messages] withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        NSLog(@"Sent %ld signaling messages", messages.count);
    }];
}

- (void)sendSignalingMessage:(NCSignalingMessage *)message
{
    NSArray *messagesArray = [NSArray arrayWithObjects:[message messageDict], nil];
    NSString *JSONSerializedMessages = [self messagesJSONSerialization:messagesArray];
    [[NCAPIController sharedInstance] sendSignalingMessages:JSONSerializedMessages withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        if (error) {
            //TODO: Error handling
            NSLog(@"Error sending signaling message.");
        }
        NSLog(@"Sent %@", JSONSerializedMessages);
    }];
}

- (NSString *)messagesJSONSerialization:(NSArray *)messages
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messages
                                                       options:0
                                                         error:&error];
    
    if (! jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    return jsonString;
}

@end
