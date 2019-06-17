//
//  NCCallController.h
//  VideoCalls
//
//  Created by Ivan Sein on 02.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCPeerConnection.h"
#import "NCRoom.h"

@class NCCallController;
@class RTCCameraVideoCapturer;

typedef void (^GetUserIdForSessionIdCompletionBlock)(NSString *userId, NSError *error);

@protocol NCCallControllerDelegate<NSObject>

- (void)callControllerDidJoinCall:(NCCallController *)callController;
- (void)callControllerDidEndCall:(NCCallController *)callController;
- (void)callController:(NCCallController *)callController peerJoined:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController peerLeft:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didCreateLocalVideoCapturer:(RTCCameraVideoCapturer *)videoCapturer;
- (void)callController:(NCCallController *)callController didAddLocalStream:(RTCMediaStream *)localStream;
- (void)callController:(NCCallController *)callController didRemoveLocalStream:(RTCMediaStream *)localStream;
- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didAddDataChannel:(RTCDataChannel *)dataChannel;
- (void)callController:(NCCallController *)callController didReceiveDataChannelMessage:(NSString *)message fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveNick:(NSString *)nick fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveUnshareScreenFromPeer:(NCPeerConnection *)peer;
- (void)callControllerIsReconnectingCall:(NCCallController *)callController;

@end

@interface NCCallController : NSObject

@property (nonatomic, weak) id<NCCallControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, copy) NSString *userSessionId;
@property (nonatomic, copy) NSString *userDisplayName;


- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId;
- (void)startCall;
- (void)leaveCall;
- (BOOL)isVideoEnabled;
- (BOOL)isAudioEnabled;
- (void)enableVideo:(BOOL)enable;
- (void)enableAudio:(BOOL)enable;
- (NSString *)getUserIdFromSessionId:(NSString *)sessionId;
- (void)getUserIdInServerFromSessionId:(NSString *)sessionId withCompletionBlock:(GetUserIdForSessionIdCompletionBlock)block;

@end
