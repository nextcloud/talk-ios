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

@interface NCExternalSignalingController () <SRWebSocketDelegate>

@property (nonatomic, strong) SRWebSocket *webSocket;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic, strong) NSString* serverUrl;
@property (nonatomic, strong) NSString* ticket;
@property (nonatomic, strong) NSString* resumeId;
@property (nonatomic, assign) BOOL mcuSupport;
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
    NSLog(@"Reconnecting...");
    _reconnecting = YES;
    [self connect];
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
