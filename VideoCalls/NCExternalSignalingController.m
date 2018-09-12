//
//  NCExternalSignalingController.m
//  VideoCalls
//
//  Created by Ivan Sein on 07.09.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCExternalSignalingController.h"

#import "SRWebSocket.h"
#import "NCAPIController.h"
#import "NCSettingsController.h"

static NSTimeInterval kInitialReconnectInterval = 1;
static NSTimeInterval kMaxReconnectInterval     = 16;

@interface NCExternalSignalingController () <SRWebSocketDelegate>

@property (nonatomic, strong) SRWebSocket *webSocket;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic, strong) NSString* serverUrl;
@property (nonatomic, strong) NSString* ticket;
@property (nonatomic, strong) NSString* resumeId;
@property (nonatomic, assign) BOOL mcuSupport;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, strong) NSTimer *reconnectTimer;
@property (nonatomic, assign) BOOL reconnecting;

@end

@implementation NCExternalSignalingController

+ (NCExternalSignalingController *)sharedInstance
{
    static dispatch_once_t once;
    static NCExternalSignalingController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL)isEnabled
{
    return (_serverUrl) ? YES : NO;
}

- (void)setServer:(NSString *)serverUrl andTicket:(NSString *)ticket
{
    _serverUrl = [self getWebSocketUrlForServer:serverUrl];
    _ticket = ticket;
    _processingQueue = dispatch_queue_create("com.nextcloud.Talk.websocket.processing", DISPATCH_QUEUE_SERIAL);
    _reconnectInterval = kInitialReconnectInterval;
    
    [self connect];
}

- (NSString *)getWebSocketUrlForServer:(NSString *)serverUrl
{
    NSString *wsUrl = [serverUrl copy];
    
    // Change to websocket protocol
    [wsUrl stringByReplacingOccurrencesOfString:@"https://" withString:@"wss://"];
    [wsUrl stringByReplacingOccurrencesOfString:@"http://" withString:@"ws://"];
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
    [self invalidateReconnectionTimer];
    NSLog(@"Connecting to: %@",  _serverUrl);
    NSURL *url = [NSURL URLWithString:_serverUrl];
    NSURLRequest *wsRequest = [[NSURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60];
    SRWebSocket *webSocket = [[SRWebSocket alloc] initWithURLRequest:wsRequest protocols:@[] allowsUntrustedSSLCertificates:YES];
    [webSocket setDelegateDispatchQueue:self.processingQueue];
    webSocket.delegate = self;
    _webSocket = webSocket;
    
    [_webSocket open];
}

- (void)reconnect
{
    if (_reconnectTimer) {
        return;
    }
    
    [_webSocket close];
    _webSocket = nil;
    _reconnecting = YES;
    
    [self setReconnectionTimer];
}

- (void)setReconnectionTimer
{
    [self invalidateReconnectionTimer];
    // Wiggle interval a little bit to prevent all clients from connecting
    // simultaneously in case the server connection is interrupted.
    NSInteger interval = _reconnectInterval - (_reconnectInterval / 2) + arc4random_uniform((int)_reconnectInterval);
    NSLog(@"Reconnecting in %ld", (long)interval);
    dispatch_async(dispatch_get_main_queue(), ^{
        _reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(connect) userInfo:nil repeats:NO];
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

- (void)sendHello
{
    NSDictionary *helloDict = @{
                                @"type": @"hello",
                                @"hello": @{
                                        @"version": @"1.0",
                                        @"auth": @{
                                                @"url": [[NCAPIController sharedInstance] authenticationBackendUrl],
                                                @"params": @{
                                                        @"userid": [NCSettingsController sharedInstance].ncUserId,
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
    
    NSString *jsonString = [self createWebSocketMessage:helloDict];
    if (!jsonString) {
        NSLog(@"Error creating hello message");
        return;
    }
    
    [_webSocket send:jsonString];
}

- (void)helloResponseReceived:(NSDictionary *)helloDict
{
    _resumeId = [helloDict objectForKey:@"resumeid"];
    // Get server features
}

- (void)errorResponseReceived:(NSDictionary *)errorDict
{
    NSString *errorCode = [errorDict objectForKey:@"code"];
    if ([errorCode isEqualToString:@"no_such_session"]) {
        _resumeId = nil;
        [self reconnect];
    }
}

- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId
{
    NSDictionary *messageDict = @{
                                  @"type": @"room",
                                  @"room": @{
                                          @"roomid": roomId,
                                          @"sessionid": sessionId
                                          }
                                  };
    
    NSString *jsonString = [self createWebSocketMessage:messageDict];
    if (!jsonString) {
        NSLog(@"Error creating join message");
        return;
    }
    
    [_webSocket send:jsonString];
}

- (void)leaveRoom:(NSString *)roomId withSessionId:(NSString *)sessionId
{
    [self joinRoom:@"" withSessionId:sessionId];
}

- (void)joinResponseReceived:(NSDictionary *)joinDict
{
    NSLog(@"Join response received");
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    if (webSocket == _webSocket) {
        NSLog(@"WebSocket Connected!");
        _reconnectInterval = kInitialReconnectInterval;
        [self sendHello];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)messageData
{
    if (webSocket == _webSocket) {
        NSLog(@"WebSocket didReceiveMessage: %@", messageData);
        NSData *data = [messageData dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *messageDict = [self getWebSocketMessageFromJSONData:data];
        NSString *messageType = [messageDict objectForKey:@"type"];
        if ([messageType isEqualToString:@"hello"]) {
            [self helloResponseReceived:[messageDict objectForKey:@"hello"]];
        } else if ([messageType isEqualToString:@"error"]) {
            [self errorResponseReceived:[messageDict objectForKey:@"error"]];
        }
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    if (webSocket == _webSocket) {
        NSLog(@"WebSocket didFailWithError: %@", error);
        [self reconnect];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    if (webSocket == _webSocket) {
        NSLog(@"WebSocket didCloseWithCode:%ld reason:%@", (long)code, reason);
        [self reconnect];
    }
}

#pragma mark - Utils

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

- (NSString *)createWebSocketMessage:(NSDictionary *)message
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message
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
