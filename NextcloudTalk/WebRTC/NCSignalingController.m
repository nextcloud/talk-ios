/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCSignalingController.h"

#import <WebRTC/RTCIceServer.h>

#import "TalkAccount.h"

#import "NextcloudTalk-Swift.h"

@interface NCSignalingController()
{
    NCRoom *_room;
    BOOL _shouldStopPullingMessages;
    NSInteger _consecutivePullFailures;
    NSInteger _consecutiveSessionGoneFailures;
    SignalingSettings *_signalingSettings;
    NSURLSessionTask *_getSignalingSettingsTask;
    NSURLSessionTask *_pullSignalingMessagesTask;
}

@end

// About 45s of retrying with the backoff below
static NSInteger const kMaxConsecutiveSessionGoneFailures = 5;

@implementation NCSignalingController

- (instancetype)initForRoom:(NCRoom *)room
{
    self = [super init];
    if (self) {
        _room = room;
    }
    return self;
}

- (void)dealloc
{
    NSLog(@"NCSignalingController dealloc");
}

- (void)updateSignalingSettingsWithCompletionBlock:(SignalingSettingsUpdatedCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

    _getSignalingSettingsTask = [[NCAPIController sharedInstance] getSignalingSettingsFor:activeAccount forRoom:_room.token completionBlock:^(SignalingSettings * _Nullable settings, NSError * _Nullable error) {
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }

            // TODO: Error handling
            [NCLog log:[NSString stringWithFormat:@"Could not get signaling settings. Error: %@", error.description]];
        }

        if (settings) {
            self->_signalingSettings = settings;
        }

        if (block) {
            block(self->_signalingSettings);
        }
    }];
}

- (NSArray *)getIceServers
{
    NSMutableArray *servers = [[NSMutableArray alloc] init];

    if (_signalingSettings) {
        for (StunServer *stunServer in _signalingSettings.stunServers) {
            RTCIceServer *iceServer = [[RTCIceServer alloc] initWithURLStrings:stunServer.urls
                                                                      username:@""
                                                                    credential:@""];
            [servers addObject:iceServer];
        }

        for (TurnServer *turnServer in _signalingSettings.turnServers) {
            RTCIceServer *iceServer = [[RTCIceServer alloc] initWithURLStrings:turnServer.urls
                                                                      username:turnServer.username
                                                                    credential:turnServer.credential];

            [servers addObject:iceServer];
        }
    }
    
    NSArray *iceServers = [NSArray arrayWithArray:servers];
    return iceServers;
}

- (void)startPullingSignalingMessages
{
    [NCLog log:[NSString stringWithFormat:@"Start pulling internal signaling messages for token %@", _room.token]];

    _shouldStopPullingMessages = NO;
    _consecutivePullFailures = 0;
    _consecutiveSessionGoneFailures = 0;
    [self pullSignalingMessages];
}

- (void)stopPullingSignalingMessages
{
    _shouldStopPullingMessages = YES;
    [_pullSignalingMessagesTask cancel];
}

- (void)pullSignalingMessages
{
    _pullSignalingMessagesTask = [[NCAPIController sharedInstance] pullSignalingMessagesFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionBlock:^(NSArray<NSDictionary<NSString *,id> *> * _Nullable messages, OcsError * _Nullable error) {
        if (self->_shouldStopPullingMessages) {
            return;
        }

        if (error) {
            self->_consecutivePullFailures += 1;

            // A 404 means our session is gone server side, which polling cannot recover from
            if (error.responseStatusCode == 404) {
                self->_consecutiveSessionGoneFailures += 1;

                if (self->_consecutiveSessionGoneFailures >= kMaxConsecutiveSessionGoneFailures) {
                    [NCLog log:[NSString stringWithFormat:@"Internal signaling has no session for token %@ anymore, ending the call", self->_room.token]];

                    self->_shouldStopPullingMessages = YES;

                    if ([self.observer respondsToSelector:@selector(signalingControllerSessionExpired:)]) {
                        [self.observer signalingControllerSessionExpired:self];
                    }

                    return;
                }
            } else {
                self->_consecutiveSessionGoneFailures = 0;
            }

            // The request is only re-armed from here, so retrying immediately would busy loop
            NSTimeInterval delay = MIN(pow(2, MIN(self->_consecutivePullFailures, 4)), 16);

            [NCLog log:[NSString stringWithFormat:@"Could not pull internal signaling messages (failure %ld, status %ld), retrying in %.0fs", (long)self->_consecutivePullFailures, (long)error.responseStatusCode, delay]];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->_shouldStopPullingMessages) {
                    return;
                }

                [self pullSignalingMessages];
            });

            return;
        }

        self->_consecutivePullFailures = 0;
        self->_consecutiveSessionGoneFailures = 0;

        for (NSDictionary *message in messages) {
            if ([self.observer respondsToSelector:@selector(signalingController:didReceiveSignalingMessage:)]) {
                [self.observer signalingController:self didReceiveSignalingMessage:message];
            }
        }
        [self pullSignalingMessages];
    }];
}

- (void)sendSignalingMessage:(NCSignalingMessage *)message
{
    NSArray *messagesArray = [NSArray arrayWithObjects:[message messageDict], nil];
    NSString *JSONSerializedMessages = [self messagesJSONSerialization:messagesArray];
    
    if (!JSONSerializedMessages) {
        return;
    }

    [[NCAPIController sharedInstance] sendSignalingMessages:JSONSerializedMessages toRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] completionHandler:^(NSError *error) {
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
    if (!jsonData) {
        NSLog(@"Error serializing signaling message: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    return jsonString;
}

- (void)stopAllRequests
{
    [_getSignalingSettingsTask cancel];
    _getSignalingSettingsTask = nil;
    
    [self stopPullingSignalingMessages];
}

@end
