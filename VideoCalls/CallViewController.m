//
//  CallViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 31.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "CallViewController.h"

#import "ARDSettingsModel.h"
#import "ARDCaptureController.h"
#import "ARDSDPUtils.h"
#import "NCAPIController.h"
#import "NCSignalingMessage.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface CallViewController () <RTCPeerConnectionDelegate, RTCDataChannelDelegate, RTCEAGLVideoViewDelegate>
{
    NSString *_callToken;
    NSString *_sessionId;
    
    RTCPeerConnectionFactory *_factory;
    
    NSMutableArray *_iceServers;
        
    NSMutableDictionary *_peerConnectionDict; // sessionId -> peerConnection
    NSMutableDictionary *_signalingMessagesDict; // sessionId -> messageQueue
    NSMutableArray *_usersInCall;
    
    RTCAudioTrack *_localAudioTrack;
    RTCVideoTrack *_localVideoTrack;
    ARDCaptureController *_captureController;
    RTCVideoTrack *_remoteVideoTrack;
    UIView<RTCVideoRenderer> *_remoteVideoView;
    
    CGSize _remoteVideoSize;
    
    RTCDataChannel *_localdataChannel;
    RTCDataChannel *_remoteDataChannel;
    
    BOOL _stopPullingMessages;
}
@end

@implementation CallViewController

@synthesize delegate = _delegate;

- (instancetype)initCall:(NSString *)token withSessionId:(NSString *)sessionId
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _callToken = token;
    _sessionId = sessionId;
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
        
    _factory = [[RTCPeerConnectionFactory alloc] init];
    _peerConnectionDict = [[NSMutableDictionary alloc] init];
    _signalingMessagesDict = [[NSMutableDictionary alloc] init];
    _usersInCall = [[NSMutableArray alloc] init];
    
    self.isAudioMute = NO;
    self.isVideoMute = NO;
    
    RTCIceServer *stunServer = [[RTCIceServer alloc] initWithURLStrings:[NSArray arrayWithObjects:@"stun:stun.nextcloud.com:443", nil]];
    NSMutableArray *iceServers = [NSMutableArray array];
    [iceServers addObject:stunServer];
    [_iceServers addObjectsFromArray:iceServers];
    
    RTCEAGLVideoView *remoteView = [[RTCEAGLVideoView alloc] initWithFrame:_remoteView.layer.bounds];
    remoteView.delegate = self;
    _remoteVideoView = remoteView;
    [_remoteView addSubview:_remoteVideoView];
    
    [self startPullingSignallingMessages];
    _stopPullingMessages = false;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Remote Video view

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    if (videoView == _remoteVideoView) {
        _remoteVideoSize = size;
        [self resizeRemoteVideoView];
    }
}

- (void)resizeRemoteVideoView {
    CGRect bounds = self.view.bounds;
    if (_remoteVideoSize.width > 0 && _remoteVideoSize.height > 0) {
        // Aspect fill remote video into bounds.
        CGRect remoteVideoFrame =
        AVMakeRectWithAspectRatioInsideRect(_remoteVideoSize, bounds);
        CGFloat scale = 1;
        if (remoteVideoFrame.size.width > remoteVideoFrame.size.height) {
            // Scale by height.
            scale = bounds.size.height / remoteVideoFrame.size.height;
        } else {
            // Scale by width.
            scale = bounds.size.width / remoteVideoFrame.size.width;
        }
        remoteVideoFrame.size.height *= scale;
        remoteVideoFrame.size.width *= scale;
        _remoteVideoView.frame = remoteVideoFrame;
        _remoteVideoView.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    } else {
        _remoteVideoView.frame = bounds;
    }
}

#pragma mark - RTCPeerConnectionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged
{
    NSLog(@"Signaling state changed: %ld", (long)stateChanged);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Received %lu video tracks and %lu audio tracks",
               (unsigned long)stream.videoTracks.count,
               (unsigned long)stream.audioTracks.count);
        if (stream.videoTracks.count) {
            RTCVideoTrack *videoTrack = stream.videoTracks[0];
            [self setRemoteVideoTrack:videoTrack];
        }
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    NSLog(@"Stream was removed.");
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    NSLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    NSLog(@"ICE state changed: %ld", (long)newState);
    dispatch_async(dispatch_get_main_queue(), ^{
//        [_delegate appClient:self didChangeConnectionState:newState];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    NSLog(@"ICE gathering state changed: %ld", (long)newState);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *to = [self getSessionIdForPeerConnection:peerConnection];
        NCICECandidateMessage *message = [[NCICECandidateMessage alloc] initWithCandidate:candidate
                                                                                     from:_sessionId
                                                                                       to:to
                                                                                      sid:nil
                                                                                 roomType:@"video"];
        [self sendSignalingMessage:message];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates
{
    NSLog(@"PeerConnection didRemoveIceCandidates delegate has been called.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    if ([dataChannel.label isEqualToString:@"status"]) {
        _remoteDataChannel = dataChannel;
        _remoteDataChannel.delegate = self;
        
        NSLog(@"Remote data channel '%@' was opened.", dataChannel.label);
    } else {
        NSLog(@"Data channel '%@' was opened.", dataChannel.label);
    }
}

//#pragma mark - RTCDataChannelDelegate

- (void)dataChannelDidChangeState:(RTCDataChannel *)dataChannel
{
    NSLog(@"Data cahnnel '%@' did change state: %ld", dataChannel.label, dataChannel.readyState);
    if (dataChannel.readyState == RTCDataChannelStateOpen && [dataChannel.label isEqualToString:@"status"]) {
        // Send current audio state
        if (self.isAudioMute) {
            [self sendDataChannelMessageOfType:@"audioOff" withPayload:nil];
        } else {
            [self sendDataChannelMessageOfType:@"audioOn" withPayload:nil];
        }
        
        // Send current video state
        if (self.isVideoMute) {
            [self sendDataChannelMessageOfType:@"videoOff" withPayload:nil];
        } else {
            [self sendDataChannelMessageOfType:@"videoOn" withPayload:nil];
        }
    }
}

- (void)dataChannel:(RTCDataChannel *)dataChannel didReceiveMessageWithBuffer:(RTCDataBuffer *)buffer
{
    NSDictionary *message = [self getDataChannelMessageFromJSONData:buffer.data];
    NSString *messageType =[message objectForKey:@"type"];
//    NSString *messagePayload = [message objectForKey:@"payload"];
    NSLog(@"Data channel '%@' did receive message: %@", dataChannel.label, messageType);
}

- (NSDictionary *)getDataChannelMessageFromJSONData:(NSData *)jsonData
{
    NSError *error;
    NSDictionary* messageDict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                options:kNilOptions
                                                                  error:&error];
    
    if (!messageDict) {
        NSLog(@"Error parsing data channel message: %@", error);
    }
    
    return messageDict;
}

- (NSData *)createDataChannelMessage:(NSDictionary *)message
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message
                                                       options:0
                                                         error:&error];
    
    if (!jsonData) {
        NSLog(@"Error creating data channel message: %@", error);
    }
    
    return jsonData;
}

- (void)sendDataChannelMessageOfType:(NSString *)type withPayload:(NSString *)payload
{
    NSDictionary *message = @{@"type": type};
    
    if (payload) {
        message = @{@"type": type,
                    @"payload": payload};
    }
    
    NSData *jsonMessage = [self createDataChannelMessage:message];
    RTCDataBuffer *dataBuffer = [[RTCDataBuffer alloc] initWithData:jsonMessage isBinary:NO];
    
    if (_localdataChannel) {
        [_localdataChannel sendData:dataBuffer];
    } else if (_remoteDataChannel) {
        [_remoteDataChannel sendData:dataBuffer];
    } else {
        NSLog(@"No data channel opened");
    }
}

#pragma mark - Audio & Video senders

- (RTCRtpSender *)createAudioSenderForPeerConnection:(RTCPeerConnection *)peerConnection
{
    NSDictionary *mandatoryConstraints = @{ kRTCMediaConstraintsLevelControl : kRTCMediaConstraintsValueTrue };
    RTCMediaConstraints *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                          optionalConstraints:nil];
    
    RTCAudioSource *source = [_factory audioSourceWithConstraints:constraints];
    _localAudioTrack = [_factory audioTrackWithSource:source trackId:kNCAudioTrackId];
    RTCRtpSender *sender =
    [peerConnection senderWithKind:kRTCMediaStreamTrackKindAudio
                          streamId:kNCMediaStreamId];
    sender.track = _localAudioTrack;
    return sender;
}

- (RTCRtpSender *)createVideoSenderForPeerConnection:(RTCPeerConnection *)peerConnection
{
    RTCRtpSender *sender =
    [peerConnection senderWithKind:kRTCMediaStreamTrackKindVideo
                          streamId:kNCMediaStreamId];
#if !TARGET_IPHONE_SIMULATOR
    RTCVideoSource *source = [_factory videoSource];
    RTCCameraVideoCapturer *capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    ARDSettingsModel *settingsModel = [[ARDSettingsModel alloc] init];
    
    _localVideoView.captureSession = capturer.captureSession;
    _captureController = [[ARDCaptureController alloc] initWithCapturer:capturer settings:settingsModel];
    
    [_captureController startCapture];
    
    _localVideoTrack = [_factory videoTrackWithSource:source trackId:kNCVideoTrackId];
    
    sender.track = _localVideoTrack;
#endif
    return sender;
}

- (void)setRemoteVideoTrack:(RTCVideoTrack *)remoteVideoTrack
{
    if (_remoteVideoTrack == remoteVideoTrack) {
        return;
    }
    
    [_remoteVideoTrack removeRenderer:_remoteVideoView];
    _remoteVideoTrack = nil;
    [_remoteVideoView renderFrame:nil];
    _remoteVideoTrack = remoteVideoTrack;
    [_remoteVideoTrack addRenderer:_remoteVideoView];
}

#pragma mark - Utils

- (RTCMediaConstraints *)defaultAnswerConstraints
{
    return [self defaultOfferConstraints];
}

- (RTCMediaConstraints *)defaultOfferConstraints
{
    NSDictionary *mandatoryConstraints = @{
                                           @"OfferToReceiveAudio" : @"true",
                                           @"OfferToReceiveVideo" : @"true"
                                           };
    
    NSDictionary *optionalConstraints = @{
                                          @"internalSctpDataChannels": @"true",
                                          @"DtlsSrtpKeyAgreement": @"true"
                                          };
    
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                        initWithMandatoryConstraints:mandatoryConstraints
                                        optionalConstraints:optionalConstraints];
    return constraints;
}

#pragma mark - Call actions

- (IBAction)audioButtonPressed:(id)sender
{
    UIButton *audioButton = sender;
    if (self.isAudioMute) {
        [self unmuteAudio];
        [audioButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
        [self sendDataChannelMessageOfType:@"audioOn" withPayload:nil];
        self.isAudioMute = NO;
    } else {
        [self muteAudio];
        [audioButton setImage:[UIImage imageNamed:@"audio-off"] forState:UIControlStateNormal];
        [self sendDataChannelMessageOfType:@"audioOff" withPayload:nil];
        self.isAudioMute = YES;
    }
}

- (IBAction)videoButtonPressed:(id)sender
{
    UIButton *videoButton = sender;
    if (self.isVideoMute) {
        [self unmuteVideo];
        [videoButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
        [self sendDataChannelMessageOfType:@"videoOn" withPayload:nil];
        self.isVideoMute = NO;
    } else {
        [self muteVideo];
        [videoButton setImage:[UIImage imageNamed:@"video-off"] forState:UIControlStateNormal];
        [self sendDataChannelMessageOfType:@"videoOff" withPayload:nil];
        self.isVideoMute = YES;
    }
}

- (IBAction)hangupButtonPressed:(id)sender {
    [self hangup];
}

- (void)hangup {
    self.remoteVideoTrack = nil;
    self.localVideoView.captureSession = nil;
    [_captureController stopCapture];
    _captureController = nil;
    
    [[NCAPIController sharedInstance] leaveCall:_callToken withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        if (error) {
            NSLog(@"Error while leaving the call.");
        }
    }];
    
    _stopPullingMessages = true;
    [_delegate viewControllerDidFinish:self];
}

#pragma mark - Audio mute/unmute
- (void)muteAudio
{
    NSLog(@"audio muted");
    NSArray *peerConnections = [_peerConnectionDict allValues];
    for (RTCPeerConnection *peerConnection in peerConnections) {
        NSArray *senders = peerConnection.senders;
        for (RTCRtpSender *sender in senders) {
            if (sender.track.kind == kRTCMediaStreamTrackKindAudio) {
                sender.track.isEnabled = NO;
            }
        }
    }
}
- (void)unmuteAudio
{
    NSLog(@"audio unmuted");
    NSArray *peerConnections = [_peerConnectionDict allValues];
    for (RTCPeerConnection *peerConnection in peerConnections) {
        NSArray *senders = peerConnection.senders;
        for (RTCRtpSender *sender in senders) {
            if (sender.track.kind == kRTCMediaStreamTrackKindAudio) {
                sender.track.isEnabled = YES;
            }
        }
    }
}

#pragma mark - Video mute/unmute
- (void)muteVideo
{
    NSLog(@"video muted");
    NSArray *peerConnections = [_peerConnectionDict allValues];
    for (RTCPeerConnection *peerConnection in peerConnections) {
        NSArray *senders = peerConnection.senders;
        for (RTCRtpSender *sender in senders) {
            if (sender.track.kind == kRTCMediaStreamTrackKindVideo) {
                sender.track.isEnabled = NO;
            }
        }
    }
}
- (void)unmuteVideo
{
    NSLog(@"video unmuted");
    NSArray *peerConnections = [_peerConnectionDict allValues];
    for (RTCPeerConnection *peerConnection in peerConnections) {
        NSArray *senders = peerConnection.senders;
        for (RTCRtpSender *sender in senders) {
            if (sender.track.kind == kRTCMediaStreamTrackKindVideo) {
                sender.track.isEnabled = YES;
            }
        }
    }
}

#pragma mark - Signalling

- (void)startPullingSignallingMessages
{
    [[NCAPIController sharedInstance] pullSignallingMessagesWithCompletionBlock:^(NSDictionary *messages, NSError *error, NSInteger errorCode) {
        NSArray *messagesArray = [[messages objectForKey:@"ocs"] objectForKey:@"data"];
        for (NSDictionary *message in messagesArray) {
            NSString *messageType = [message objectForKey:@"type"];
            
            if ([messageType isEqualToString:@"usersInRoom"]) {
                [self processUsersInRoom:[message objectForKey:@"data"]];
            } else if ([messageType isEqualToString:@"message"]) {
                NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromJSONString:[message objectForKey:@"data"]];
                if (signalingMessage) {
                    RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:signalingMessage.from];
                    NSMutableArray *messageQueue = [_signalingMessagesDict objectForKey:signalingMessage.from];
                    
                    switch (signalingMessage.messageType) {
                        case kNCSignalingMessageTypeOffer:
                        case kNCSignalingMessageTypeAnswer:
                            // Offers and answers must be processed before any other message, so we
                            // place them at the front of the queue.
                            [self processSignalingMessage:signalingMessage];
                            break;
                        case kNCSignalingMessageTypeCandidate:
                            if (!peerConnection.remoteDescription) {
                                [messageQueue addObject:signalingMessage];
                            } else {
                                [self processSignalingMessage:signalingMessage];
                                [self drainMessageQueueIfReadyForPeer:signalingMessage.from];
                            }
                            
                            break;
                        case kNCSignalingMessageTypeUknown:
                            break;
                    }
                }
            } else {
                NSLog(@"Uknown message: %@", [message objectForKey:@"data"]);
            }
        }
        
        if (!_stopPullingMessages) {
            [self startPullingSignallingMessages];
        }
    }];
}

- (void)drainMessageQueueIfReadyForPeer:(NSString *)sessionId {
    NSMutableArray *messageQueue = [_signalingMessagesDict objectForKey:sessionId];
    
    for (NCSignalingMessage *message in messageQueue) {
        [self processSignalingMessage:message];
    }
    
    [messageQueue removeAllObjects];
}

- (void)sendSignalingMessages:(NSArray *)messages
{
    [[NCAPIController sharedInstance] sendSignallingMessages:[self messagesJSONSerialization:messages] withCompletionBlock:^(NSError *error, NSInteger errorCode) {
        NSLog(@"Sent %ld signalling messages", messages.count);
    }];
}

- (void)sendSignalingMessage:(NCSignalingMessage *)message
{
    NSArray *messagesArray = [NSArray arrayWithObjects:[message messageDict], nil];
    NSString *JSONSerializedMessages = [self messagesJSONSerialization:messagesArray];
    [[NCAPIController sharedInstance] sendSignallingMessages:JSONSerializedMessages withCompletionBlock:^(NSError *error, NSInteger errorCode) {
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

- (void)processUsersInRoom:(NSArray *)users
{
    for (NSDictionary *user in users) {
        NSString *sessionId = [user objectForKey:@"sessionId"];
        
        if([_sessionId isEqualToString:sessionId]) {
            continue;
        }
        
        if (![_peerConnectionDict objectForKey:sessionId]) {
            NSComparisonResult result = [sessionId compare:_sessionId];
            if (result == NSOrderedAscending) {
                NSLog(@"Creating offer...");
                [self sendOfferToSessionId:sessionId];
            } else {
                NSLog(@"Waiting for offer...");
            }
        }
        
    }
}

- (void)processSignalingMessage:(NCSignalingMessage *)message
{
    switch (message.messageType) {
        case kNCSignalingMessageTypeOffer:
        case kNCSignalingMessageTypeAnswer: {
            NCSessionDescriptionMessage *sdpMessage = (NCSessionDescriptionMessage *)message;
            RTCSessionDescription *description = sdpMessage.sessionDescription;
            RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:message.from];
            
            [peerConnection setRemoteDescription:description completionHandler:^(NSError *error) {
                [self peerConnectionForSessionId:message.from didSetSessionDescriptionWithError:error];
            }];
            break;
        }
        case kNCSignalingMessageTypeCandidate: {
            NCICECandidateMessage *candidateMessage = (NCICECandidateMessage *)message;
            RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:message.from];
            
            [peerConnection addIceCandidate:candidateMessage.candidate];
            break;
        }
        case kNCSignalingMessageTypeUknown:
            NSLog(@"Trying to process an unkown type message.");
            break;
    }
}

#pragma mark - Peer Connection

- (RTCPeerConnection *)getPeerConnectionForSessionId:(NSString *)sessionId
{
    RTCPeerConnection *peerConnection = [_peerConnectionDict objectForKey:sessionId];
    
    if (!peerConnection) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                            initWithMandatoryConstraints:nil
                                            optionalConstraints:nil];
        RTCConfiguration *config = [[RTCConfiguration alloc] init];
        config.iceServers = _iceServers;
        
        peerConnection = [_factory peerConnectionWithConfiguration:config
                                                       constraints:constraints
                                                          delegate:self];
        
        [self createAudioSenderForPeerConnection:peerConnection];
        [self createVideoSenderForPeerConnection:peerConnection];
        
        [_peerConnectionDict setObject:peerConnection forKey:sessionId];
        
        // Initialize message queue for this peer
        NSMutableArray *messageQueue = [[NSMutableArray alloc] init];
        [_signalingMessagesDict setObject:messageQueue forKey:sessionId];
    }
    
    return peerConnection;
}

- (NSString *)getSessionIdForPeerConnection:(RTCPeerConnection *)peerConnection
{
    NSString *sessionId = nil;
    NSArray *keysForPC = [_peerConnectionDict allKeysForObject:peerConnection];
    
    if ([keysForPC count] > 0) {
        sessionId = [keysForPC lastObject];
    }
    
    if ([keysForPC count] > 1) {
        NSLog(@"Warning: Multiple session ids saved the same peer connection object.");
    }
    
    return sessionId;
}

- (void)sendOfferToSessionId:(NSString *)sessionId
{
    RTCPeerConnection *peerConnection =  [self getPeerConnectionForSessionId:sessionId];
    if (peerConnection) {
        //Create data channel before creating the offer to enable data channels
        RTCDataChannelConfiguration* config = [[RTCDataChannelConfiguration alloc] init];
        config.isNegotiated = NO;
        _localdataChannel = [peerConnection dataChannelForLabel:@"status" configuration:config];
        _localdataChannel.delegate = self;
        [peerConnection offerForConstraints:[self defaultOfferConstraints] completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
            [peerConnection setLocalDescription:sdp completionHandler:^(NSError *error) {
                NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                                        initWithSessionDescription:sdp
                                                        from:_sessionId
                                                        to:sessionId
                                                        sid:nil
                                                        roomType:@"video"];
                [self sendSignalingMessage:message];
            }];
        }];
    } else {
        NSLog(@"Could not send offer.");
    }
}

#pragma mark - RTCSessionDescriptionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnectionForSessionId:(NSString *)sessionId
didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to create session description. Error: %@", error);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"didCreateSessionDescription: %ld", (long)sdp.type);
        // Set VP8 as preferred codec.
        RTCSessionDescription *sdpPreferringCodec = [ARDSDPUtils descriptionForDescription:sdp preferredVideoCodec:@"VP8"];
        RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:sessionId];
        [peerConnection setLocalDescription:sdpPreferringCodec completionHandler:^(NSError *error) {
            [self peerConnectionForSessionId:sessionId didSetSessionDescriptionWithError:error];
        }];
        
        NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                                initWithSessionDescription:sdpPreferringCodec
                                                from:_sessionId to:sessionId
                                                sid:nil
                                                roomType:@"video"];
        [self sendSignalingMessage:message];
//        [self setMaxBitrateForPeerConnectionVideoSender];
    });
}

- (void)peerConnectionForSessionId:(NSString *)sessionId
didSetSessionDescriptionWithError:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to set session description. Error: %@", error);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // If we're answering and we've just set the remote offer we need to create
        // an answer and set the local description.
        NSLog(@"didSetSessionDescription");
        RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:sessionId];
        if (!peerConnection.localDescription) {
            NSLog(@"creating local description");
            RTCMediaConstraints *constraints = [self defaultAnswerConstraints];
            [peerConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
                [self peerConnectionForSessionId:sessionId didCreateSessionDescription:sdp error:error];
            }];
        }
    });
}

@end
