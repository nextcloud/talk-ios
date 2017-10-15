//
//  CallViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 31.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "CallViewController.h"

#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCVideoTrack.h>
#import "ARDSettingsModel.h"
#import "ARDCaptureController.h"
#import "CallParticipantViewCell.h"
#import "NBMPeersFlowLayout.h"
#import "NCCallController.h"

typedef NS_ENUM(NSInteger, CallState) {
    CallStateJoining,
    CallStateWaitingParticipants,
    CallStateInCall
};

@interface CallViewController () <NCCallControllerDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, RTCEAGLVideoViewDelegate>
{
    CallState _callState;
    NSMutableArray *_peersInCall;
    NSMutableDictionary *_renderersDict;
    NCCallController *_callController;
    ARDCaptureController *_captureController;
}

@property (nonatomic, strong) IBOutlet UICollectionView *collectionView;
@property (nonatomic, strong) IBOutlet UICollectionViewFlowLayout *flowLayout;

@end

@implementation CallViewController

@synthesize delegate = _delegate;

- (instancetype)initCallInRoom:(NSString *)room asUser:(NSString*)displayName
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _callController = [[NCCallController alloc] initWithDelegate:self];
    _callController.room = room;
    _callController.userDisplayName = displayName;
    _peersInCall = [[NSMutableArray alloc] init];
    _renderersDict = [[NSMutableDictionary alloc] init];
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    [_callController startCall];
    
    self.collectionView.delegate = self;
    [self.collectionView registerNib:[UINib nibWithNibName:kCallParticipantCellNibName bundle:nil] forCellWithReuseIdentifier:kCallParticipantCellIdentifier];
    
    if (@available(iOS 11.0, *)) {
        [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Call State

- (void)setCallState:(CallState)state
{
    switch (state) {
        case CallStateJoining:
            break;
        
        case CallStateWaitingParticipants:
            break;
            
        case CallStateInCall:
            break;
            
        default:
            break;
    }
}

#pragma mark - Call actions

- (IBAction)audioButtonPressed:(id)sender
{
    UIButton *audioButton = sender;
    if ([_callController isAudioEnabled]) {
        [_callController enableAudio:NO];
        [audioButton setImage:[UIImage imageNamed:@"audio-off"] forState:UIControlStateNormal];
    } else {
        [_callController enableAudio:YES];
        [audioButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
    }
}

- (IBAction)videoButtonPressed:(id)sender
{
    UIButton *videoButton = sender;
    if ([_callController isVideoEnabled]) {
        [_callController enableVideo:NO];
        [videoButton setImage:[UIImage imageNamed:@"video-off"] forState:UIControlStateNormal];
    } else {
        [_callController enableVideo:YES];
        [videoButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
    }
}

- (IBAction)hangupButtonPressed:(id)sender {
    [self hangup];
}

- (void)hangup
{
    [_localVideoView.captureSession stopRunning];
    _localVideoView.captureSession = nil;
    [_captureController stopCapture];
    _captureController = nil;
    
    for (NCPeerConnection *peerConnection in _peersInCall) {
        RTCEAGLVideoView *renderer = [_renderersDict objectForKey:peerConnection.peerId];
        [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:renderer];
        [_renderersDict removeObjectForKey:peerConnection.peerId];
    }
    
    [_callController leaveCall];
}

- (void)finishCall
{
    _callController = nil;
    [self.delegate viewControllerDidFinish:self];
}

- (void)dealloc
{
    NSLog(@"CallViewController dealloc");
}

#pragma mark - UICollectionView Datasource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [_peersInCall count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CallParticipantViewCell *cell = (CallParticipantViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:kCallParticipantCellIdentifier forIndexPath:indexPath];
    NCPeerConnection *peerConnection = [_peersInCall objectAtIndex:indexPath.row];
    
    [cell setVideoView:[_renderersDict objectForKey:peerConnection.peerId]];
    [cell setDisplayName:peerConnection.peerName];
    [cell setAudioDisabled:peerConnection.isRemoteAudioDisabled];
    
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGRect frame = [NBMPeersFlowLayout frameForWithNumberOfItems:_peersInCall.count
                                                             row:indexPath.row
                                                     contentSize:self.collectionView.frame.size];
    return frame.size;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.collectionView reloadData];
}

#pragma mark - Call Controller delegate

- (void)callControllerDidJoinCall:(NCCallController *)callController
{
    [self setCallState:CallStateWaitingParticipants];
    
}
- (void)callControllerDidEndCall:(NCCallController *)callController
{
    [self finishCall];
}
- (void)callController:(NCCallController *)callController peerJoined:(NCPeerConnection *)peer
{
    // Start adding cell for that peer and wait until add
}

- (void)callController:(NCCallController *)callController peerLeft:(NCPeerConnection *)peer
{
    RTCEAGLVideoView *renderer = [_renderersDict objectForKey:peer.peerId];
    [[peer.remoteStream.videoTracks firstObject] removeRenderer:renderer];
    [_renderersDict removeObjectForKey:peer.peerId];
    [_peersInCall removeObject:peer];
    [self.collectionView reloadData];
}

- (void)callController:(NCCallController *)callController didCreateLocalVideoCapturer:(RTCCameraVideoCapturer *)videoCapturer
{
    _localVideoView.captureSession = videoCapturer.captureSession;
    
    ARDSettingsModel *settingsModel = [[ARDSettingsModel alloc] init];
    _captureController = [[ARDCaptureController alloc] initWithCapturer:videoCapturer settings:settingsModel];
    [_captureController startCapture];
}
- (void)callController:(NCCallController *)callController didAddLocalStream:(RTCMediaStream *)localStream
{
}
- (void)callController:(NCCallController *)callController didRemoveLocalStream:(RTCMediaStream *)localStream
{
}
- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    RTCEAGLVideoView *renderView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectZero];
    renderView.delegate = self;
    RTCVideoTrack *remoteVideoTrack = [remotePeer.remoteStream.videoTracks firstObject];
    [remoteVideoTrack addRenderer:renderView];
    [_renderersDict setObject:renderView forKey:remotePeer.peerId];
    [_peersInCall addObject:remotePeer];
    [self.collectionView reloadData];
}
- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    
}
- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer
{
    if (state == RTCIceConnectionStateDisconnected) {
        [_peersInCall removeObject:peer];
        [self.collectionView reloadData];
    }
}
- (void)callController:(NCCallController *)callController didAddDataChannel:(RTCDataChannel *)dataChannel
{
}

- (void)callController:(NCCallController *)callController didReceiveDataChannelMessage:(NSString *)message fromPeer:(NCPeerConnection *)peer
{
    if ([message isEqualToString:@"audioOn"] || [message isEqualToString:@"audioOff"]) {
        [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
            [cell setAudioDisabled:peer.isRemoteAudioDisabled];
        }];
    }
}
- (void)callController:(NCCallController *)callController didReceiveNick:(NSString *)nick fromPeer:(NCPeerConnection *)peer
{
    [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
        [cell setDisplayName:nick];
    }];
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    for (RTCEAGLVideoView *rendererView in [_renderersDict allValues]) {
        if ([videoView isEqual:rendererView]) {
            rendererView.frame = CGRectMake(0, 0, size.width, size.height);
        }
    }
    
    [self.collectionView reloadData];
}

#pragma mark - Cell updates

- (NSIndexPath *)indexPathOfPeer:(NCPeerConnection *)peer {
    NSUInteger idx = [_peersInCall indexOfObject:peer];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
    
    return indexPath;
}

- (void)updatePeer:(NCPeerConnection *)peer block:(void(^)(CallParticipantViewCell* cell))block {
    NSIndexPath *indexPath = [self indexPathOfPeer:peer];
    CallParticipantViewCell *cell = (id)[self.collectionView cellForItemAtIndexPath:indexPath];
    block(cell);
}

@end
