//
//  NCPeerConnection.h
//  VideoCalls
//
//  Created by Ivan Sein on 29.09.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WebRTC/RTCPeerConnection.h>
#import <WebRTC/RTCDataChannel.h>

@class NCPeerConnection;

@protocol NCPeerConnectionDelegate <NSObject>

/** Called when media is received on a new stream from remote peer. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream;

/** Called when a remote peer closes a stream. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream;

/** Called any time the IceConnectionState changes. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState;

/** Status data channel has been opened. */
- (void)peerConnectionDidOpenStatusDataChannel:(NCPeerConnection *)peerConnection;

/** Message received from status data channel has been opened. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didReceiveStatusDataChannelMessage:(NSString *)type;

/** Peer's nick received from status data channel has been opened. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didReceivePeerNick:(NSString *)nick;

/** New ice candidate has been found. */
- (void)peerConnection:(NCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate;

/** Called when a peer connection creates session description */
- (void)peerConnection:(NCPeerConnection *)peerConnection needsToSendSessionDescription:(RTCSessionDescription *)sessionDescription;

@end

@interface NCPeerConnection : NSObject

@property (nonatomic, weak) id<NCPeerConnectionDelegate> delegate;

@property (nonatomic, copy) NSString *peerId;
@property (nonatomic, copy) NSString *peerName;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, assign) BOOL isInitiator;
@property (nonatomic, strong) RTCDataChannel *localDataChannel;
@property (nonatomic, strong) RTCDataChannel *remoteDataChannel;
@property (nonatomic, assign) BOOL isRemoteAudioDisabled;
@property (nonatomic, assign) BOOL isRemoteVideoDisabled;
@property (nonatomic, strong, readonly) NSMutableArray *queuedRemoteCandidates;
@property (nonatomic, strong) RTCMediaStream *remoteStream;
@property (nonatomic, assign) NSUInteger iceAttempts;

- (instancetype)initWithSessionId:(NSString *)sessionId;
- (void)addICECandidate:(RTCIceCandidate *)candidate;
- (void)setRemoteDescription:(RTCSessionDescription *)sessionDescription;
- (void)sendOffer;
- (void)sendDataChannelMessageOfType:(NSString *)type withPayload:(NSString *)payload;
- (void)drainRemoteCandidates;
- (void)removeRemoteCandidates;
- (void)close;

@end
