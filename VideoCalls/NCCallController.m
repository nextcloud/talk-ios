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
#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>
#import "NCAPIController.h"
#import "NCSignalingController.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface NCCallController () <NCPeerConnectionDelegate, NCSignalingControllerObserver>

@property (nonatomic, assign) BOOL isAudioOnly;
@property (nonatomic, assign) BOOL leavingCall;
@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSTimer *micAudioLevelTimer;
@property (nonatomic, assign) BOOL speaking;
@property (nonatomic, strong) NSArray *usersInRoom;
@property (nonatomic, strong) NSArray *peersInCall;
@property (nonatomic, strong) RTCMediaStream *localStream;
@property (nonatomic, strong) RTCAudioTrack *localAudioTrack;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong) NCSignalingController *signalingController;

@end

@implementation NCCallController

- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly
{
    self = [super init];
    
    if (self) {
        _delegate = delegate;
        _room = room;
        _isAudioOnly = audioOnly;
        _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] init];
        _connectionsDict = [[NSMutableDictionary alloc] init];
        _usersInRoom = [[NSArray alloc] init];
        _peersInCall = [[NSArray alloc] init];
        
        _signalingController = [[NCSignalingController alloc] initForRoom:room];
        _signalingController.observer = self;
        
        if (audioOnly) {
            [self setAudioSessionToVoiceChatMode];
        } else {
            [self setAudioSessionToVideoChatMode];
        }
        
        [self initRecorder];
    }
    
    return self;
}

- (void)startCall
{
    [self createLocalMedia];
    
    [[NCAPIController sharedInstance] joinRoom:_room.token withCompletionBlock:^(NSString *sessionId, NSError *error) {
        if (!error) {
            self.userSessionId = sessionId;
            [[NCAPIController sharedInstance] joinCall:_room.token withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self.delegate callControllerDidJoinCall:self];
                    
                    [self getPeersForCall];
                    [self startPingCall];
                    [self startMonitoringMicrophoneAudioLevel];
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
    
    [self stopPingCall];
    [self stopMonitoringMicrophoneAudioLevel];
    [_signalingController stopPullingSignalingMessages];
    
    [[NCAPIController sharedInstance] leaveCall:_room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCAPIController sharedInstance] exitRoom:_room.token withCompletionBlock:^(NSError *error) {
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
    if (!enable) {
        _speaking = NO;
        [self sendDataChannelMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
    }
}

#pragma mark - Ping call

- (void)pingCall
{
    [[NCAPIController sharedInstance] pingCall:_room.token withCompletionBlock:^(NSError *error) {
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

#pragma mark - Microphone audio level

- (void)startMonitoringMicrophoneAudioLevel
{
    _micAudioLevelTimer = [NSTimer scheduledTimerWithTimeInterval:1.0  target:self selector:@selector(checkMicAudioLevel) userInfo:nil repeats:YES];
}

- (void)stopMonitoringMicrophoneAudioLevel
{
    [_micAudioLevelTimer invalidate];
    _micAudioLevelTimer = nil;
}

- (void)initRecorder
{
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat: 44100.0],                 AVSampleRateKey,
                              [NSNumber numberWithInt: kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt: 0],                         AVNumberOfChannelsKey,
                              [NSNumber numberWithInt: AVAudioQualityMax],         AVEncoderAudioQualityKey,
                              nil];
    
    NSError *error;
    
    _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
    if (_recorder) {
        [_recorder prepareToRecord];
        _recorder.meteringEnabled = YES;
        [_recorder record];
    } else {
        NSLog(@"Failed initializing recorder.");
    }
}

- (void)checkMicAudioLevel
{
    if ([self isAudioEnabled]) {
        [_recorder updateMeters];
        float averagePower = [_recorder averagePowerForChannel:0];
        if (averagePower >= -50.0f && !_speaking) {
            _speaking = YES;
            [self sendDataChannelMessageToAllOfType:@"speaking" withPayload:nil];
        } else if (averagePower < -50.0f && _speaking) {
            _speaking = NO;
            [self sendDataChannelMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
        }
    }
}

#pragma mark - Call participants

- (void)getPeersForCall
{
    [[NCAPIController sharedInstance] getPeersForCall:_room.token withCompletionBlock:^(NSMutableArray *peers, NSError *error) {
        if (!error) {
            _peersInCall = peers;
        }
    }];
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
    if (!_isAudioOnly) {
        [self createLocalVideoTrack];
    }
}

#pragma mark - Audio session configuration

- (void)setAudioSessionToVoiceChatMode
{
    [self changeAudioSessionConfigurationModeTo:AVAudioSessionModeVoiceChat];
}

- (void)setAudioSessionToVideoChatMode
{
    [self changeAudioSessionConfigurationModeTo:AVAudioSessionModeVideoChat];
}

- (void)changeAudioSessionConfigurationModeTo:(NSString *)mode
{
    RTCAudioSessionConfiguration *configuration = [RTCAudioSessionConfiguration webRTCConfiguration];
    configuration.category = AVAudioSessionCategoryPlayAndRecord;
    configuration.mode = mode;
    
    RTCAudioSession *session = [RTCAudioSession sharedInstance];
    [session lockForConfiguration];
    BOOL hasSucceeded = NO;
    NSError *error = nil;
    if (session.isActive) {
        hasSucceeded = [session setConfiguration:configuration error:&error];
    } else {
        hasSucceeded = [session setConfiguration:configuration
                                          active:YES
                                           error:&error];
    }
    if (!hasSucceeded) {
        NSLog(@"Error setting configuration: %@", error.localizedDescription);
    }
    [session unlockForConfiguration];
}

- (BOOL)isSpeakerActive
{
    return [[RTCAudioSession sharedInstance] mode] == AVAudioSessionModeVideoChat;
}

#pragma mark - Peer Connection Wrapper

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId
{
    NCPeerConnection *peerConnectionWrapper = [_connectionsDict objectForKey:sessionId];
    
    if (!peerConnectionWrapper) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        
        NSArray *iceServers = [_signalingController getIceServers];
        peerConnectionWrapper = [[NCPeerConnection alloc] initWithSessionId:sessionId andICEServers:iceServers forAudioOnlyCall:_isAudioOnly];
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
    NSMutableArray *newSessions = [self getInCallSessionsFromUsersInRoom:users];
    NSMutableArray *oldSessions = [NSMutableArray arrayWithArray:_usersInRoom];
    
    //Save current sessions in call
    _usersInRoom = [NSArray arrayWithArray:newSessions];
    
    // Calculate sessions that left the call
    NSMutableArray *leftSessions = [NSMutableArray arrayWithArray:oldSessions];
    [leftSessions removeObjectsInArray:newSessions];
    
    // Calculate sessions that join the call
    [newSessions removeObjectsInArray:oldSessions];
    
    if (_leavingCall) {return;}
    
    if (newSessions.count > 0) {
        [self getPeersForCall];
    }
    
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

- (NSMutableArray *)getInCallSessionsFromUsersInRoom:(NSArray *)users
{
    NSMutableArray *sessions = [[NSMutableArray alloc] init];
    for (NSMutableDictionary *user in users) {
        NSString *sessionId = [user objectForKey:@"sessionId"];
        BOOL inCall = [[user objectForKey:@"inCall"] boolValue];
        
        // Ignore app user sessionId
        if ([_userSessionId isEqualToString:sessionId]) {
            continue;
        }
        
        // Only add session that are in the call
        if (inCall) {
            [sessions addObject:sessionId];
        }
    }
    return sessions;
}

- (NSString *)getUserIdFromSessionId:(NSString *)sessionId
{
    NSString *userId = nil;
    for (NSMutableDictionary *user in _peersInCall) {
        NSString *userSessionId = [user objectForKey:@"sessionId"];
        if ([userSessionId isEqualToString:sessionId]) {
            userId = [user objectForKey:@"userId"];
        }
    }
    return userId;
}

- (void)getUserIdInServerFromSessionId:(NSString *)sessionId withCompletionBlock:(GetUserIdForSessionIdCompletionBlock)block
{
    [[NCAPIController sharedInstance] getPeersForCall:_room.token withCompletionBlock:^(NSMutableArray *peers, NSError *error) {
        if (!error) {
            NSString *userId = nil;
            for (NSMutableDictionary *user in peers) {
                NSString *userSessionId = [user objectForKey:@"sessionId"];
                if ([userSessionId isEqualToString:sessionId]) {
                    userId = [user objectForKey:@"userId"];
                }
            }
            if (block) {
                block(userId, nil);
            }
        } else {
            if (block) {
                block(nil, error);
            }
        }
    }];
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
    if (self.isVideoEnabled && !_isAudioOnly) {
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
