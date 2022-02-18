/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
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


@interface NCPeerConnection () <RTCPeerConnectionDelegate, RTCDataChannelDelegate>

@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong) NSMutableArray *queuedRemoteCandidates;

@end

@implementation NCPeerConnection

- (instancetype)initWithSessionId:(NSString *)sessionId andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly
{
    self = [super init];
    
    if (self) {
        RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
        RTCDefaultVideoDecoderFactory *decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
        _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory decoderFactory:decoderFactory];
        
        RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
                                            initWithMandatoryConstraints:nil
                                            optionalConstraints:nil];
        
        RTCConfiguration *config = [[RTCConfiguration alloc] init];
        [config setIceServers:iceServers];
        
        RTCPeerConnection *peerConnection = [_peerConnectionFactory peerConnectionWithConfiguration:config
                                                                                        constraints:constraints
                                                                                           delegate:self];
        
        _peerConnection = peerConnection;
        _peerId = sessionId;
        _isAudioOnly = audioOnly;
    }
    
    return self;
}

- (instancetype)initForPublisherWithSessionId:(NSString *)sessionId andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly
{
    self = [self initWithSessionId:sessionId andICEServers:iceServers forAudioOnlyCall:audioOnly];
    
    if (self) {
        _isMCUPublisherPeer = YES;
    }
    
    return self;
}

#pragma mark - NSObject

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

- (void)addICECandidate:(RTCIceCandidate *)candidate
{
    BOOL queueCandidates = self.peerConnection == nil || self.peerConnection.signalingState != RTCSignalingStateStable;
    
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

- (void)removeRemoteCandidates
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    [self.queuedRemoteCandidates removeAllObjects];
    self.queuedRemoteCandidates = nil;
}

- (void)setRemoteDescription:(RTCSessionDescription *)sessionDescription
{
    __weak NCPeerConnection *weakSelf = self;
    RTCSessionDescription *sdpPreferringCodec = [ARDSDPUtils descriptionForDescription:sessionDescription preferredVideoCodec:@"H264"];
    [_peerConnection setRemoteDescription:sdpPreferringCodec completionHandler:^(NSError *error) {
        NCPeerConnection *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf peerConnectionDidSetRemoteSessionDescription:sdpPreferringCodec error:error];
        }
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
    //Create data channel before creating the offer to enable data channels
    RTCDataChannelConfiguration* config = [[RTCDataChannelConfiguration alloc] init];
    config.isNegotiated = NO;
    _localDataChannel = [_peerConnection dataChannelForLabel:@"status" configuration:config];
    _localDataChannel.delegate = self;
    // Create offer
    __weak NCPeerConnection *weakSelf = self;
    [_peerConnection offerForConstraints:constraints completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
        NCPeerConnection *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf peerConnectionDidCreateLocalSessionDescription:sdp error:error];
        }
    }];
}

- (void)setStatusForDataChannelMessageType:(NSString *)type withPayload:(id)payload
{
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
        }
        
        [self.delegate peerConnection:self didReceiveStatusDataChannelMessage:type];
    }
}

- (void)close
{
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

#pragma mark - RTCPeerConnectionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged
{
    NSLog(@"Signaling state with '%@' changed to: %@", self.peerId, [self stringForSignalingState:stateChanged]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Received %lu video tracks and %lu audio tracks from %@",
              (unsigned long)stream.videoTracks.count,
              (unsigned long)stream.audioTracks.count,
              self.peerId);
        
        self.remoteStream = stream;
        [self.delegate peerConnection:self didAddStream:stream];
        
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    NSLog(@"Stream was removed from %@.", self.peerId);
#warning Check if if is the same stream?
    self.remoteStream = nil;
    [self.delegate peerConnection:self didRemoveStream:stream];
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    NSLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    NSLog(@"ICE state with '%@' changed to: %@", self.peerId, [self stringForConnectionState:newState]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate peerConnection:self didChangeIceConnectionState:newState];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    NSLog(@"ICE gathering state with '%@' changed to : %@", self.peerId, [self stringForGatheringState:newState]);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NSLog(@"Peer '%@' did generate Ice Candidate: %@", self.peerId, candidate);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate peerConnection:self didGenerateIceCandidate:candidate];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates
{
    NSLog(@"PeerConnection didRemoveIceCandidates delegate has been called.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    if ([dataChannel.label isEqualToString:@"status"] || [dataChannel.label isEqualToString:@"JanusDataChannel"]) {
        _remoteDataChannel = dataChannel;
        _remoteDataChannel.delegate = self;
        NSLog(@"Remote data channel '%@' was opened.", dataChannel.label);
    } else {
        NSLog(@"Data channel '%@' was opened.", dataChannel.label);
    }
}

#pragma mark - RTCDataChannelDelegate

- (void)dataChannelDidChangeState:(RTCDataChannel *)dataChannel
{
    NSLog(@"Data cahnnel '%@' did change state: %ld", dataChannel.label, (long)dataChannel.readyState);
    if (dataChannel.readyState == RTCDataChannelStateOpen && [dataChannel.label isEqualToString:@"status"]) {
        [self.delegate peerConnectionDidOpenStatusDataChannel:self];
    }
}

- (void)dataChannel:(RTCDataChannel *)dataChannel didReceiveMessageWithBuffer:(RTCDataBuffer *)buffer
{
    NSDictionary *message = [self getDataChannelMessageFromJSONData:buffer.data];
    NSString *messageType = [message objectForKey:@"type"];
    id messagePayload = [message objectForKey:@"payload"];
    
    [self setStatusForDataChannelMessageType:messageType withPayload:messagePayload];
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
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnectionDidCreateLocalSessionDescription:(RTCSessionDescription *)sdp error:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to create local session description for peer %@. Error: %@", _peerId, error);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Did create local session description of type %@ for peer %@", [RTCSessionDescription stringForType:sdp.type], self->_peerId);
        // Set H264 as preferred codec.
        RTCSessionDescription *sdpPreferringCodec = [ARDSDPUtils descriptionForDescription:sdp preferredVideoCodec:@"H264"];
        __weak NCPeerConnection *weakSelf = self;
        [self->_peerConnection setLocalDescription:sdpPreferringCodec completionHandler:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to set local session description: %@", error);
                return;
            }
            NCPeerConnection *strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf.delegate peerConnection:strongSelf needsToSendSessionDescription:sdpPreferringCodec];
            }
        }];
    });
}

- (void)peerConnectionDidSetRemoteSessionDescription:(RTCSessionDescription *)sessionDescription error:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to set remote session description for peer %@. Error: %@", _peerId, error);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Did set remote session description of type %@ for peer %@", [RTCSessionDescription stringForType:sessionDescription.type], self->_peerId);
        // If we just set a remote offer we need to create an answer and set it as local description.
        if (sessionDescription.type == RTCSdpTypeOffer) {
            NSLog(@"Creating answer for peer %@", self->_peerId);
            //Create data channel before sending answer
            RTCDataChannelConfiguration* config = [[RTCDataChannelConfiguration alloc] init];
            config.isNegotiated = NO;
            self->_localDataChannel = [self->_peerConnection dataChannelForLabel:@"status" configuration:config];
            self->_localDataChannel.delegate = self;
            // Create answer
            RTCMediaConstraints *constraints = [self defaultAnswerConstraints];
            __weak NCPeerConnection *weakSelf = self;
            [self->_peerConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription *sdp, NSError *error) {
                NCPeerConnection *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf peerConnectionDidCreateLocalSessionDescription:sdp error:error];
                }
            }];
        }
        
        if (self->_peerConnection.remoteDescription) {
            [self drainRemoteCandidates];
        }
    });
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
