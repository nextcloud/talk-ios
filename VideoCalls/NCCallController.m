//
//  NCCallController.m
//  VideoCalls
//
//  Created by Ivan Sein on 02.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCCallController.h"

#import <WebRTC/RTCConfiguration.h>
#import <WebRTC/RTCDataChannelConfiguration.h>
#import <WebRTC/RTCMediaConstraints.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCPeerConnectionFactory.h>
#import <WebRTC/RTCAudioTrack.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCVideoCapturer.h>
#import <WebRTC/RTCCameraVideoCapturer.h>
#import "NCAPIController.h"
#import "NCSignalingController.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface NCCallController () <NCPeerConnectionDelegate, NCSignalingControllerObserver>

@property (nonatomic, assign) BOOL leavingCall;
@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, strong) NSArray *usersInRoom;;
@property (nonatomic, strong) RTCMediaStream *localStream;
@property (nonatomic, strong) RTCAudioTrack *localAudioTrack;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong) NCSignalingController *signalingController;

@end

@implementation NCCallController

- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate
{
    self = [super init];
    
    if (self) {
        _delegate = delegate;
        _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] init];
        _connectionsDict = [[NSMutableDictionary alloc] init];
        _usersInRoom = [[NSArray alloc] init];
        
        _signalingController = [[NCSignalingController alloc] init];
        _signalingController.observer = self;
    }
    
    return self;
}

- (void)startCall
{
    [[NCAPIController sharedInstance] joinRoom:_room withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger errorCode) {
        if (!error) {
            self.userSessionId = sessionId;
            [[NCAPIController sharedInstance] joinCall:_room withCompletionBlock:^(NSError *error, NSInteger errorCode) {
                if (!error) {
                    [self createLocalMedia];
                    [self.delegate callControllerDidJoinCall:self];
                    
                    [self startPingCall];
                    [_signalingController startPullingSignalingMessages];
                } else {
                    NSLog(@"Could not join call. Error: %@", error.description);
                }
            }];
        } else {
            NSLog(@"Could not join room. Error: %@", error.description);
        }
    }];
}

- (void)leaveCall
{
    _leavingCall = YES;
    
    for (NCPeerConnection *peerConnectionWrapper in [_connectionsDict allValues]) {
        [peerConnectionWrapper close];
    }
    
    [_localStream removeAudioTrack:_localAudioTrack];
    [_localStream removeVideoTrack:_localVideoTrack];
    _localStream = nil;
    _localAudioTrack = nil;
    _localVideoTrack = nil;
    _peerConnectionFactory = nil;
    _connectionsDict = nil;
    
    [[NCAPIController sharedInstance] leaveCall:_room withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        if (!error) {
            [self stopPingCall];
            [_signalingController stopPullingSignalingMessages];
            [[NCAPIController sharedInstance] exitRoom:_room withCompletionBlock:^(NSError *error, NSInteger errorCode) {
                if (!error) {
                    [self.delegate callControllerDidEndCall:self];
                } else {
                    NSLog(@"Could not leave room. Error: %@", error.description);
                }
                
            }];
        } else {
            NSLog(@"Could not leave call. Error: %@", error.description);
        }
    }];
}

- (void)dealloc
{
    NSLog(@"NCCallController dealloc");
}

- (void)toggleCamera
{
    // TODO
}

- (BOOL)isVideoEnabled
{
    RTCVideoTrack *videoTrack = [_localStream.videoTracks firstObject];
    return videoTrack ? videoTrack.isEnabled : YES;
}

- (BOOL)isAudioEnabled
{
    RTCAudioTrack *audioTrack = [_localStream.audioTracks firstObject];
    return audioTrack ? audioTrack.isEnabled : YES;
}

- (void)enableVideo:(BOOL)enable
{
    RTCVideoTrack *videoTrack = [_localStream.videoTracks firstObject];
    [videoTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"videoOn" : @"videoOff" withPayload:nil];
}

- (void)enableAudio:(BOOL)enable
{
    RTCAudioTrack *audioTrack = [_localStream.audioTracks firstObject];
    [audioTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"audioOn" : @"audioOff" withPayload:nil];
}

#pragma mark - Ping call

- (void)pingCall
{
    [[NCAPIController sharedInstance] pingCall:_room withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        //TODO: Error handling
    }];
}

- (void)startPingCall
{
    [self pingCall];
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:5.0  target:self selector:@selector(pingCall) userInfo:nil repeats:YES];
}

- (void)stopPingCall
{
    [_pingTimer invalidate];
    _pingTimer = nil;
}

#pragma mark - Audio & Video senders

- (void)createLocalAudioTrack
{
    NSDictionary *mandatoryConstraints = @{ kRTCMediaConstraintsLevelControl : kRTCMediaConstraintsValueTrue };
    RTCMediaConstraints *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                          optionalConstraints:nil];
    
    RTCAudioSource *source = [_peerConnectionFactory audioSourceWithConstraints:constraints];
    _localAudioTrack = [_peerConnectionFactory audioTrackWithSource:source trackId:kNCAudioTrackId];
    [_localStream addAudioTrack:_localAudioTrack];
}

- (void)createLocalVideoTrack
{
#if !TARGET_IPHONE_SIMULATOR
    RTCVideoSource *source = [_peerConnectionFactory videoSource];
    RTCCameraVideoCapturer *capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    
    [self.delegate callController:self didCreateLocalVideoCapturer:capturer];
    
    _localVideoTrack = [_peerConnectionFactory videoTrackWithSource:source trackId:kNCVideoTrackId];
    [_localStream addVideoTrack:_localVideoTrack];
#endif
}

- (void)createLocalMedia
{
    RTCMediaStream *localMediaStream = [_peerConnectionFactory mediaStreamWithStreamId:kNCMediaStreamId];
    self.localStream = localMediaStream;
    [self createLocalAudioTrack];
    [self createLocalVideoTrack];
}

#pragma mark - Peer Connection Wrapper

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId
{
    NCPeerConnection *peerConnectionWrapper = [_connectionsDict objectForKey:sessionId];
    
    if (!peerConnectionWrapper) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        
        peerConnectionWrapper = [[NCPeerConnection alloc] initWithSessionId:sessionId];
        peerConnectionWrapper.delegate = self;
        // TODO: Try to get display name here
        [peerConnectionWrapper.peerConnection addStream:_localStream];
        
        [_connectionsDict setObject:peerConnectionWrapper forKey:sessionId];
        NSLog(@"Peer joined: %@", sessionId);
        [self.delegate callController:self peerJoined:peerConnectionWrapper];
    }
    
    return peerConnectionWrapper;
}

- (NCPeerConnection *)peerConnectionWrapperForConnection:(RTCPeerConnection *)connection
{
    NCPeerConnection *peerConnectionWrapper = nil;
    NSArray *connectionWrappers = [self.connectionsDict allValues];
    
    for (NCPeerConnection *wrapper in connectionWrappers) {
        if ([wrapper.peerConnection isEqual:connection]) {
            peerConnectionWrapper = wrapper;
            break;
        }
    }
    
    return peerConnectionWrapper;
}

- (void)sendDataChannelMessageToAllOfType:(NSString *)type withPayload:(NSString *)payload
{
    NSArray *connectionWrappers = [self.connectionsDict allValues];
    
    for (NCPeerConnection *peerConnection in connectionWrappers) {
        [peerConnection sendDataChannelMessageOfType:type withPayload:payload];
    }
}

#pragma mark - Signaling Controller Delegate

- (void)signalingController:(NCSignalingController *)signalingController didReceiveSignalingMessage:(NSDictionary *)message
{
    NSString *messageType = [message objectForKey:@"type"];
    
    if (_leavingCall) {return;}
    
    if ([messageType isEqualToString:@"usersInRoom"]) {
        [self processUsersInRoom:[message objectForKey:@"data"]];
    } else if ([messageType isEqualToString:@"message"]) {
        NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromJSONString:[message objectForKey:@"data"]];
        if (signalingMessage && [signalingMessage.roomType isEqualToString:kRoomTypeVideo]) {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from];            
            switch (signalingMessage.messageType) {
                case kNCSignalingMessageTypeOffer:
                case kNCSignalingMessageTypeAnswer:
                {
                    NCSessionDescriptionMessage *sdpMessage = (NCSessionDescriptionMessage *)signalingMessage;
                    RTCSessionDescription *description = sdpMessage.sessionDescription;
                    [peerConnectionWrapper setPeerName:sdpMessage.nick];
                    [peerConnectionWrapper setRemoteDescription:description];
                    break;
                }
                case kNCSignalingMessageTypeCandidate:
                {
                    NCICECandidateMessage *candidateMessage = (NCICECandidateMessage *)signalingMessage;
                    [peerConnectionWrapper addICECandidate:candidateMessage.candidate];
                    break;
                }
                    
                case kNCSignalingMessageTypeUknown:
                    NSLog(@"Received an unknown signaling message: %@", message);
                    break;
            }
        }
    } else {
        NSLog(@"Uknown message: %@", [message objectForKey:@"data"]);
    }
}

#pragma mark - Signaling functions

- (void)processUsersInRoom:(NSArray *)users
{
    NSMutableArray *newSessions = [self getSessionsFromUsersInRoom:users];
    NSMutableArray *oldSessions = [NSMutableArray arrayWithArray:_usersInRoom];
    
    //Save current sessions in call
    _usersInRoom = [NSArray arrayWithArray:newSessions];
    
    // Calculate sessions that left the call
    NSMutableArray *leftSessions = [NSMutableArray arrayWithArray:oldSessions];
    [leftSessions removeObjectsInArray:newSessions];
    
    // Calculate sessions that join the call
    [newSessions removeObjectsInArray:oldSessions];
    
    if (_leavingCall) {return;}
    
    for (NSString *sessionId in newSessions) {
        if (![_connectionsDict objectForKey:sessionId]) {
            NSComparisonResult result = [sessionId compare:_userSessionId];
            if (result == NSOrderedAscending) {
                NSLog(@"Creating offer...");
                NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:sessionId];
                [peerConnectionWrapper sendOffer];
            } else {
                NSLog(@"Waiting for offer...");
            }
        }
    }
    
    for (NSString *sessionId in leftSessions) {
        NCPeerConnection *leftPeerConnection = [_connectionsDict objectForKey:sessionId];
        if (leftPeerConnection) {
            NSLog(@"Peer left: %@", sessionId);
            [self.delegate callController:self peerLeft:leftPeerConnection];
            [leftPeerConnection close];
            [_connectionsDict removeObjectForKey:sessionId];
        }
    }
}

- (NSMutableArray *)getSessionsFromUsersInRoom:(NSArray *)users
{
    NSMutableArray *sessions = [[NSMutableArray alloc] init];
    for (NSDictionary *user in users) {
        NSString *sessionId = [user objectForKey:@"sessionId"];
        
        // Ignore user sessionId
        if([_userSessionId isEqualToString:sessionId]) {
            continue;
        }
        
        [sessions addObject:sessionId];
    }
    return sessions;
}

#pragma mark - NCPeerConnectionDelegate

- (void)peerConnection:(NCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    [self.delegate callController:self didAddStream:stream ofPeer:peerConnection];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    [self.delegate callController:self didRemoveStream:stream ofPeer:peerConnection];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    [self.delegate callController:self iceStatusChanged:newState ofPeer:peerConnection];
}

- (void)peerConnectionDidOpenStatusDataChannel:(NCPeerConnection *)peerConnection
{
    // Send current audio state
    if (self.isAudioEnabled) {
        NSLog(@"Send audioOn");
        [peerConnection sendDataChannelMessageOfType:@"audioOn" withPayload:nil];
    } else {
        NSLog(@"Send audioOff");
        [peerConnection sendDataChannelMessageOfType:@"audioOff" withPayload:nil];
    }
    
    // Send current video state
    if (self.isVideoEnabled) {
        NSLog(@"Send videoOn");
        [peerConnection sendDataChannelMessageOfType:@"videoOn" withPayload:nil];
    } else {
        NSLog(@"Send videoOff");
        [peerConnection sendDataChannelMessageOfType:@"videoOff" withPayload:nil];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NCICECandidateMessage *message = [[NCICECandidateMessage alloc] initWithCandidate:candidate
                                                                                 from:_userSessionId
                                                                                   to:peerConnection.peerId
                                                                                  sid:nil
                                                                             roomType:@"video"];
    
    [_signalingController sendSignalingMessage:message];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection needsToSendSessionDescription:(RTCSessionDescription *)sessionDescription
{
    NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                            initWithSessionDescription:sessionDescription
                                            from:_userSessionId
                                            to:peerConnection.peerId
                                            sid:nil
                                            roomType:@"video"
                                            nick:_userDisplayName];
    
    [_signalingController sendSignalingMessage:message];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didReceiveStatusDataChannelMessage:(NSString *)type
{
    [self.delegate callController:self didReceiveDataChannelMessage:type fromPeer:peerConnection];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didReceivePeerNick:(NSString *)nick
{
    [self.delegate callController:self didReceiveNick:nick fromPeer:peerConnection];
}


@end
