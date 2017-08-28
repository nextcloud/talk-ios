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
#import "ARDSignalingMessage.h"
#import "NCAPIController.h"
#import "NCSignalingMessage.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface CallViewController () <RTCPeerConnectionDelegate, RTCEAGLVideoViewDelegate>
{
    NSString *_sessionId;
    
    RTCPeerConnectionFactory *_factory;
    
    NSMutableArray *_iceServers;
        
    NSMutableDictionary *_peerConnectionDict; // sessionId -> peerConnection
    NSMutableDictionary *_signalingMessagesDict; // sessionId -> messageQueue
    NSMutableArray *_usersInCall;
    
    RTCVideoTrack *_localVideoTrack;
    ARDCaptureController *_captureController;
    RTCVideoTrack *_remoteVideoTrack;
    UIView<RTCVideoRenderer> *_remoteVideoView;
    
    CGSize _remoteVideoSize;
    
    BOOL _stopPullingMessages;
}
@end

@implementation CallViewController

@synthesize delegate = _delegate;

- (instancetype)initWithSessionId:(NSString *)sessionId
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
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
                                                                                      sid:[NCSignalingMessage getMessageSid]
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
    NSLog(@"Data channel was opened.");
}

#pragma mark - Audio & Video senders

- (RTCRtpSender *)createAudioSenderForPeerConnection:(RTCPeerConnection *)peerConnection
{
    NSDictionary *mandatoryConstraints = @{ kRTCMediaConstraintsLevelControl : kRTCMediaConstraintsValueTrue };
    RTCMediaConstraints *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                          optionalConstraints:nil];
    
    RTCAudioSource *source = [_factory audioSourceWithConstraints:constraints];
    RTCAudioTrack *track = [_factory audioTrackWithSource:source trackId:kNCAudioTrackId];
    RTCRtpSender *sender =
    [peerConnection senderWithKind:kRTCMediaStreamTrackKindAudio
                          streamId:kNCMediaStreamId];
    sender.track = track;
    return sender;
}

- (RTCRtpSender *)createVideoSenderForPeerConnection:(RTCPeerConnection *)peerConnection
{
    RTCRtpSender *sender =
    [peerConnection senderWithKind:kRTCMediaStreamTrackKindVideo
                          streamId:kNCMediaStreamId];
    
    RTCVideoSource *source = [_factory videoSource];
    RTCCameraVideoCapturer *capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    ARDSettingsModel *settingsModel = [[ARDSettingsModel alloc] init];
    
    _localVideoView.captureSession = capturer.captureSession;
    _captureController = [[ARDCaptureController alloc] initWithCapturer:capturer settings:settingsModel];
    
    [_captureController startCapture];
    
    _localVideoTrack = [_factory videoTrackWithSource:source trackId:kNCVideoTrackId];
    
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
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                        initWithMandatoryConstraints:mandatoryConstraints
                                        optionalConstraints:nil];
    return constraints;
}

#pragma mark - Call actions

- (IBAction)hangupButtonPressed:(id)sender {
    [self hangup];
}

- (void)hangup {
    self.remoteVideoTrack = nil;
    self.localVideoView.captureSession = nil;
    [_captureController stopCapture];
    _captureController = nil;
    
    _stopPullingMessages = true;
    
    [_delegate viewControllerDidFinish:self];
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
            return;
        }
        
        if (![_peerConnectionDict objectForKey:sessionId]) {
            NSComparisonResult result = [sessionId compare:_sessionId];
            if (result == NSOrderedAscending) {
                NSLog(@"Creating offer...");
                [self createPeerConnectionWithOfferForSessionId:sessionId];
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

- (void)createPeerConnectionWithOfferForSessionId:(NSString *)sessionId
{
    // Create peer connection.
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                        initWithMandatoryConstraints:nil
                                        optionalConstraints:nil];
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    config.iceServers = _iceServers;
    
    RTCPeerConnection *peerConnection = [_factory peerConnectionWithConfiguration:config
                                                                      constraints:constraints
                                                                         delegate:self];
    
    [_peerConnectionDict setObject:peerConnection forKey:sessionId];
    
    // Initialize message queue for this peer
    NSMutableArray *messageQueue = [[NSMutableArray alloc] init];
    [_signalingMessagesDict setObject:messageQueue forKey:sessionId];
    
    [peerConnection offerForConstraints:[self defaultOfferConstraints]
                       completionHandler:^(RTCSessionDescription *sdp,
                                           NSError *error) {
                           [peerConnection setLocalDescription:sdp completionHandler:^(NSError *error) {
                               NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                                                       initWithSessionDescription:sdp
                                                                       from:_sessionId
                                                                       to:sessionId
                                                                       sid:[NCSignalingMessage getMessageSid]
                                                                       roomType:@"video"];
                               [self sendSignalingMessage:message];
                           }];
                       }];
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
        RTCPeerConnection *peerConnection = [self getPeerConnectionForSessionId:sessionId];
        [peerConnection setLocalDescription:sdp completionHandler:^(NSError *error) {
            [self peerConnectionForSessionId:sessionId didSetSessionDescriptionWithError:error];
        }];
        
        NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                                initWithSessionDescription:sdp
                                                from:_sessionId to:sessionId
                                                sid:[NCSignalingMessage getMessageSid]
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
