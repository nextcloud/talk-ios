/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

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
//- (void)peerConnectionDidOpenStatusDataChannel:(NCPeerConnection *)peerConnection;

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

@property (nonatomic, copy, readonly) NSString *peerIdentifier; // "peerId-sid"
@property (nonatomic, copy) NSString *peerId;
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, copy) NSString *peerName;
@property (nonatomic, copy) NSString *roomType;
@property (nonatomic, assign) BOOL isAudioOnly;
@property (nonatomic, assign) BOOL isMCUPublisherPeer;
@property (nonatomic, assign) BOOL isDummyPeer;
@property (nonatomic, assign) BOOL isOwnScreensharePeer;
@property (nonatomic, assign) BOOL isRemoteAudioDisabled;
@property (nonatomic, assign) BOOL isRemoteVideoDisabled;
@property (nonatomic, assign) BOOL isPeerSpeaking;
@property (nonatomic, assign) BOOL isHandRaised;
@property (nonatomic, assign) BOOL showRemoteVideoInOriginalSize;
@property (nonatomic, strong, readonly) NSMutableArray *queuedRemoteCandidates;
@property (nonatomic, assign) NSInteger addedTime;

- (instancetype)initWithSessionId:(NSString *)sessionId sid:(NSString *)sid andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly;
- (instancetype)initForPublisherWithSessionId:(NSString *)sessionId andICEServers:(NSArray *)iceServers forAudioOnlyCall:(BOOL)audioOnly;
- (void)addICECandidate:(RTCIceCandidate *)candidate;
- (void)setRemoteDescription:(RTCSessionDescription *)sessionDescription;
- (void)sendPublisherOffer;
- (void)sendOffer;
- (void)sendDataChannelMessageOfType:(NSString *)type withPayload:(id)payload;
- (void)setStatusForDataChannelMessageType:(NSString *)type withPayload:(id)payload;
- (void)drainRemoteCandidates;
- (void)close;
- (RTCPeerConnection *)getPeerConnection;
- (RTCMediaStream *)getRemoteStream;
- (BOOL)hasRemoteStream;

@end
