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
#import "DBImageColorPicker.h"
#import "AFImageDownloader.h"
#import "NCImageSessionManager.h"
#import "NBMPeersFlowLayout.h"
#import "NCCallController.h"
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCRoomController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "UIImageView+AFNetworking.h"
#import "CallKitManager.h"

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
    UITapGestureRecognizer *_tapGestureForDetailedView;
    NSTimer *_detailedViewTimer;
    NSString *_displayName;
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

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString *)displayName audioOnly:(BOOL)audioOnly
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _room = room;
    _displayName = displayName;
    _isAudioOnly = audioOnly;
    _peersInCall = [[NSMutableArray alloc] init];
    _renderersDict = [[NSMutableDictionary alloc] init];
    
    // Set image downloader to avatar background imageviews.
    // Do not cache images so I can get 200 or 201 from the avatar requests.
    AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                          initWithSessionManager:[NCImageSessionManager sharedInstance]
                                          downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                          maximumActiveDownloads:4
                                          imageCache:nil];
    [AvatarBackgroundImageView setSharedImageDownloader:imageDownloader];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerDidEndCall:) name:CallKitManagerDidEndCallNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerDidChangeAudioMute:) name:CallKitManagerDidChangeAudioMuteNotification object:nil];
    
    return self;
}

- (void)startCallWithSessionId:(NSString *)sessionId
{
    _callController = [[NCCallController alloc] initWithDelegate:self inRoom:_room forAudioOnlyCall:_isAudioOnly withSessionId:sessionId];
    _callController.userDisplayName = _displayName;
    
    [_callController startCall];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _tapGestureForDetailedView = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showDetailedViewWithTimer)];
    [_tapGestureForDetailedView setNumberOfTapsRequired:1];
    
    [self.audioMuteButton.layer setCornerRadius:30.0f];
    [self.speakerButton.layer setCornerRadius:30.0f];
    [self.videoDisableButton.layer setCornerRadius:30.0f];
    [self.hangUpButton.layer setCornerRadius:30.0f];
    
    [self adjustButtonsConainer];
    
    self.collectionView.delegate = self;
    
    [self createWaitingScreen];
    
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
    for (UICollectionViewCell *cell in _collectionView.visibleCells) {
        CallParticipantViewCell * participantCell = (CallParticipantViewCell *) cell;
        [participantCell resizeRemoteVideoView];
    }
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

#pragma mark - Rooms manager notifications

- (void)didJoinRoom:(NSNotification *)notification
{
    NCRoomController *roomController = [notification.userInfo objectForKey:@"roomController"];
    if (![roomController.roomToken isEqualToString:_room.token]) {
        return;
    }
    
    if (!_callController) {
        [self startCallWithSessionId:roomController.userSessionId];
    }
}

- (void)providerDidChangeAudioMute:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (![roomToken isEqualToString:_room.token]) {
        return;
    }
    
    BOOL isMuted = [[notification.userInfo objectForKey:@"isMuted"] boolValue];
    if (isMuted) {
        [self muteAudio];
    } else {
        [self unmuteAudio];
    }
}

- (void)providerDidEndCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (![roomToken isEqualToString:_room.token]) {
        return;
    }
    
    [self hangup];
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
            localVideoSize = CGSizeMake(width, width * 3/4);
        }
    } else {
        if (width < height) {
            localVideoSize = CGSizeMake(height * 9/16, height);
        } else {
            localVideoSize = CGSizeMake(width, width * 9/16);
        }
    }
    
    CGRect localVideoRect = CGRectMake(16, 80, localVideoSize.width, localVideoSize.height);
    
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
            [[NCAudioController sharedInstance] setAudioSessionToVoiceChatMode];
        } else {
            // Only enable video if it was not disabled by the user.
            if (!_userDisabledVideo) {
                [self enableLocalVideo];
            }
            [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
        }
    }
}

#pragma mark - User Interface

- (void)setCallState:(CallState)state
{
    _callState = state;
    switch (state) {
        case CallStateJoining:
        case CallStateWaitingParticipants:
        {
            [self showWaitingScreen];
            [self invalidateDetailedViewTimer];
            [self showDetailedView];
            [self removeTapGestureForDetailedView];
        }
            break;
            
        case CallStateInCall:
        {
            [self hideWaitingScreen];
            if (!_isAudioOnly) {
                [self addTapGestureForDetailedView];
                [self showDetailedViewWithTimer];
            }
        }
            break;
            
        default:
            break;
    }
}

- (void)setCallStateForPeersInCall
{
    if ([_peersInCall count] > 0) {
        if (_callState != CallStateInCall) {
            [self setCallState:CallStateInCall];
        }
    } else {
        if (_callState == CallStateInCall) {
            [self setCallState:CallStateWaitingParticipants];
        }
    }
}

- (void)createWaitingScreen
{
    if (_room.type == kNCRoomTypeOneToOneCall) {
        self.waitingLabel.text = [NSString stringWithFormat:@"Waiting for %@ to join call…", _room.displayName];
        __weak AvatarBackgroundImageView *weakBGView = self.avatarBackgroundImageView;
        [self.avatarBackgroundImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:256]
                                              placeholderImage:nil success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                                  if ([response statusCode] == 200) {
                                                      CIContext *context = [CIContext contextWithOptions:nil];
                                                      CIImage *inputImage = [[CIImage alloc] initWithImage:image];
                                                      CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
                                                      [filter setValue:inputImage forKey:kCIInputImageKey];
                                                      [filter setValue:[NSNumber numberWithFloat:2.0f] forKey:@"inputRadius"];
                                                      CIImage *result = [filter valueForKey:kCIOutputImageKey];
                                                      CGImageRef cgImage = [context createCGImage:result fromRect:[inputImage extent]];
                                                      UIImage *finalImage = [UIImage imageWithCGImage:cgImage];
                                                      [weakBGView setImage:finalImage];
                                                      weakBGView.contentMode = UIViewContentModeScaleAspectFill;
                                                  } else if ([response statusCode] == 201) {
                                                      DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:image withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
                                                      [weakBGView setBackgroundColor:colorPicker.backgroundColor];
                                                      weakBGView.backgroundColor = [weakBGView.backgroundColor colorWithAlphaComponent:0.8];
                                                  }
                                              } failure:nil];
    } else {
        self.waitingLabel.text = @"Waiting for others to join call…";
        UIImage *avatarImage = [UIImage imageNamed:@"group-bg"];
        if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
            avatarImage = [UIImage imageNamed:@"file-bg"];
        } else if ([_room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
            avatarImage = [UIImage imageNamed:@"password-bg"];
        } else if (_room.type == kNCRoomTypeGroupCall) {
            avatarImage = [UIImage imageNamed:@"group-bg"];
        } else if (_room.type == kNCRoomTypePublicCall){
            avatarImage = (_room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"];
        }
        
        DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:avatarImage withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
        [self.avatarBackgroundImageView setBackgroundColor:colorPicker.backgroundColor];
        self.avatarBackgroundImageView.backgroundColor = [self.avatarBackgroundImageView.backgroundColor colorWithAlphaComponent:0.8];
    }
}

- (void)showWaitingScreen
{
    self.collectionView.backgroundView = self.waitingView;
}

- (void)hideWaitingScreen
{
    self.collectionView.backgroundView = nil;
}

- (void)addTapGestureForDetailedView
{
    [self.view addGestureRecognizer:_tapGestureForDetailedView];
}

- (void)removeTapGestureForDetailedView
{
    [self.view removeGestureRecognizer:_tapGestureForDetailedView];
}

- (void)showDetailedView
{
    [self showButtonsContainer];
    [self showPeersInfo];
}

- (void)showDetailedViewWithTimer
{
    [self showDetailedView];
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
    
    // Enable speaker button for iPhones only
    if(![[UIDevice currentDevice].model isEqualToString:@"iPhone"]) {
        _speakerButton.enabled = NO;
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
    if ([_callController isAudioEnabled]) {
        [self muteAudio];
    } else {
        [self unmuteAudio];
    }
}

- (void)muteAudio
{
    [_callController enableAudio:NO];
    [_audioMuteButton setImage:[UIImage imageNamed:@"audio-off"] forState:UIControlStateNormal];
}

- (void)unmuteAudio
{
    [_callController enableAudio:YES];
    [_audioMuteButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
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
    if ([[NCAudioController sharedInstance] isSpeakerActive]) {
        [self disableSpeaker];
    } else {
        [self enableSpeaker];
    }
}

- (void)disableSpeaker
{
    [[NCAudioController sharedInstance] setAudioSessionToVoiceChatMode];
    [_speakerButton setImage:[UIImage imageNamed:@"speaker-off"] forState:UIControlStateNormal];
}

- (void)enableSpeaker
{
    [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
    [_speakerButton setImage:[UIImage imageNamed:@"speaker"] forState:UIControlStateNormal];
}

- (IBAction)hangupButtonPressed:(id)sender
{
    [self hangup];
}

- (void)hangup
{
    [self.delegate callViewControllerWantsToBeDismissed:self];
    
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
    
    if (_callController) {
        [_callController leaveCall];
    } else {
        [self finishCall];
    }
}

- (void)finishCall
{
    _callController = nil;
    [self.delegate callViewControllerDidFinish:self];
}

#pragma mark - UICollectionView Datasource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    [self setCallStateForPeersInCall];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
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
