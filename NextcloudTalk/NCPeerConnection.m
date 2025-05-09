/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCPeerConnection.h"

#import <WebRTC/RTCConfiguration.h>
#import <WebRTC/RTCDataChannelConfiguration.h>
#import <WebRTC/RTCIceServer.h>
#import <WebRTC/RTCPeerConnectionFactory.h>
#import <WebRTC/RTCMediaConstraints.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>
#import <WebRTC/RTCDefaultVideoDecoderFactory.h>

#import "ARDSDPUtils.h"

#import "NCSignalingMessage.h"
#import "NextcloudTalk-Swift.h"


@interface NCPeerConnection () <RTCPeerConnectionDelegate, RTCDataChannelDelegate>

@property (nonatomic, strong) NSMutableArray *queuedRemoteCandidates;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, strong) RTCDataChannel *localDataChannel;
@property (nonatomic, strong) RTCDataChannel *remoteDataChannel;
@property (nonatomic, strong) RTCMediaStream *remoteStream;

@end

@implementation NCPeerConnection

- (instancetype)initWithSessionId:(NSString *)sessionId sid:(NSString *)sid andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly
{
    self = [super init];
    
    if (self) {
        [[WebRTCCommon shared] assertQueue];
        
        RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                            initWithMandatoryConstraints:nil
                                            optionalConstraints:nil];
        
        RTCConfiguration *config = [[RTCConfiguration alloc] init];
        [config setIceServers:iceServers];
        [config setSdpSemantics:RTCSdpSemanticsUnifiedPlan];

        RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
        RTCPeerConnection *peerConnection = [peerConnectionFactory peerConnectionWithConfiguration:config
                                                                                       constraints:constraints
                                                                                          delegate:self];
        
        _peerConnection = peerConnection;
        _peerId = sessionId;
        NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970] * 1000;
        _sid = sid ? sid : [NSString stringWithFormat:@"%.0f", timeStamp];
        _isAudioOnly = audioOnly;
    }
    
    return self;
}

- (instancetype)initForPublisherWithSessionId:(NSString *)sessionId andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly
{
    self = [self initWithSessionId:sessionId sid:nil andICEServers:iceServers forAudioOnlyCall:audioOnly];
    
    if (self) {
        _isMCUPublisherPeer = YES;
    }
    
    return self;
}

#pragma mark - NSObject

- (NSUInteger)hash
{
    return [self.peerIdentifier hash];
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[NCPeerConnection class]]) {
        NCPeerConnection *otherConnection = (NCPeerConnection *)object;
        return [otherConnection.peerConnection isEqual:self.peerConnection];
    }
    
    return NO;
}

- (void)dealloc {
//    [self close];
    NSLog(@"NCPeerConnection dealloc");
}

#pragma mark - Public

- (NSString *)peerIdentifier
{
    if (_sid != nil) {
        return [NSString stringWithFormat:@"%@-%@", _peerId, _sid];
    }

    return _peerId;
}

- (void)addICECandidate:(RTCIceCandidate *)candidate
{
    [[WebRTCCommon shared] assertQueue];

    if (!_peerConnection.remoteDescription) {
        if (!self.queuedRemoteCandidates) {
            self.queuedRemoteCandidates = [NSMutableArray array];
        }
        
        NSLog(@"Queued a remote ICE candidate for later.");
        [self.queuedRemoteCandidates addObject:candidate];
    } else {
        NSLog(@"Adding a remote ICE candidate.");

        [self.peerConnection addIceCandidate:candidate completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error while adding a remote ICE candidate.");
            }
        }];
    }
}

- (void)drainRemoteCandidates
{

    [[WebRTCCommon shared] assertQueue];

    NSLog(@"Drain %lu remote ICE candidates.", (unsigned long)[self.queuedRemoteCandidates count]);

    for (RTCIceCandidate *candidate in self.queuedRemoteCandidates) {
        [self.peerConnection addIceCandidate:candidate completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error while adding a remote ICE candidate.");
            }
        }];
    }
    self.queuedRemoteCandidates = nil;
}

- (void)setRemoteDescription:(RTCSessionDescription *)sessionDescription
{
    [[WebRTCCommon shared] assertQueue];

    __weak NCPeerConnection *weakSelf = self;
    RTCSessionDescription *sdpPreferringCodec = [ARDSDPUtils descriptionForDescription:sessionDescription preferredVideoCodec:@"H264"];
    [_peerConnection setRemoteDescription:sdpPreferringCodec completionHandler:^(NSError *error) {
        [[WebRTCCommon shared] dispatch:^{
            NCPeerConnection *strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf peerConnectionDidSetRemoteSessionDescription:sdpPreferringCodec error:error];
            }
        }];
    }];
}

- (void)sendOffer
{
    [self sendOfferWithConstraints:[self defaultOfferConstraints]];
}

- (void)sendPublisherOffer
{
    [self sendOfferWithConstraints:[self publisherOfferConstraints]];
}

- (void)sendOfferWithConstraints:(RTCMediaConstraints *)constraints
{
    [[WebRTCCommon shared] assertQueue];

    //Create data channel before creating the offer to enable data channels
    RTCDataChannelConfiguration* config = [[RTCDataChannelConfiguration alloc] init];
    config.isNegotiated = NO;
    _localDataChannel = [_peerConnection dataChannelForLabel:@"status" configuration:config];
    _localDataChannel.delegate = self;

    // Create offer
    __weak NCPeerConnection *weakSelf = self;
    [_peerConnection offerForConstraints:constraints completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
        [[WebRTCCommon shared] dispatch:^{
            NCPeerConnection *strongSelf = weakSelf;

            if (strongSelf) {
                [strongSelf peerConnectionDidCreateLocalSessionDescription:sdp error:error];
            }
        }];
    }];
}

- (void)setStatusForDataChannelMessageType:(NSString *)type withPayload:(id)payload
{
    [[WebRTCCommon shared] assertQueue];

    if ([type isEqualToString:@"nickChanged"]) {
        NSString *nick = @"";
        if ([payload isKindOfClass:[NSString class]]) {
            nick = payload;
        } else if ([payload isKindOfClass:[NSDictionary class]]) {
            nick = [payload objectForKey:@"name"];
        }
        _peerName = nick;
        [self.delegate peerConnection:self didReceivePeerNick:nick];
    } else {
        // Check remote audio/video status
        if ([type isEqualToString:@"audioOn"]) {
            _isRemoteAudioDisabled = NO;
        } else if ([type isEqualToString:@"audioOff"]) {
            _isRemoteAudioDisabled = YES;
        } else if ([type isEqualToString:@"videoOn"]) {
            _isRemoteVideoDisabled = NO;
        } else if ([type isEqualToString:@"videoOff"]) {
            _isRemoteVideoDisabled = YES;
        } else if ([type isEqualToString:@"speaking"]) {
            _isPeerSpeaking = YES;
        } else if ([type isEqualToString:@"stoppedSpeaking"]) {
            _isPeerSpeaking = NO;
        } else if ([type isEqualToString:@"raiseHand"]) {
            _isHandRaised = [payload boolValue];
        }
        
        [self.delegate peerConnection:self didReceiveStatusDataChannelMessage:type];
    }
}

- (void)close
{
    [[WebRTCCommon shared] assertQueue];

    RTCMediaStream *localStream = [self.peerConnection.localStreams firstObject];
    if (localStream) {
        [self.peerConnection removeStream:localStream];
    }
    [self.peerConnection close];

    self.remoteStream = nil;
    self.localDataChannel = nil;
    self.remoteDataChannel = nil;
    self.peerConnection = nil;
}

#pragma mark - Public RTC getters

- (RTCPeerConnection *)getPeerConnection {
    [[WebRTCCommon shared] assertQueue];
    return self.peerConnection;
}

- (RTCDataChannel *)getLocalDataChannel {
    [[WebRTCCommon shared] assertQueue];
    return self.localDataChannel;
}

- (RTCDataChannel *)getRemoteDataChannel {
    [[WebRTCCommon shared] assertQueue];
    return self.remoteDataChannel;
}

- (RTCMediaStream *)getRemoteStream {
    [[WebRTCCommon shared] assertQueue];
    return self.remoteStream;
}

- (BOOL)hasRemoteStream {
    return (self.remoteStream != nil);
}

#pragma mark - RTCPeerConnectionDelegate
// Delegates from RTCPeerConnection are called on the "signaling_thread" of WebRTC

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged
{
    NSLog(@"Signaling state with '%@' changed to: %@", self.peerId, [self stringForSignalingState:stateChanged]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Received %lu video tracks and %lu audio tracks from %@",
              (unsigned long)stream.videoTracks.count,
              (unsigned long)stream.audioTracks.count,
              self.peerId);

        self.remoteStream = stream;

        if ([stream.videoTracks count] == 0) {
            self.isRemoteVideoDisabled = YES;
        }

        [self.delegate peerConnection:self didAddStream:stream];
    }];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Stream was removed from %@", self.peerId);
        self.remoteStream = nil;
        [self.delegate peerConnection:self didRemoveStream:stream];
    }];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddReceiver:(RTCRtpReceiver *)rtpReceiver streams:(NSArray<RTCMediaStream *> *)mediaStreams
{
    [[WebRTCCommon shared] dispatch:^{
        RTCMediaStream *stream = mediaStreams[0];
        if (!stream) {
            return;
        }

        NSLog(@"Received %lu video tracks and %lu audio tracks from %@",
              (unsigned long)stream.videoTracks.count,
              (unsigned long)stream.audioTracks.count,
              self.peerId);
        
        self.remoteStream = stream;
        [self.delegate peerConnection:self didAddStream:stream];
    }];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveReceiver:(RTCRtpReceiver *)rtpReceiver
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Receiver was removed from %@", self.peerId);
        self.remoteStream = nil;
        [self.delegate peerConnection:self didRemoveStream:nil];
    }];
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    NSLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"ICE state with '%@' changed to: %@", self.peerId, [self stringForConnectionState:newState]);
        [self.delegate peerConnection:self didChangeIceConnectionState:newState];
    }];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    NSLog(@"ICE gathering state with '%@' changed to : %@", self.peerId, [self stringForGatheringState:newState]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Peer '%@' did generate Ice Candidate: %@", self.peerId, candidate);
        [self.delegate peerConnection:self didGenerateIceCandidate:candidate];
    }];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates
{
    NSLog(@"PeerConnection didRemoveIceCandidates delegate has been called.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    [[WebRTCCommon shared] dispatch:^{
        if (self->_remoteDataChannel) {
            NSLog(@"Remote data channel with label '%@' exists, but received open event for data channel with label '%@'", self->_remoteDataChannel.label, dataChannel.label);
        }

        self->_remoteDataChannel = dataChannel;
        self->_remoteDataChannel.delegate = self;
        NSLog(@"Remote data channel '%@' was opened.", dataChannel.label);
    }];
}

#pragma mark - RTCDataChannelDelegate
// Delegates from RTCDataChannel are called on the "signaling_thread" of WebRTC

- (void)dataChannelDidChangeState:(RTCDataChannel *)dataChannel
{
    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Data channel '%@' did change state: %ld", dataChannel.label, (long)dataChannel.readyState);
        
//        if (dataChannel.readyState == RTCDataChannelStateOpen && [dataChannel.label isEqualToString:@"status"]) {
//            [self.delegate peerConnectionDidOpenStatusDataChannel:self];
//        }
    }];
}

- (void)dataChannel:(RTCDataChannel *)dataChannel didReceiveMessageWithBuffer:(RTCDataBuffer *)buffer
{
    [[WebRTCCommon shared] dispatch:^{
        NSDictionary *message = [self getDataChannelMessageFromJSONData:buffer.data];
        NSString *messageType = [message objectForKey:@"type"];
        id messagePayload = [message objectForKey:@"payload"];

        [self setStatusForDataChannelMessageType:messageType withPayload:messagePayload];
    }];
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

- (void)sendDataChannelMessageOfType:(NSString *)type withPayload:(id)payload
{
    [[WebRTCCommon shared] assertQueue];

    NSDictionary *message = @{@"type": type};

    if (payload) {
        message = @{@"type": type,
                    @"payload": payload};
    }

    NSData *jsonMessage = [self createDataChannelMessage:message];
    RTCDataBuffer *dataBuffer = [[RTCDataBuffer alloc] initWithData:jsonMessage isBinary:NO];

    if (_localDataChannel) {
        [_localDataChannel sendData:dataBuffer];
    } else if (_remoteDataChannel) {
        [_remoteDataChannel sendData:dataBuffer];
    } else {
        NSLog(@"No data channel opened");
    }
}

#pragma mark - RTCSessionDescriptionDelegate
// Delegates from RTCSessionDescription are already dispatched to the webrtc client thread

- (void)peerConnectionDidCreateLocalSessionDescription:(RTCSessionDescription *)sdp error:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to create local session description for peer %@. Error: %@", _peerId, error);
        return;
    }

    [[WebRTCCommon shared] assertQueue];

    // Set H264 as preferred codec.
    RTCSessionDescription *sdpPreferringCodec = [ARDSDPUtils descriptionForDescription:sdp preferredVideoCodec:@"H264"];

    __weak NCPeerConnection *weakSelf = self;
    [self->_peerConnection setLocalDescription:sdpPreferringCodec completionHandler:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to set local session description: %@", error);
            return;
        }

        [[WebRTCCommon shared] dispatch:^{
            NCPeerConnection *strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf.delegate peerConnection:strongSelf needsToSendSessionDescription:sdpPreferringCodec];
            }
        }];
    }];
}

- (void)peerConnectionDidSetRemoteSessionDescription:(RTCSessionDescription *)sessionDescription error:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to set remote session description for peer %@. Error: %@", _peerId, error);
        return;
    }

    [[WebRTCCommon shared] assertQueue];

    // If we just set a remote offer we need to create an answer and set it as local description.
    if (self->_peerConnection.signalingState == RTCSignalingStateHaveRemoteOffer) {
        // Create data channel before sending answer
        RTCDataChannelConfiguration* config = [[RTCDataChannelConfiguration alloc] init];
        config.isNegotiated = NO;
        self->_localDataChannel = [self->_peerConnection dataChannelForLabel:@"status" configuration:config];
        self->_localDataChannel.delegate = self;

        // Stop video transceiver in audio only peer connections
        // Constraints are no longer supported when creating answers (with Unified Plan semantics)
        if (_isAudioOnly) {
            for (RTCRtpTransceiver *transceiver in self->_peerConnection.transceivers) {
                if (transceiver.mediaType == RTCRtpMediaTypeVideo) {
                    [transceiver stopInternal];
                    NSLog(@"Stop video transceiver in audio only peer connections.");
                }
            }
        }

        // Create answer
        RTCMediaConstraints *constraints = [self defaultAnswerConstraints];

        __weak NCPeerConnection *weakSelf = self;
        [self->_peerConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
            [[WebRTCCommon shared] dispatch:^{
                NCPeerConnection *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf peerConnectionDidCreateLocalSessionDescription:sdp error:error];
                }
            }];
        }];
    }

    if (self->_peerConnection.remoteDescription) {
        [self drainRemoteCandidates];
    }
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
    
    if (_isAudioOnly) {
        mandatoryConstraints = @{
                                 @"OfferToReceiveAudio" : @"true",
                                 @"OfferToReceiveVideo" : @"false"
                                 };
    }
    
    NSDictionary *optionalConstraints = @{
                                          @"internalSctpDataChannels": @"true",
                                          @"DtlsSrtpKeyAgreement": @"true"
                                          };
    
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                        initWithMandatoryConstraints:mandatoryConstraints
                                        optionalConstraints:optionalConstraints];
    return constraints;
}

- (RTCMediaConstraints *)publisherOfferConstraints
{
    NSDictionary *mandatoryConstraints = @{
                                           @"OfferToReceiveAudio" : @"false",
                                           @"OfferToReceiveVideo" : @"false"
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

- (NSString *)stringForSignalingState:(RTCSignalingState)state
{
    switch (state) {
        case RTCSignalingStateStable:
            return @"Stable";
            break;
        case RTCSignalingStateHaveLocalOffer:
            return @"Have Local Offer";
            break;
        case RTCSignalingStateHaveRemoteOffer:
            return @"Have Remote Offer";
            break;
        case RTCSignalingStateClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (NSString *)stringForConnectionState:(RTCIceConnectionState)state
{
    switch (state) {
        case RTCIceConnectionStateNew:
            return @"New";
            break;
        case RTCIceConnectionStateChecking:
            return @"Checking";
            break;
        case RTCIceConnectionStateConnected:
            return @"Connected";
            break;
        case RTCIceConnectionStateCompleted:
            return @"Completed";
            break;
        case RTCIceConnectionStateFailed:
            return @"Failed";
            break;
        case RTCIceConnectionStateDisconnected:
            return @"Disconnected";
            break;
        case RTCIceConnectionStateClosed:
            return @"Closed";
            break;
        default:
            return @"Other state";
            break;
    }
}

- (NSString *)stringForGatheringState:(RTCIceGatheringState)state
{
    switch (state) {
        case RTCIceGatheringStateNew:
            return @"New";
            break;
        case RTCIceGatheringStateGathering:
            return @"Gathering";
            break;
        case RTCIceGatheringStateComplete:
            return @"Complete";
            break;
        default:
            return @"Other state";
            break;
    }
}

@end
