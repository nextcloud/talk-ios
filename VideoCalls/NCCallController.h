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

@protocol NCCallControllerDelegate<NSObject>

- (void)callControllerDidJoinCall:(NCCallController *)callController;
- (void)callControllerDidEndCall:(NCCallController *)callController;
- (void)callController:(NCCallController *)callController peerJoined:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didCreateLocalVideoCapturer:(RTCCameraVideoCapturer *)videoCapturer;
- (void)callController:(NCCallController *)callController didAddLocalStream:(RTCMediaStream *)localStream;
- (void)callController:(NCCallController *)callController didRemoveLocalStream:(RTCMediaStream *)localStream;
- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer;
- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didAddDataChannel:(RTCDataChannel *)dataChannel;
- (void)callController:(NCCallController *)callController didReceiveDataChannelMessage:(NSString *)message fromPeer:(NCPeerConnection *)peer;
- (void)callController:(NCCallController *)callController didReceiveNick:(NSString *)nick fromPeer:(NCPeerConnection *)peer;

@end

@interface NCCallController : NSObject

@property (nonatomic, weak) id<NCCallControllerDelegate> delegate;
@property (nonatomic, copy) NSString *room;
@property (nonatomic, copy) NSString *userSessionId;
@property (nonatomic, copy) NSString *userDisplayName;
@property (nonatomic, strong) NSMutableDictionary *connectionsDict;
@property (nonatomic, strong) NSMutableArray *renderers;


- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate;
- (void)startCall;
- (void)leaveCall;
- (void)toggleCamera;
- (BOOL)isVideoEnabled;
- (BOOL)isAudioEnabled;
- (void)enableVideo:(BOOL)enable;
- (void)enableAudio:(BOOL)enable;

@end
