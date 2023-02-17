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

#import "NCPeerConnection.h"
#import "NCRoom.h"

@class NCCallController;
@class RTCAudioTrack;
@class RTCVideoTrack;
@class RTCCameraVideoCapturer;

typedef void (^GetVideoEnabledStateCompletionBlock)(BOOL isEnabled);
typedef void (^GetAudioEnabledStateCompletionBlock)(BOOL isEnabled);

@protocol NCCallControllerDelegate<NSObject>

- (void)callControllerDidJoinCall:(NCCallController *)callController;
- (void)callControllerDidFailedJoiningCall:(NCCallController *)callController statusCode:(NSNumber *)statusCode errorReason:(NSString *)errorReason;
- (void)callControllerDidEndCall:(NCCallController *)callController;
- (void)callController:(NCCallController *)callController peerJoined:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController peerLeft:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didCreateLocalAudioTrack:(RTCAudioTrack *)audioTrack;
- (void)callController:(NCCallController *)callController didCreateLocalVideoTrack:(RTCVideoTrack *)videoTrack;
- (void)callController:(NCCallController *)callController didCreateLocalVideoCapturer:(RTCCameraVideoCapturer *)videoCapturer;
- (void)callController:(NCCallController *)callController userPermissionsChanged:(NSInteger)permissions;
- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didAddDataChannel:(RTCDataChannel *)dataChannel;
- (void)callController:(NCCallController *)callController didReceiveDataChannelMessage:(NSString *)message fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveNick:(NSString *)nick fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveUnshareScreenFromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveForceMuteActionForPeerId:(NSString *)peerId;
- (void)callControllerIsReconnectingCall:(NCCallController *)callController;
- (void)callControllerWantsToHangUpCall:(NCCallController *)callController;
- (void)callControllerDidChangeRecording:(NCCallController *)callController;
- (void)callController:(NCCallController *)callController isSwitchingToCall:(NSString *)token withAudioEnabled:(BOOL)audioEnabled andVideoEnabled:(BOOL)videoEnabled;

@end

@interface NCCallController : NSObject

@property (nonatomic, weak) id<NCCallControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, copy) NSString *userSessionId;
@property (nonatomic, copy) NSString *userDisplayName;
@property (nonatomic, assign) BOOL disableAudioAtStart;
@property (nonatomic, assign) BOOL disableVideoAtStart;
@property (nonatomic, assign) BOOL silentCall;


- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId andVoiceChatMode:(BOOL)voiceChatMode;
- (void)startCall;
- (void)leaveCall;
- (void)getVideoEnabledStateWithCompletionBlock:(GetVideoEnabledStateCompletionBlock)block;
- (void)getAudioEnabledStateWithCompletionBlock:(GetAudioEnabledStateCompletionBlock)block;
- (void)switchCamera;
- (void)enableVideo:(BOOL)enable;
- (void)enableAudio:(BOOL)enable;
- (void)raiseHand:(BOOL)raised;
- (void)startRecording;
- (void)stopRecording;
- (NSString *)getUserIdFromSessionId:(NSString *)sessionId;
- (NSString *)signalingSessionId;

- (void)willSwitchToCall:(NSString *)token;

@end
