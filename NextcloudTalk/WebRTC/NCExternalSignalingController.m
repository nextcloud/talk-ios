/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCExternalSignalingController.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "WSMessage.h"

#import "NextcloudTalk-Swift.h"

static NSTimeInterval kInitialReconnectInterval = 1;
static NSTimeInterval kMaxReconnectInterval     = 16;
static NSTimeInterval kWebSocketTimeoutInterval = 15;

NSString * const NCExternalSignalingControllerDidUpdateParticipantsNotification         = @"NCExternalSignalingControllerDidUpdateParticipantsNotification";
NSString * const NCExternalSignalingControllerDidReceiveJoinOfParticipantNotification   = @"NCExternalSignalingControllerDidReceiveJoinOfParticipant";
NSString * const NCExternalSignalingControllerDidReceiveLeaveOfParticipantNotification  = @"NCExternalSignalingControllerDidReceiveLeaveOfParticipant";
NSString * const NCExternalSignalingControllerDidReceiveStartedTypingNotification       = @"NCExternalSignalingControllerDidReceiveStartedTypingNotification";
NSString * const NCExternalSignalingControllerDidReceiveStoppedTypingNotification       = @"NCExternalSignalingControllerDidReceiveStoppedTypingNotification";

@interface NCExternalSignalingController () <NSURLSessionWebSocketDelegate>

@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocket;
@property (nonatomic, strong) NSString* serverUrl;
@property (nonatomic, strong) NSString* ticket;
@property (nonatomic, strong) NSString* resumeId;
@property (nonatomic, strong) NSString* sessionId;
@property (nonatomic, strong) NSString* userId;
@property (nonatomic, strong) NSString* authenticationBackendUrl;
@property (nonatomic, assign) BOOL helloResponseReceived;
@property (nonatomic, assign) BOOL mcuSupport;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SignalingParticipant *>* participantsMap;
@property (nonatomic, strong) NSMutableArray* pendingMessages;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) WSMessage *helloMessage;
@property (nonatomic, strong) NSMutableArray *messagesWithCompletionBlocks;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@property (nonatomic, assign) NSInteger disconnectTime;

@end

@implementation NCExternalSignalingController

- (instancetype)initWithAccount:(TalkAccount *)account server:(NSString *)serverUrl andTicket:(NSString *)ticket
{
    self = [super init];
    if (self) {
        _account = account;
        _userId = _account.userId;
        _authenticationBackendUrl = [[NCAPIController sharedInstance] authenticationBackendUrlForAccount:_account];
        [self setServer:serverUrl andTicket:ticket];
    }
    return self;
}

- (BOOL)hasMCU
{
    return _mcuSupport;
}

- (NSString *)sessionId
{
    return _sessionId;
}

- (void)setServer:(NSString *)serverUrl andTicket:(NSString *)ticket
{
    _serverUrl = [self getWebSocketUrlForServer:serverUrl];
    _ticket = ticket;
    _reconnectInterval = kInitialReconnectInterval;
    _pendingMessages = [NSMutableArray new];
    
    [self connect];
}

- (NSString *)getWebSocketUrlForServer:(NSString *)serverUrl
{
    NSString *wsUrl = [serverUrl copy];
    
    // Change to websocket protocol
    wsUrl = [wsUrl stringByReplacingOccurrencesOfString:@"https://" withString:@"wss://"];
    wsUrl = [wsUrl stringByReplacingOccurrencesOfString:@"http://" withString:@"ws://"];
    // Remove trailing slash
    if([wsUrl hasSuffix:@"/"]) {
        wsUrl = [wsUrl substringToIndex:[wsUrl length] - 1];
    }
    // Add spreed endpoint
    wsUrl = [wsUrl stringByAppendingString:@"/spreed"];
    
    return wsUrl;
}

#pragma mark - WebSocket connection

- (void)connect
{
    [self connect:NO];
}

- (void)forceConnect
{
    [self connect:YES];
}

- (void)connect:(BOOL)force
{
    BOOL forceConnect = force || [NCRoomsManager sharedInstance].callViewController;
    // Do not try to connect if the app is running in the background (unless forcing a connection or in a call)
    if (!forceConnect && [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
        [NCUtils log:@"Trying to create websocket connection while app is in the background"];
        _disconnected = YES;
        return;
    }

    [self invalidateReconnectionTimer];

    _disconnected = NO;
    _messageId = 1;
    _messagesWithCompletionBlocks = [NSMutableArray new];
    _helloResponseReceived = NO;

    [NCUtils log:[NSString stringWithFormat:@"Connecting to: %@", _serverUrl]];
    NSURL *url = [NSURL URLWithString:_serverUrl];

    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@",
                           [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];

    NSURLSession *wsSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
    NSMutableURLRequest *wsRequest = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:kWebSocketTimeoutInterval];
    [wsRequest setValue:userAgent forHTTPHeaderField:@"User-Agent"];

    if (self.resumeId) {
        NSTimeInterval currentTimestamp = [[NSDate date] timeIntervalSince1970];

        // We are only allowed to resume a session 30s after disconnect
        if (!self.disconnectTime || (currentTimestamp - self.disconnectTime) >= 30) {
            [NCUtils log:@"We have a resumeId, but we disconnected outside of the 30s resume window. Connecting without resumeId."];
            self.resumeId = nil;
        }
    }

    NSURLSessionWebSocketTask *webSocket = [wsSession webSocketTaskWithRequest:wsRequest];
    _webSocket = webSocket;
    
    [_webSocket resume];

    [self receiveMessage];
}

- (void)reconnect
{
    // Note: Make sure to call reconnect only from the main-thread!
    if (_reconnectTimer) {
        return;
    }

    [NCUtils log:[NSString stringWithFormat:@"Reconnecting to: %@", _serverUrl]];

    [self resetWebSocket];

    // Execute completion blocks on all messages
    for (WSMessage *message in self->_messagesWithCompletionBlocks) {
        [message executeCompletionBlockWithStatus:SendMessageSocketError];
    }

    [self setReconnectionTimer];
}

- (void)forceReconnect
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_resumeId = nil;
        self->_currentRoom = nil;
        [self reconnect];
    });
}

- (void)forceReconnectForRejoin
{
    // In case we force reconnect in order to rejoin the call again, we need to keep the currently joined room.
    // In `helloResponseReceived` we determine that we were in a room and that the sessionId changed, in that case
    // we trigger a re-join in `NCRoomsManager` which takes care of re-joining.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *byeDict = @{
            @"type": @"bye",
            @"bye": @{}
        };

        // Close our current session. Don't leave the room, as that would defeat the above mentioned purpose
        [self sendMessage:byeDict withCompletionBlock:^(NSURLSessionWebSocketTask *task, NCExternalSignalingSendMessageStatus status) {
            self->_resumeId = nil;
            [self reconnect];
        }];
    });
}

- (void)disconnect
{
    [NCUtils log:[NSString stringWithFormat:@"Disconnecting from: %@", _serverUrl]];

    self.disconnectTime = [[NSDate date] timeIntervalSince1970];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self invalidateReconnectionTimer];
        [self resetWebSocket];
    });
}

- (void)resetWebSocket
{
    [_webSocket cancel];
    _webSocket = nil;
    _helloResponseReceived = NO;
    [_helloMessage ignoreCompletionBlock];
    _helloMessage = nil;
    _disconnected = YES;
}

- (void)setReconnectionTimer
{
    [self invalidateReconnectionTimer];
    // Wiggle interval a little bit to prevent all clients from connecting
    // simultaneously in case the server connection is interrupted.
    NSInteger interval = _reconnectInterval - (_reconnectInterval / 2) + arc4random_uniform((int)_reconnectInterval);
    NSLog(@"Reconnecting in %ld", (long)interval);
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(connect) userInfo:nil repeats:NO];
    });
    _reconnectInterval = _reconnectInterval * 2;
    if (_reconnectInterval > kMaxReconnectInterval) {
        _reconnectInterval = kMaxReconnectInterval;
    }
}

- (void)invalidateReconnectionTimer
{
    [_reconnectTimer invalidate];
    _reconnectTimer = nil;
}

#pragma mark - WebSocket messages

- (void)sendMessage:(NSDictionary *)jsonDict withCompletionBlock:(SendMessageCompletionBlock)block
{
    WSMessage *wsMessage = [[WSMessage alloc] initWithMessage:jsonDict withCompletionBlock:block];

    // Add message as pending message if websocket is not connected
    if (!_helloResponseReceived && !wsMessage.isHelloMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (wsMessage.isJoinMessage) {
                // We join a new room, so any message which wasn't send by now is not relevant for the new room anymore
                self->_pendingMessages = [NSMutableArray new];
            }

            [NCUtils log:@"Trying to send message before we received a hello response -> adding to pendingMessages"];
            [self->_pendingMessages addObject:wsMessage];
        });

        return;
    }

    [self sendMessage:wsMessage];
}

- (void)sendMessage:(WSMessage *)wsMessage
{
    // Assign messageId and timeout to messages with completionBlocks
    if (wsMessage.completionBlock) {
        NSString *messageIdString = [NSString stringWithFormat: @"%ld", (long)_messageId++];
        wsMessage.messageId = messageIdString;

        if (wsMessage.isHelloMessage) {
            [_helloMessage ignoreCompletionBlock];
            _helloMessage = wsMessage;
        } else {
            [_messagesWithCompletionBlocks addObject:wsMessage];
        }
    }

    if (!wsMessage.webSocketMessage) {
        NSLog(@"Error creating websocket message");
        [wsMessage executeCompletionBlockWithStatus:SendMessageApplicationError];
        return;
    }

    [wsMessage sendMessageWithWebSocket:_webSocket];
}

- (void)sendHelloMessage
{
    NSDictionary *helloDict = @{
                                @"type": @"hello",
                                @"hello": @{
                                        @"version": @"1.0",
                                        @"auth": @{
                                                @"url": _authenticationBackendUrl,
                                                @"params": @{
                                                        @"userid": _userId,
                                                        @"ticket": _ticket
                                                        }
                                                }
                                        }
                                };
    // Try to resume session
    if (_resumeId) {
        helloDict = @{
                      @"type": @"hello",
                      @"hello": @{
                              @"version": @"1.0",
                              @"resumeid": _resumeId
                              }
                      };
    }

    [NCUtils log:@"Sending hello message"];
    
    [self sendMessage:helloDict withCompletionBlock:^(NSURLSessionWebSocketTask *task, NCExternalSignalingSendMessageStatus status) {
        if (status == SendMessageSocketError && task == self->_webSocket) {
            [NCUtils log:[NSString stringWithFormat:@"Reconnecting from sendHelloMessage"]];
            [self reconnect];
        }
    }];
}

- (void)helloResponseReceived:(NSDictionary *)messageDict
{
    _helloResponseReceived = YES;

    [NCUtils log:[NSString stringWithFormat:@"Hello received with %ld pending messages", _pendingMessages.count]];

    NSString *messageId = [messageDict objectForKey:@"id"];
    [self executeCompletionBlockForMessageId:messageId withStatus:SendMessageSuccess];

    NSDictionary *helloDict = [messageDict objectForKey:@"hello"];
    _resumeId = [helloDict objectForKey:@"resumeid"];

    NSString *newSessionId = [helloDict objectForKey:@"sessionid"];
    BOOL sessionChanged = _sessionId && ![_sessionId isEqualToString:newSessionId];
    _sessionId = newSessionId;

    NSArray *serverFeatures = [[helloDict objectForKey:@"server"] objectForKey:@"features"];
    for (NSString *feature in serverFeatures) {
        if ([feature isEqualToString:@"mcu"]) {
            _mcuSupport = YES;
        }
    }

    NSString *serverVersion = [[helloDict objectForKey:@"server"] objectForKey:@"version"];
    dispatch_async(dispatch_get_main_queue(), ^{
        BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateSignalingVersionTransaction" expirationHandler:nil];
        [[NCDatabaseManager sharedInstance] setExternalSignalingServerVersion:serverVersion forAccountId:self->_account.accountId];

        // Send pending messages
        for (WSMessage *wsMessage in self->_pendingMessages) {
            [self sendMessage:wsMessage];
        }
        self->_pendingMessages = [NSMutableArray new];

        [bgTask stopBackgroundTask];
    });
    
    // Re-join if user was in a room
    if (_currentRoom && sessionChanged) {
        sessionChanged = NO;
        [self.delegate externalSignalingControllerWillRejoinCall:self];

        [[NCRoomsManager sharedInstance] rejoinRoomForCall:_currentRoom completionBlock:^(NSString * _Nullable sessionId, NCRoom * _Nullable room, NSError * _Nullable error, NSInteger statusCode, NSString * _Nullable statusReason) {
            [self.delegate externalSignalingControllerShouldRejoinCall:self];
        }];
    }
}

- (void)errorResponseReceived:(NSDictionary *)messageDict
{
    NSString *errorCode = [[messageDict objectForKey:@"error"] objectForKey:@"code"];
    NSString *messageId = [messageDict objectForKey:@"id"];

    [NCUtils log:[NSString stringWithFormat:@"Received error response %@", errorCode]];

    if ([errorCode isEqualToString:@"no_such_session"] || [errorCode isEqualToString:@"too_many_requests"]) {
        // We could not resume the previous session, but the websocket is still alive -> resend the hello message without a resumeId
        _resumeId = nil;
        [self sendHelloMessage];

        return;
    } else if ([errorCode isEqualToString:@"already_joined"]) {
        // We already joined this room on the signaling server
        NSDictionary *details = [[messageDict objectForKey:@"error"] objectForKey:@"details"];
        NSString *roomId = [[details objectForKey:@"room"] objectForKey:@"roomid"];

        // If we are aware that we were in this room before, we should treat this as a success
        if ([_currentRoom isEqualToString:roomId]) {
            [self executeCompletionBlockForMessageId:messageId withStatus:SendMessageSuccess];

            return;
        }
    }

    [self executeCompletionBlockForMessageId:messageId withStatus:SendMessageApplicationError];
}

- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId withFederation:(NSDictionary *)federationDict withCompletionBlock:(JoinRoomExternalSignalingCompletionBlock)block
{

    if (_disconnected) {
        [NCUtils log:[NSString stringWithFormat:@"Joining room %@, but the websocket is disconnected.", roomId]];
    }

    if (_webSocket == nil) {
        [NCUtils log:[NSString stringWithFormat:@"Joining room %@, but the websocket is nil.", roomId]];
    }

    NSDictionary *messageDict = @{
                                  @"type": @"room",
                                  @"room": @{
                                          @"roomid": roomId,
                                          @"sessionid": sessionId
                                          }
                                  };

    if (federationDict) {
        messageDict = @{
            @"type": @"room",
            @"room": @{
                @"roomid": roomId,
                @"sessionid": sessionId,
                @"federation": federationDict
            }
        };
    }

    [self sendMessage:messageDict withCompletionBlock:^(NSURLSessionWebSocketTask *task, NCExternalSignalingSendMessageStatus status) {
        if (status == SendMessageSocketError && task == self->_webSocket) {
            // Reconnect if this is still the same socket we tried to send the message on
            [NCUtils log:[NSString stringWithFormat:@"Reconnect from joinRoom"]];

            // When we failed to join a room, we shouldn't try to resume a session but instead do a force reconnect
            [self forceReconnect];
        }

        if (block) {
            NSError *error = nil;
            
            if (status != SendMessageSuccess) {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            }

            block(error);
        }
    }];
}

- (void)leaveRoom:(NSString *)roomId
{
    if ([_currentRoom isEqualToString:roomId]) {
        _currentRoom = nil;
        [self joinRoom:@"" withSessionId:@"" withFederation:nil withCompletionBlock:nil];
    } else {
        NSLog(@"External signaling: Not leaving because it's not room we joined");
    }
}

- (void)sendCallMessage:(NCSignalingMessage *)message
{
    NSDictionary *messageDict = @{
                                  @"type": @"message",
                                  @"message": @{
                                          @"recipient": @{
                                                  @"type": @"session",
                                                  @"sessionid": message.to
                                                  },
                                          @"data": [message functionDict]
                                          }
                                  };
    
    [self sendMessage:messageDict withCompletionBlock:nil];
}

- (void)sendSendOfferMessageWithSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType
{
    NSDictionary *messageDict = @{
        @"type": @"message",
        @"message": @{
            @"recipient": @{
                @"type": @"session",
                @"sessionid": sessionId
            },
            @"data": @{
                @"type": @"sendoffer",
                @"roomType": roomType
            }
        }
    };

    [self sendMessage:messageDict withCompletionBlock:nil];
}

- (void)sendRoomMessageOfType:(NSString *)messageType andRoomType:(NSString *)roomType
{
    NSDictionary *messageDict = @{
        @"type": @"message",
        @"message": @{
            @"recipient": @{
                @"type": @"room"
            },
            @"data": @{
                @"type": messageType,
                @"roomType": roomType
            }
        }
    };

    [self sendMessage:messageDict withCompletionBlock:nil];
}

- (void)requestOfferForSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType
{
    NSDictionary *messageDict = @{
                                  @"type": @"message",
                                  @"message": @{
                                          @"recipient": @{
                                                  @"type": @"session",
                                                  @"sessionid": sessionId
                                                  },
                                          @"data": @{
                                                  @"type": @"requestoffer",
                                                  @"roomType": roomType
                                                  }
                                          }
                                  };
    
    [self sendMessage:messageDict withCompletionBlock:nil];
}

- (void)roomMessageReceived:(NSDictionary *)messageDict
{
    NSString *newRoomId = [[messageDict objectForKey:@"room"] objectForKey:@"roomid"];

    // Only reset the participant map when the room actually changed
    // Otherwise we would loose participant information for example when a recording is started
    if (![_currentRoom isEqualToString:newRoomId]) {
        _participantsMap = [NSMutableDictionary new];
        _currentRoom = newRoomId;
    }
    
    NSString *messageId = [messageDict objectForKey:@"id"];
    [self executeCompletionBlockForMessageId:messageId withStatus:SendMessageSuccess];
}

- (void)eventMessageReceived:(NSDictionary *)eventDict
{
    NSString *eventTarget = [eventDict objectForKey:@"target"];
    if ([eventTarget isEqualToString:@"room"]) {
        [self processRoomEvent:eventDict];
    } else if ([eventTarget isEqualToString:@"roomlist"]) {
        [self processRoomListEvent:eventDict];
    } else if ([eventTarget isEqualToString:@"participants"]) {
        [self processRoomParticipantsEvent:eventDict];
    } else {
        NSLog(@"Unsupported event target: %@", eventDict);
    }
}

- (void)processRoomEvent:(NSDictionary *)eventDict
{
    NSString *eventType = [eventDict objectForKey:@"type"];
    if ([eventType isEqualToString:@"join"]) {
        NSArray *joins = [eventDict objectForKey:@"join"];
        for (NSDictionary *participantDict in joins) {
            SignalingParticipant *participant = [[SignalingParticipant alloc] initWithJoinDictionary:participantDict];

            if (!participant.isFederated && [participant.userId isEqualToString:_userId]) {
                NSLog(@"App user joined room.");
            } else {
                NSLog(@"Participant joined room.");

                // Only notify if another participant joined the room and not ourselves from a different device
                NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];

                if (_currentRoom && participant.signalingSessionId){
                    [userInfo setObject:_currentRoom forKey:@"roomToken"];
                    [userInfo setObject:participant.signalingSessionId forKey:@"sessionId"];
                }

                [[NSNotificationCenter defaultCenter] postNotificationName:NCExternalSignalingControllerDidReceiveJoinOfParticipantNotification
                                                                    object:self
                                                                  userInfo:userInfo];
            }

            [_participantsMap setObject:participant forKey:participant.signalingSessionId];
        }
    } else if ([eventType isEqualToString:@"leave"]) {
        NSArray *leftSessions = [eventDict objectForKey:@"leave"];
        for (NSString *sessionId in leftSessions) {
            SignalingParticipant *participant = [self getParticipantFromSessionId:sessionId];

            [_participantsMap removeObjectForKey:sessionId];

            if ([participant.signalingSessionId isEqualToString:_sessionId] || (!participant.isFederated && [participant.userId isEqualToString:_userId])) {
                // Ignore own session
                continue;
            }

            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];

            if (_currentRoom && sessionId){
                [userInfo setObject:_currentRoom forKey:@"roomToken"];
                [userInfo setObject:sessionId forKey:@"sessionId"];

                if (participant.userId) {
                    [userInfo setObject:participant.userId forKey:@"userId"];
                }
            }

            [[NSNotificationCenter defaultCenter] postNotificationName:NCExternalSignalingControllerDidReceiveLeaveOfParticipantNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    } else if ([eventType isEqualToString:@"message"]) {
        [self processRoomMessageEvent:[eventDict objectForKey:@"message"]];
    } else if ([eventType isEqualToString:@"switchto"]) {
        [self processSwitchToMessageEvent:[eventDict objectForKey:@"switchto"]];
    } else {
        NSLog(@"Unknown room event: %@", eventDict);
    }
}

- (void)processRoomMessageEvent:(NSDictionary *)messageDict
{
    NSString *messageType = [[messageDict objectForKey:@"data"] objectForKey:@"type"];
    if ([messageType isEqualToString:@"chat"]) {
        NSLog(@"Chat message received.");
    } else if ([messageType isEqualToString:@"recording"]) {
        [self.delegate externalSignalingController:self didReceivedSignalingMessage:messageDict];
    } else {
        NSLog(@"Unknown room message type: %@", messageDict);
    }
}

- (void)processSwitchToMessageEvent:(NSDictionary *)messageDict
{
    NSString *roomToken = [messageDict objectForKey:@"roomid"];
    if (roomToken.length > 0) {
        [self.delegate externalSignalingController:self shouldSwitchToCall:roomToken];
    } else {
        NSLog(@"Unknown switchTo message: %@", messageDict);
    }
}

- (void)processRoomListEvent:(NSDictionary *)eventDict
{
    NSLog(@"Refresh room list.");
}

- (void)processRoomParticipantsEvent:(NSDictionary *)eventDict
{
    NSString *eventType = [eventDict objectForKey:@"type"];
    if ([eventType isEqualToString:@"update"]) {
        //NSLog(@"Participant list changed: %@", [eventDict objectForKey:@"update"]);
        NSDictionary *updateDict = [eventDict objectForKey:@"update"];
        [self.delegate externalSignalingController:self didReceivedParticipantListMessage:updateDict];

        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        NSString *roomToken = [updateDict objectForKey:@"roomid"];
        if (roomToken){
            [userInfo setObject:roomToken forKey:@"roomToken"];
        }
        NSArray *users = [updateDict objectForKey:@"users"];
        if (users) {
            for (NSDictionary *userDict in users) {
                NSString *sessionId = [userDict objectForKey:@"sessionId"];
                SignalingParticipant *participant = [self getParticipantFromSessionId:sessionId];

                if (participant) {
                    [participant updateWithUpdateDictionary:userDict];
                }
            }

            [userInfo setObject:users forKey:@"users"];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NCExternalSignalingControllerDidUpdateParticipantsNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else {
        NSLog(@"Unknown room event: %@", eventDict);
    }
}

- (void)messageReceived:(NSDictionary *)messageDict
{
    NSString *messageType = [[messageDict objectForKey:@"data"] objectForKey:@"type"];
    if ([messageType isEqualToString:@"startedTyping"] || [messageType isEqualToString:@"stoppedTyping"]) {
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];

        NSDictionary *sender = [messageDict objectForKey:@"sender"];
        NSString *fromSession = [sender objectForKey:@"sessionid"];
        NSString *fromUser = [sender objectForKey:@"userid"];

        if (_currentRoom && fromSession){
            [userInfo setObject:_currentRoom forKey:@"roomToken"];
            [userInfo setObject:fromSession forKey:@"sessionId"];

            if (fromUser) {
                [userInfo setObject:fromUser forKey:@"userId"];
            }

            SignalingParticipant *participant = [_participantsMap objectForKey:fromSession];
            if (participant) {
                BOOL isFederated = participant.isFederated;
                [userInfo setObject:@(isFederated) forKey:@"isFederated"];

                if (participant.displayName != nil) {
                    [userInfo setObject:participant.displayName forKey:@"displayName"];
                }
            }
        }

        if ([messageType isEqualToString:@"startedTyping"]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCExternalSignalingControllerDidReceiveStartedTypingNotification
                                                                object:self
                                                              userInfo:userInfo];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:NCExternalSignalingControllerDidReceiveStoppedTypingNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    } else {
        [self.delegate externalSignalingController:self didReceivedSignalingMessage:messageDict];
    }
}

#pragma mark - Completion blocks

- (void)executeCompletionBlockForMessageId:(NSString *)messageId withStatus:(NCExternalSignalingSendMessageStatus)status
{
    if (!messageId) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self->_helloMessage.messageId isEqualToString:messageId]) {
            [self->_helloMessage executeCompletionBlockWithStatus:status];
            self->_helloMessage = nil;
            return;
        }

        for (WSMessage *message in self->_messagesWithCompletionBlocks) {
            if ([messageId isEqualToString:message.messageId]) {
                [message executeCompletionBlockWithStatus:status];
                [self->_messagesWithCompletionBlocks removeObject:message];
                break;
            }
        }
    });
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (webSocketTask != self->_webSocket) {
            return;
        }


        [NCUtils log:@"WebSocket Connected!"];
        self->_reconnectInterval = kInitialReconnectInterval;
        [self sendHelloMessage];
    });
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (webSocketTask != self->_webSocket) {
            return;
        }

        [NCUtils log:[NSString stringWithFormat:@"WebSocket didCloseWithCode:%ld reason:%@", (long)closeCode, reason]];
        [self reconnect];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task != self->_webSocket) {
            return;
        }

        if (error) {
            [NCUtils log:[NSString stringWithFormat:@"WebSocket session didCompleteWithError: %@", error.description]];
            [self reconnect];
        }
    });
}

- (void)receiveMessage {
    __weak NCExternalSignalingController *weakSelf = self;
    __block NSURLSessionWebSocketTask *receivingWebSocket = _webSocket;

    [_webSocket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (!error) {
            NSData *messageData = message.data;
            NSString *messageString = message.string;

            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                messageData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
            }

            if (message.type == NSURLSessionWebSocketMessageTypeData) {
                messageString = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];
            }

            //NSLog(@"WebSocket didReceiveMessage: %@", messageString);
            NSDictionary *messageDict = [weakSelf getWebSocketMessageFromJSONData:messageData];
            NSString *messageType = [messageDict objectForKey:@"type"];
            if ([messageType isEqualToString:@"hello"]) {
                [weakSelf helloResponseReceived:messageDict];
            } else if ([messageType isEqualToString:@"error"]) {
                [weakSelf errorResponseReceived:messageDict];
            } else if ([messageType isEqualToString:@"room"]) {
                [weakSelf roomMessageReceived:messageDict];
            } else if ([messageType isEqualToString:@"event"]) {
                [weakSelf eventMessageReceived:[messageDict objectForKey:@"event"]];
            } else if ([messageType isEqualToString:@"message"]) {
                [weakSelf messageReceived:[messageDict objectForKey:@"message"]];
            } else if ([messageType isEqualToString:@"control"]) {
                [weakSelf messageReceived:[messageDict objectForKey:@"control"]];
            }
            
            // Completion block for messageId should have been handled already at this point
            NSString *messageId = [messageDict objectForKey:@"id"];
            [weakSelf executeCompletionBlockForMessageId:messageId withStatus:SendMessageApplicationError];

            [weakSelf receiveMessage];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Only try to reconnect if the webSocket is still the one we tried to receive a message on
                if (receivingWebSocket != weakSelf.webSocket) {
                    return;
                }

                [NCUtils log:[NSString stringWithFormat:@"WebSocket receiveMessageWithCompletionHandler error %@", error.description]];
                [weakSelf reconnect];
            });
        }
    }];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }
}

#pragma mark - Utils

- (SignalingParticipant *)getParticipantFromSessionId:(NSString *)sessionId
{
    return [_participantsMap objectForKey:sessionId];
}

- (NSMutableDictionary *)getParticipantMap
{
    return _participantsMap;
}

- (NSDictionary *)getWebSocketMessageFromJSONData:(NSData *)jsonData
{
    NSError *error;
    NSDictionary* messageDict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                options:kNilOptions
                                                                  error:&error];
    if (!messageDict) {
        NSLog(@"Error parsing websocket message: %@", error);
    }
    
    return messageDict;
}

@end
