/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCSignalingController.h"

#import <WebRTC/RTCIceServer.h>

#import "NCAPIController.h"
#import "NCDatabaseManager.h"

#import "NextcloudTalk-Swift.h"

@interface NCSignalingController()
{
    NCRoom *_room;
    BOOL _shouldStopPullingMessages;
    SignalingSettings *_signalingSettings;
    NSURLSessionTask *_getSignalingSettingsTask;
    NSURLSessionTask *_pullSignalingMessagesTask;
}

@end

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
            [NCUtils log:[NSString stringWithFormat:@"Could not get signaling settings. Error: %@", error.description]];
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
    [NCUtils log:[NSString stringWithFormat:@"Start pulling internal signaling messages for token %@", _room.token]];

    _shouldStopPullingMessages = NO;
    [self pullSignalingMessages];
}

- (void)stopPullingSignalingMessages
{
    _shouldStopPullingMessages = YES;
    [_pullSignalingMessagesTask cancel];
}

- (void)pullSignalingMessages
{
    _pullSignalingMessagesTask = [[NCAPIController sharedInstance] pullSignalingMessagesFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *messages, NSError *error) {
        if (self->_shouldStopPullingMessages) {
            return;
        }
        
        id messagesObj = [[messages objectForKey:@"ocs"] objectForKey:@"data"];
        NSArray *messagesArray = [[NSArray alloc] init];
        
        // Check if messages array was parsed correctly
        if ([messagesObj isKindOfClass:[NSArray class]]) {
            messagesArray = messagesObj;
        }else if ([messagesObj isKindOfClass:[NSDictionary class]]) {
            messagesArray = [messagesObj allValues];
        }
        
        for (NSDictionary *message in messagesArray) {
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
    
    [[NCAPIController sharedInstance] sendSignalingMessages:JSONSerializedMessages toRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
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
