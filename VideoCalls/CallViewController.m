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
#import "NCAPIController.h"
#import "NCSettingsController.h"
#import "UIImageView+AFNetworking.h"

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
    NSTimer *_buttonsContainerTimer;
}

@property (nonatomic, strong) IBOutlet UIView *buttonsContainerView;
@property (nonatomic, strong) IBOutlet UIButton *audioMuteButton;
@property (nonatomic, strong) IBOutlet UIButton *videoDisableButton;
@property (nonatomic, strong) IBOutlet UIButton *switchCameraButton;
@property (nonatomic, strong) IBOutlet UIButton *hangUpButton;
@property (nonatomic, strong) IBOutlet UICollectionView *collectionView;
@property (nonatomic, strong) IBOutlet UICollectionViewFlowLayout *flowLayout;

@end

@implementation CallViewController

@synthesize delegate = _delegate;

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString*)displayName
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _callController = [[NCCallController alloc] initWithDelegate:self];
    _callController.room = room;
    _callController.userDisplayName = displayName;
    _room = room;
    _peersInCall = [[NSMutableArray alloc] init];
    _renderersDict = [[NSMutableDictionary alloc] init];
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    [_callController startCall];
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleButtonsContainer)];
    [tapGestureRecognizer setNumberOfTapsRequired:1];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    
    [self.audioMuteButton.layer setCornerRadius:24.0f];
    [self.videoDisableButton.layer setCornerRadius:24.0f];
    [self.switchCameraButton.layer setCornerRadius:24.0f];
    [self.hangUpButton.layer setCornerRadius:24.0f];
    
    [self setButtonsContainerTimer];
    
    self.collectionView.delegate = self;
    
    self.waitingLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.waitingLabel.numberOfLines = 0;
    
    self.waitingImageView.layer.cornerRadius = 64;
    self.waitingImageView.layer.masksToBounds = YES;
    
    [self setWaitingScreen];
    
    [self.localAvatarView setImageWithURLRequest:[[NCAPIController sharedInstance]
                                                  createAvatarRequestForUser:[NCSettingsController sharedInstance].ncUser andSize:160]
                            placeholderImage:nil success:nil failure:nil];
    self.localAvatarView.layer.cornerRadius = 40;
    self.localAvatarView.layer.masksToBounds = YES;
    self.localAvatarView.hidden = YES;

    
    [self.collectionView registerNib:[UINib nibWithNibName:kCallParticipantCellNibName bundle:nil] forCellWithReuseIdentifier:kCallParticipantCellIdentifier];
    
    if (@available(iOS 11.0, *)) {
        [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - User Interface

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

- (void)setWaitingScreen
{
    if (_room.type == kNCRoomTypeOneToOneCall) {
        self.waitingLabel.text = [NSString stringWithFormat:@"Waiting for %@ to join call…", _room.displayName];
        [self.waitingImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:256]
                                     placeholderImage:nil success:nil failure:nil];
    } else {
        self.waitingLabel.text = @"Waiting for others to join call…";
        
        if (_room.type == kNCRoomTypeGroupCall) {
            [self.waitingImageView setImage:[UIImage imageNamed:@"group-white85"]];
        } else {
            [self.waitingImageView setImage:[UIImage imageNamed:@"public-white85"]];
        }
        
        self.waitingImageView.backgroundColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
        self.waitingImageView.contentMode = UIViewContentModeCenter;
    }
    
    [self setWaitingScreenVisibility];
}

- (void)setWaitingScreenVisibility
{
    self.collectionView.backgroundView = self.waitingView;
    
    if (_peersInCall.count > 0) {
        self.collectionView.backgroundView = nil;
    }
}

- (void)toggleButtonsContainer {
    CGRect buttonsContainerFrame = self.buttonsContainerView.frame;
    [UIView animateWithDuration:0.3f animations:^{
        if (self.buttonsContainerView.frame.origin.x < 0.0f) {
            self.buttonsContainerView.frame = CGRectMake(0.0f, buttonsContainerFrame.origin.y, buttonsContainerFrame.size.width, buttonsContainerFrame.size.height);
            [self.buttonsContainerView setAlpha:1.0f];
            [self setButtonsContainerTimer];
        } else {
            self.buttonsContainerView.frame = CGRectMake(-72.0f, buttonsContainerFrame.origin.y, buttonsContainerFrame.size.width, buttonsContainerFrame.size.height);
            [self.buttonsContainerView setAlpha:0.0f];
            [self invalidateButtonsContainerTimer];
        }
        [self.view layoutIfNeeded];
    }];
}

- (void)setButtonsContainerTimer
{
    [self invalidateButtonsContainerTimer];
    _buttonsContainerTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(toggleButtonsContainer) userInfo:nil repeats:NO];
}

- (void)invalidateButtonsContainerTimer
{
    [_buttonsContainerTimer invalidate];
    _buttonsContainerTimer = nil;
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
        [_captureController stopCapture];
        [_localAvatarView setHidden:NO];
        [_switchCameraButton setEnabled:NO];
        [videoButton setImage:[UIImage imageNamed:@"video-off"] forState:UIControlStateNormal];
    } else {
        [_callController enableVideo:YES];
        [_captureController startCapture];
        [_localAvatarView setHidden:YES];
        [_switchCameraButton setEnabled:YES];
        [videoButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
    }
}
- (IBAction)switchCameraButtonPressed:(id)sender
{
    [self switchCamera];
}

- (void)switchCamera
{
    [_captureController switchCamera];
    [self flipLocalVideoView];
}

- (void)flipLocalVideoView
{
    CATransition *animation = [CATransition animation];
    animation.duration = .5f;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.type = @"oglFlip";
    animation.subtype = kCATransitionFromRight;
    
    [self.localVideoView.layer addAnimation:animation forKey:nil];
}

- (IBAction)hangupButtonPressed:(id)sender
{
    [self hangup];
}

- (void)hangup
{
    self.waitingLabel.text = @"Call ended";
    
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
    [self setWaitingScreenVisibility];
    return [_peersInCall count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CallParticipantViewCell *cell = (CallParticipantViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:kCallParticipantCellIdentifier forIndexPath:indexPath];
    NCPeerConnection *peerConnection = [_peersInCall objectAtIndex:indexPath.row];
    
    [cell setVideoView:[_renderersDict objectForKey:peerConnection.peerId]];
    [cell setUserAvatar:[_callController getUserIdFromSessionId:peerConnection.peerId]];
    [cell setDisplayName:peerConnection.peerName];
    [cell setAudioDisabled:peerConnection.isRemoteAudioDisabled];
    [cell setVideoDisabled:peerConnection.isRemoteVideoDisabled];
    
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
    if (state == RTCIceConnectionStateClosed) {
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
    } else if ([message isEqualToString:@"videoOn"] || [message isEqualToString:@"videoOff"]) {
        [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
            [cell setVideoDisabled:peer.isRemoteVideoDisabled];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        CallParticipantViewCell *cell = (id)[self.collectionView cellForItemAtIndexPath:indexPath];
        block(cell);
    });
}

@end
