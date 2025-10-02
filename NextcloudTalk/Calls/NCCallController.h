/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCPeerConnection.h"
#import "NCRoom.h"

@class NCCallController;
@class RTCAudioTrack;
@class RTCVideoTrack;
@class NCCameraController;
@class TalkActor;

typedef void (^GetVideoEnabledStateCompletionBlock)(BOOL isEnabled);
typedef void (^GetAudioEnabledStateCompletionBlock)(BOOL isEnabled);

@protocol NCCallControllerDelegate<NSObject>

- (void)callControllerDidJoinCall:(NCCallController *)callController;
- (void)callControllerDidFailedJoiningCall:(NCCallController *)callController statusCode:(NSInteger)statusCode errorReason:(NSString *)errorReason;
- (void)callControllerDidEndCall:(NCCallController *)callController;
- (void)callController:(NCCallController *)callController peerJoined:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController peerLeft:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didCreateLocalAudioTrack:(RTCAudioTrack * _Nullable)audioTrack;
- (void)callController:(NCCallController *)callController didCreateLocalVideoTrack:(RTCVideoTrack * _Nullable)videoTrack;
- (void)callController:(NCCallController *)callController didCreateCameraController:(NCCameraController *)cameraController;
- (void)callController:(NCCallController *)callController userPermissionsChanged:(NCPermission)permissions;
- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didAddDataChannel:(RTCDataChannel *)dataChannel;
- (void)callController:(NCCallController *)callController didReceiveDataChannelMessage:(NSString *)message fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveNick:(NSString *)nick fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveUnshareScreenFromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveForceMuteActionForPeerId:(NSString *)peerId;
- (void)callController:(NCCallController *)callController didReceiveReaction:(NSString *)reaction fromPeer:(NCPeerConnection *)peer;
- (void)callControllerIsReconnectingCall:(NCCallController *)callController;
- (void)callControllerWantsToHangUpCall:(NCCallController *)callController;
- (void)callControllerDidChangeRecording:(NCCallController *)callController;
- (void)callControllerDidDrawFirstLocalFrame:(NCCallController *)callController;
- (void)callControllerDidChangeScreenrecording:(NCCallController *)callController;
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
@property (nonatomic, strong) NSArray *silentFor;
@property (nonatomic, assign) BOOL recordingConsent;
@property (nonatomic, assign) BOOL screensharingActive;


- (instancetype _Nonnull)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId andVoiceChatMode:(BOOL)voiceChatMode;
- (void)startCall;
- (void)leaveCallForAll:(BOOL)allParticipants;
- (void)getVideoEnabledStateWithCompletionBlock:(GetVideoEnabledStateCompletionBlock)block;
- (void)getAudioEnabledStateWithCompletionBlock:(GetAudioEnabledStateCompletionBlock)block;
- (void)switchCamera;
- (void)enableVideo:(BOOL)enable;
- (void)enableAudio:(BOOL)enable;
- (void)raiseHand:(BOOL)raised;
- (void)sendReaction:(NSString *)reaction;
- (void)startRecording;
- (void)stopRecording;
- (void)startScreenshare;
- (void)stopScreenshare;
- (TalkActor * _Nullable)getActorFromSessionId:(NSString * _Nonnull)sessionId;
- (NSString *)signalingSessionId;
- (BOOL)isBackgroundBlurEnabled;
- (void)enableBackgroundBlur:(BOOL)enable;
- (void)stopCapturing;
- (BOOL)isCameraAccessAvailable;
- (BOOL)isMicrophoneAccessAvailable;
- (void)forceMuteOthers;

- (void)willSwitchToCall:(NSString *)token;

@end
