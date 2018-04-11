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
    NSTimer *_detailedViewTimer;
    BOOL _isAudioOnly;
    BOOL _userDisabledVideo;
}

@property (nonatomic, strong) IBOutlet UIView *buttonsContainerView;
@property (nonatomic, strong) IBOutlet UIButton *audioMuteButton;
@property (nonatomic, strong) IBOutlet UIButton *speakerButton;
@property (nonatomic, strong) IBOutlet UIButton *videoDisableButton;
@property (nonatomic, strong) IBOutlet UIButton *switchCameraButton;
@property (nonatomic, strong) IBOutlet UIButton *hangUpButton;
@property (nonatomic, strong) IBOutlet UICollectionView *collectionView;
@property (nonatomic, strong) IBOutlet UICollectionViewFlowLayout *flowLayout;

@end

@implementation CallViewController

@synthesize delegate = _delegate;

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString*)displayName audioOnly:(BOOL)audioOnly
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _callController = [[NCCallController alloc] initWithDelegate:self inRoom:room forAudioOnlyCall:audioOnly];
    _callController.userDisplayName = displayName;
    _room = room;
    _isAudioOnly = audioOnly;
    _peersInCall = [[NSMutableArray alloc] init];
    _renderersDict = [[NSMutableDictionary alloc] init];
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    [_callController startCall];
    
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showDetailedView)];
    [tapGestureRecognizer setNumberOfTapsRequired:1];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    
    [self.audioMuteButton.layer setCornerRadius:24.0f];
    [self.speakerButton.layer setCornerRadius:24.0f];
    [self.videoDisableButton.layer setCornerRadius:24.0f];
    [self.hangUpButton.layer setCornerRadius:24.0f];
    
    [self adjustButtonsConainer];
    [self setDetailedViewTimer];
    
    self.collectionView.delegate = self;
    
    self.waitingImageView.layer.cornerRadius = 64;
    self.waitingImageView.layer.masksToBounds = YES;
    
    [self setWaitingScreen];
    
    if ([[[NCSettingsController sharedInstance] videoSettingsModel] videoDisabledSettingFromStore] || _isAudioOnly) {
        _userDisabledVideo = YES;
        [self disableLocalVideo];
    }
    
    [self.collectionView registerNib:[UINib nibWithNibName:kCallParticipantCellNibName bundle:nil] forCellWithReuseIdentifier:kCallParticipantCellIdentifier];
    
    if (@available(iOS 11.0, *)) {
        [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:)
                                                 name:@"UIDeviceProximityStateDidChangeNotification" object:nil];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self setLocalVideoRect];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self setLocalVideoRect];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Local video

- (void)setLocalVideoRect
{
    CGSize localVideoSize = CGSizeMake(0, 0);
    
    CGFloat width = [UIScreen mainScreen].bounds.size.width / 5;
    CGFloat height = [UIScreen mainScreen].bounds.size.height / 5;
    
    NSString *videoResolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
    NSString *localVideoRes = [[[NCSettingsController sharedInstance] videoSettingsModel] readableResolution:videoResolution];
    
    if ([localVideoRes isEqualToString:@"Low"] || [localVideoRes isEqualToString:@"Normal"]) {
        if (width < height) {
            localVideoSize = CGSizeMake(height * 3/4, height);
        } else {
            localVideoSize = CGSizeMake(height * 4/3, height);
        }
    } else {
        if (width < height) {
            localVideoSize = CGSizeMake(height * 9/16, height);;
        } else {
            localVideoSize = CGSizeMake(height * 16/9, height);
        }
    }
    
    CGRect localVideoRect = CGRectMake(16, 62, localVideoSize.width, localVideoSize.height);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _localVideoView.frame = localVideoRect;
        _localVideoView.layer.cornerRadius = 4.0f;
        _localVideoView.layer.masksToBounds = YES;
    });
}

#pragma mark - Proximity sensor

- (void)sensorStateChange:(NSNotificationCenter *)notification
{
    if (!_isAudioOnly) {
        if ([[UIDevice currentDevice] proximityState] == YES) {
            [self disableLocalVideo];
            [_callController setAudioSessionToVoiceChatMode];
        } else {
            // Only enable video if it was not disabled by the user.
            if (!_userDisabledVideo) {
                [self enableLocalVideo];
            }
            [_callController setAudioSessionToVideoChatMode];
        }
    }
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

- (void)showDetailedView
{
    [self showButtonsContainer];
    [self showPeersInfo];
    [self setDetailedViewTimer];
}

- (void)hideDetailedView
{
    [self hideButtonsContainer];
    [self hidePeersInfo];
    [self invalidateDetailedViewTimer];
}

- (void)showButtonsContainer
{
    [UIView animateWithDuration:0.3f animations:^{
        [self.buttonsContainerView setAlpha:1.0f];
        [self.switchCameraButton setAlpha:1.0f];
        [self.view layoutIfNeeded];
    }];
}

- (void)hideButtonsContainer
{
    [UIView animateWithDuration:0.3f animations:^{
        [self.buttonsContainerView setAlpha:0.0f];
        [self.switchCameraButton setAlpha:0.0f];
        [self.view layoutIfNeeded];
    }];
}

- (void)adjustButtonsConainer
{
    if (_isAudioOnly) {
        _videoDisableButton.hidden = YES;
        _switchCameraButton.hidden = YES;
    } else {
        _speakerButton.hidden = YES;
    }
}

- (void)setDetailedViewTimer
{
    [self invalidateDetailedViewTimer];
    _detailedViewTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideDetailedView) userInfo:nil repeats:NO];
}

- (void)invalidateDetailedViewTimer
{
    [_detailedViewTimer invalidate];
    _detailedViewTimer = nil;
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
    if ([_callController isVideoEnabled]) {
        [self disableLocalVideo];
        _userDisabledVideo = YES;
    } else {
        [self enableLocalVideo];
        _userDisabledVideo = NO;
    }
}

- (void)disableLocalVideo
{
    [_callController enableVideo:NO];
    [_captureController stopCapture];
    [_localVideoView setHidden:YES];
    [_videoDisableButton setImage:[UIImage imageNamed:@"video-off"] forState:UIControlStateNormal];
}

- (void)enableLocalVideo
{
    [_callController enableVideo:YES];
    [_captureController startCapture];
    [_localVideoView setHidden:NO];
    [_videoDisableButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
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

- (IBAction)speakerButtonPressed:(id)sender
{
    if ([_callController isSpeakerActive]) {
        [self disableSpeaker];
    } else {
        [self enableSpeaker];
    }
}

- (void)disableSpeaker
{
    [_callController setAudioSessionToVoiceChatMode];
    [_speakerButton setImage:[UIImage imageNamed:@"speaker-off"] forState:UIControlStateNormal];
}

- (void)enableSpeaker
{
    [_callController setAudioSessionToVideoChatMode];
    [_speakerButton setImage:[UIImage imageNamed:@"speaker"] forState:UIControlStateNormal];
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
    [_localVideoView setHidden:YES];
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
    [self.delegate callViewControllerDidFinish:self];
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
    [cell setVideoDisabled: (_isAudioOnly) ? YES : peerConnection.isRemoteVideoDisabled];
    
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
    _captureController = [[ARDCaptureController alloc] initWithCapturer:videoCapturer settings:[[NCSettingsController sharedInstance] videoSettingsModel]];
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
    [self showDetailedView];
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
        if (!_isAudioOnly) {
            [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
                [cell setVideoDisabled:peer.isRemoteVideoDisabled];
            }];
        }
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

- (void)showPeersInfo
{
    NSArray *visibleCells = [_collectionView visibleCells];
    for (CallParticipantViewCell *cell in visibleCells) {
        [UIView animateWithDuration:0.3f animations:^{
            [cell.peerNameLabel setAlpha:1.0f];
            [cell.audioOffIndicator setAlpha:0.5f];
            [cell layoutIfNeeded];
        }];
    }
}

- (void)hidePeersInfo
{
    NSArray *visibleCells = [_collectionView visibleCells];
    for (CallParticipantViewCell *cell in visibleCells) {
        [UIView animateWithDuration:0.3f animations:^{
            [cell.peerNameLabel setAlpha:0.0f];
            [cell.audioOffIndicator setAlpha:0.0f];
            [cell layoutIfNeeded];
        }];
    }
}

@end
