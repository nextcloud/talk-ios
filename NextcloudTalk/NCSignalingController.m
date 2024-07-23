/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCSignalingController.h"

#import <WebRTC/RTCIceServer.h>

#import "NCAPIController.h"
#import "NCDatabaseManager.h"

@interface NCSignalingController()
{
    NCRoom *_room;
    BOOL _shouldStopPullingMessages;
    NSDictionary *_signalingSettings;
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
        [self getSignalingSettings];
    }
    return self;
}

- (void)dealloc
{
    NSLog(@"NCSignalingController dealloc");
}

- (void)getSignalingSettings
{
    _getSignalingSettingsTask = [[NCAPIController sharedInstance] getSignalingSettingsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSDictionary *settings, NSError *error) {
        if (error) {
            //TODO: Error handling
            NSLog(@"Error getting signaling settings.");
        }
        
        if (settings) {
            self->_signalingSettings = [[settings objectForKey:@"ocs"] objectForKey:@"data"];
        }
    }];
}

- (NSArray *)getIceServers
{
    NSMutableArray *servers = [[NSMutableArray alloc] init];
    NSInteger signalingAPIVersion = [[NCAPIController sharedInstance] signalingAPIVersionForAccount:[[NCDatabaseManager sharedInstance] activeAccount]];
    
    if (_signalingSettings) {
        NSArray *stunServers = [_signalingSettings objectForKey:@"stunservers"];
        for (NSDictionary *stunServer in stunServers) {
            NSArray *stunURLs = nil;
            if (signalingAPIVersion >= APIv3) {
                stunURLs = [stunServer objectForKey:@"urls"];
            } else {
                NSString *stunURL = [stunServer objectForKey:@"url"];
                stunURLs = @[stunURL];
            }
            RTCIceServer *iceServer = [[RTCIceServer alloc] initWithURLStrings:stunURLs
                                                                     username:@""
                                                                   credential:@""];
            [servers addObject:iceServer];
        }
        NSArray *turnServers = [_signalingSettings objectForKey:@"turnservers"];
        for (NSDictionary *turnServer in turnServers) {
            NSArray *turnURLs = nil;
            if (signalingAPIVersion >= APIv3) {
                turnURLs = [turnServer objectForKey:@"urls"];
            } else {
                turnURLs = [turnServer objectForKey:@"url"];
            }
            NSString *turnUserName = [turnServer objectForKey:@"username"];
            NSString *turnCredential = [turnServer objectForKey:@"credential"];
            RTCIceServer *iceServer = [[RTCIceServer alloc] initWithURLStrings:turnURLs
                                                                      username:turnUserName
                                                                    credential:turnCredential];
            [servers addObject:iceServer];
        }
    }
    
    NSArray *iceServers = [NSArray arrayWithArray:servers];
    return iceServers;
}

- (void)startPullingSignalingMessages
{
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
