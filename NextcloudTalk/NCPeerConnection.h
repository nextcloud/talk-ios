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
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, strong) RTCDataChannel *localDataChannel;
@property (nonatomic, strong) RTCDataChannel *remoteDataChannel;
@property (nonatomic, assign) BOOL isRemoteAudioDisabled;
@property (nonatomic, assign) BOOL isRemoteVideoDisabled;
@property (nonatomic, assign) BOOL isPeerSpeaking;
@property (nonatomic, assign) BOOL isHandRaised;
@property (nonatomic, assign) BOOL showRemoteVideoInOriginalSize;
@property (nonatomic, strong, readonly) NSMutableArray *queuedRemoteCandidates;
@property (nonatomic, strong) RTCMediaStream *remoteStream;

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

@end
