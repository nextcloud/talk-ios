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
#import "NCImageSessionManager.h"
#import "NBMPeersFlowLayout.h"
#import "NCCallController.h"
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCRoomController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCSignalingMessage.h"
#import "UIImageView+AFNetworking.h"
#import "CallKitManager.h"

typedef NS_ENUM(NSInteger, CallState) {
    CallStateJoining,
    CallStateWaitingParticipants,
    CallStateReconnecting,
    CallStateInCall
};

@interface CallViewController () <NCCallControllerDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, RTCEAGLVideoViewDelegate, CallParticipantViewCellDelegate>
{
    CallState _callState;
    NSMutableArray *_peersInCall;
    NSMutableDictionary *_videoRenderersDict;
    NSMutableDictionary *_screenRenderersDict;
    NCCallController *_callController;
    ARDCaptureController *_captureController;
    UIView <RTCVideoRenderer> *_screenView;
    CGSize _screensharingSize;
    UITapGestureRecognizer *_tapGestureForDetailedView;
    NSTimer *_detailedViewTimer;
    NSString *_displayName;
    BOOL _isAudioOnly;
    BOOL _userDisabledVideo;
    BOOL _videoCallUpgrade;
    BOOL _hangingUp;
}

@property (nonatomic, strong) IBOutlet UIView *buttonsContainerView;
@property (nonatomic, strong) IBOutlet UIButton *audioMuteButton;
@property (nonatomic, strong) IBOutlet UIButton *speakerButton;
@property (nonatomic, strong) IBOutlet UIButton *videoDisableButton;
@property (nonatomic, strong) IBOutlet UIButton *switchCameraButton;
@property (nonatomic, strong) IBOutlet UIButton *hangUpButton;
@property (nonatomic, strong) IBOutlet UIButton *videoCallButton;
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
    _videoRenderersDict = [[NSMutableDictionary alloc] init];
    _screenRenderersDict = [[NSMutableDictionary alloc] init];
    
    // Use image downloader without cache so I can get 200 or 201 from the avatar requests.
    [AvatarBackgroundImageView setSharedImageDownloader:[[NCAPIController sharedInstance] imageDownloaderNoCache]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didJoinRoom:) name:NCRoomsManagerDidJoinRoomNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerDidEndCall:) name:CallKitManagerDidEndCallNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerDidChangeAudioMute:) name:CallKitManagerDidChangeAudioMuteNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerWantsToUpgradeToVideoCall:) name:CallKitManagerWantsToUpgradeToVideoCall object:nil];
    
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
    
    [_screensharingView setHidden:YES];
    
    [self.audioMuteButton.layer setCornerRadius:30.0f];
    [self.speakerButton.layer setCornerRadius:30.0f];
    [self.videoDisableButton.layer setCornerRadius:30.0f];
    [self.hangUpButton.layer setCornerRadius:30.0f];
    [self.videoCallButton.layer setCornerRadius:30.0f];
    [self.closeScreensharingButton.layer setCornerRadius:16.0f];
    
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
    [self resizeScreensharingView];
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
    NSString *token = [notification.userInfo objectForKey:@"token"];
    if (![token isEqualToString:_room.token]) {
        return;
    }
    
    NSError *error = [notification.userInfo objectForKey:@"error"];
    if (error) {
        [self presentJoinCallError];
        return;
    }
    
    NCRoomController *roomController = [notification.userInfo objectForKey:@"roomController"];
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

- (void)providerWantsToUpgradeToVideoCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (![roomToken isEqualToString:_room.token]) {
        return;
    }
    
    if (_isAudioOnly) {
        [self showUpgradeToVideoCallDialog];
    }
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
        case CallStateReconnecting:
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
    if (_room.type == kNCRoomTypeOneToOne) {
        __weak AvatarBackgroundImageView *weakBGView = self.avatarBackgroundImageView;
        [self.avatarBackgroundImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                              placeholderImage:nil success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                                  if ([response statusCode] == 200) {
                                                      CGFloat inputRadius = 8.0f;
                                                      CIContext *context = [CIContext contextWithOptions:nil];
                                                      CIImage *inputImage = [[CIImage alloc] initWithImage:image];
                                                      CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
                                                      [filter setValue:inputImage forKey:kCIInputImageKey];
                                                      [filter setValue:[NSNumber numberWithFloat:inputRadius] forKey:@"inputRadius"];
                                                      CIImage *result = [filter valueForKey:kCIOutputImageKey];
                                                      CGRect imageRect = [inputImage extent];
                                                      CGRect cropRect = CGRectMake(imageRect.origin.x + inputRadius, imageRect.origin.y + inputRadius, imageRect.size.width - inputRadius * 2, imageRect.size.height - inputRadius * 2);
                                                      CGImageRef cgImage = [context createCGImage:result fromRect:imageRect];
                                                      UIImage *finalImage = [UIImage imageWithCGImage:CGImageCreateWithImageInRect(cgImage, cropRect)];
                                                      [weakBGView setImage:finalImage];
                                                      weakBGView.contentMode = UIViewContentModeScaleAspectFill;
                                                  } else if ([response statusCode] == 201) {
                                                      DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:image withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
                                                      [weakBGView setBackgroundColor:colorPicker.backgroundColor];
                                                      weakBGView.backgroundColor = [weakBGView.backgroundColor colorWithAlphaComponent:0.8];
                                                  }
                                              } failure:nil];
    } else {
        self.avatarBackgroundImageView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1];
    }
    
    [self setWaitingScreenText];
}

- (void)setWaitingScreenText
{
    NSString *waitingMessage = @"Waiting for others to join call…";
    if (_room.type == kNCRoomTypeOneToOne) {
        waitingMessage = [NSString stringWithFormat:@"Waiting for %@ to join call…", _room.displayName];
    }
    
    if (_callState == CallStateReconnecting) {
        waitingMessage = @"Connecting to the call…";
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.waitingLabel.text = waitingMessage;
    });
}

- (void)showWaitingScreen
{
    [self setWaitingScreenText];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.collectionView.backgroundView = self.waitingView;
    });
}

- (void)hideWaitingScreen
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.collectionView.backgroundView = nil;
    });
}

- (void)addTapGestureForDetailedView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view addGestureRecognizer:_tapGestureForDetailedView];
    });
}

- (void)removeTapGestureForDetailedView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view removeGestureRecognizer:_tapGestureForDetailedView];
    });
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3f animations:^{
            [self.buttonsContainerView setAlpha:1.0f];
            [self.switchCameraButton setAlpha:1.0f];
            [self.videoCallButton setAlpha:1.0f];
            [self.closeScreensharingButton setAlpha:1.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)hideButtonsContainer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3f animations:^{
            [self.buttonsContainerView setAlpha:0.0f];
            [self.switchCameraButton setAlpha:0.0f];
            [self.videoCallButton setAlpha:0.0f];
            [self.closeScreensharingButton setAlpha:0.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)adjustButtonsConainer
{
    if (_isAudioOnly) {
        _videoDisableButton.hidden = YES;
        _switchCameraButton.hidden = YES;
        _videoCallButton.hidden = NO;
        // Align audio - video - speaker buttons
        CGRect audioButtonFrame = _audioMuteButton.frame;
        audioButtonFrame.origin.y = 10;
        _audioMuteButton.frame = audioButtonFrame;
        CGRect speakerButtonFrame = _speakerButton.frame;
        speakerButtonFrame.origin.y = 10;
        _speakerButton.frame = speakerButtonFrame;
    } else {
        _speakerButton.hidden = YES;
        _videoCallButton.hidden = YES;
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

- (void)presentJoinCallError
{
    NSString *alertTitle = [NSString stringWithFormat:@"Could not join %@ call", _room.displayName];
    if (_room.type == kNCRoomTypeOneToOne) {
        alertTitle = [NSString stringWithFormat:@"Could not join call with %@", _room.displayName];
    }
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                    message:@"An error occurred while joining the call"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okButton = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
                                                         [self hangup];
                                                     }];
    [alert addAction:okButton];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
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
    if (!_hangingUp) {
        _hangingUp = YES;
        // Dismiss possible notifications
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        
        [self.delegate callViewControllerWantsToBeDismissed:self];
        
        [_localVideoView.captureSession stopRunning];
        _localVideoView.captureSession = nil;
        [_localVideoView setHidden:YES];
        [_captureController stopCapture];
        _captureController = nil;
        
        for (NCPeerConnection *peerConnection in _peersInCall) {
            // Video renderers
            RTCEAGLVideoView *videoRenderer = [_videoRenderersDict objectForKey:peerConnection.peerId];
            [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
            [_videoRenderersDict removeObjectForKey:peerConnection.peerId];
            // Screen renderers
            RTCEAGLVideoView *screenRenderer = [_screenRenderersDict objectForKey:peerConnection.peerId];
            [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
            [_screenRenderersDict removeObjectForKey:peerConnection.peerId];
        }
        
        if (_callController) {
            [_callController leaveCall];
        } else {
            [self finishCall];
        }
    }
}

- (IBAction)videoCallButtonPressed:(id)sender
{
    [self showUpgradeToVideoCallDialog];
}

- (void)showUpgradeToVideoCallDialog
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:@"Do you want to enable your video?"
                                        message:@"If you enable your video, this call will be interrupted for a few seconds."
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Enable" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self upgradeToVideoCall];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)upgradeToVideoCall
{
    _videoCallUpgrade = YES;
    [self hangup];
}

- (void)finishCall
{
    _callController = nil;
    if (_videoCallUpgrade) {
        _videoCallUpgrade = NO;
        [self.delegate callViewControllerWantsVideoCallUpgrade:self];
    } else {
        [self.delegate callViewControllerDidFinish:self];
    }
}

#pragma mark - CallParticipantViewCell delegate

- (void)cellWantsToPresentScreenSharing:(CallParticipantViewCell *)participantCell
{
    [self showScreenOfPeerId:participantCell.peerId];
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
    
    cell.peerId = peerConnection.peerId;
    cell.actionsDelegate = self;
    [cell setVideoView:[_videoRenderersDict objectForKey:peerConnection.peerId]];
    [cell setUserAvatar:[_callController getUserIdFromSessionId:peerConnection.peerId]];
    [cell setDisplayName:peerConnection.peerName];
    [cell setAudioDisabled:peerConnection.isRemoteAudioDisabled];
    [cell setScreenShared:[_screenRenderersDict objectForKey:peerConnection.peerId]];
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

- (void)callControllerDidFailedJoiningCall:(NCCallController *)callController
{
    [self presentJoinCallError];
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
    // Video renderers
    RTCEAGLVideoView *videoRenderer = [_videoRenderersDict objectForKey:peer.peerId];
    [[peer.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
    [_videoRenderersDict removeObjectForKey:peer.peerId];
    // Screen renderers
    RTCEAGLVideoView *screenRenderer = [_screenRenderersDict objectForKey:peer.peerId];
    [[peer.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
    [_screenRenderersDict removeObjectForKey:peer.peerId];
    
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
    
    if ([remotePeer.roomType isEqualToString:kRoomTypeVideo]) {
        [_videoRenderersDict setObject:renderView forKey:remotePeer.peerId];
        [_peersInCall addObject:remotePeer];
    } else if ([remotePeer.roomType isEqualToString:kRoomTypeScreen]) {
        [_screenRenderersDict setObject:renderView forKey:remotePeer.peerId];
        [self showScreenOfPeerId:remotePeer.peerId];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    
}

- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer
{
    if (state == RTCIceConnectionStateClosed) {
        [_peersInCall removeObject:peer];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.collectionView reloadData];
        });
    } else {
        [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
            [cell setConnectionState:state];
        }];
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

- (void)callController:(NCCallController *)callController didReceiveUnshareScreenFromPeer:(NCPeerConnection *)peer
{
    RTCEAGLVideoView *screenRenderer = [_screenRenderersDict objectForKey:peer.peerId];
    [[peer.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
    [_screenRenderersDict removeObjectForKey:peer.peerId];
    [self closeScreensharingButtonPressed:self];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)callControllerIsReconnectingCall:(NCCallController *)callController
{
    [self setCallState:CallStateReconnecting];
}

#pragma mark - Screensharing

- (void)showScreenOfPeerId:(NSString *)peerId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCEAGLVideoView *renderView = [_screenRenderersDict objectForKey:peerId];
        [_screenView removeFromSuperview];
        _screenView = nil;
        _screenView = renderView;
        _screensharingSize = renderView.frame.size;
        [_screensharingView addSubview:_screenView];
        [_screensharingView bringSubviewToFront:_closeScreensharingButton];
        [UIView transitionWithView:_screensharingView duration:0.4
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{_screensharingView.hidden = NO;}
                        completion:nil];
        [self resizeScreensharingView];
    });
    // Enable/Disable detailed view with tap gesture
    // in voice only call when screensharing is enabled
    if (_isAudioOnly) {
        [self addTapGestureForDetailedView];
        [self showDetailedViewWithTimer];
    }
}

- (void)resizeScreensharingView {
    CGRect bounds = _screensharingView.bounds;
    CGSize videoSize = _screensharingSize;
    
    if (videoSize.width > 0 && videoSize.height > 0) {
        // Aspect fill remote video into bounds.
        CGRect remoteVideoFrame = AVMakeRectWithAspectRatioInsideRect(videoSize, bounds);
        CGFloat scale = 1;
        remoteVideoFrame.size.height *= scale;
        remoteVideoFrame.size.width *= scale;
        _screenView.frame = remoteVideoFrame;
        _screenView.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    } else {
        _screenView.frame = bounds;
    }
}

- (IBAction)closeScreensharingButtonPressed:(id)sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_screenView removeFromSuperview];
        _screenView = nil;
        [UIView transitionWithView:_screensharingView duration:0.4
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{_screensharingView.hidden = YES;}
                        completion:nil];
    });
    // Back to normal voice only UI
    if (_isAudioOnly) {
        [self invalidateDetailedViewTimer];
        [self showDetailedView];
        [self removeTapGestureForDetailedView];
    }
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    for (RTCEAGLVideoView *rendererView in [_videoRenderersDict allValues]) {
        if ([videoView isEqual:rendererView]) {
            rendererView.frame = CGRectMake(0, 0, size.width, size.height);
        }
    }
    for (RTCEAGLVideoView *rendererView in [_screenRenderersDict allValues]) {
        if ([videoView isEqual:rendererView]) {
            rendererView.frame = CGRectMake(0, 0, size.width, size.height);
            if ([_screenView isEqual:rendererView]) {
                _screensharingSize = rendererView.frame.size;
                [self resizeScreensharingView];
            }
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *visibleCells = [_collectionView visibleCells];
        for (CallParticipantViewCell *cell in visibleCells) {
            [UIView animateWithDuration:0.3f animations:^{
                [cell.peerNameLabel setAlpha:1.0f];
                [cell.buttonsContainerView setAlpha:1.0f];
                [cell layoutIfNeeded];
            }];
        }
    });
}

- (void)hidePeersInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *visibleCells = [_collectionView visibleCells];
        for (CallParticipantViewCell *cell in visibleCells) {
            [UIView animateWithDuration:0.3f animations:^{
                [cell.peerNameLabel setAlpha:0.0f];
                [cell.buttonsContainerView setAlpha:0.0f];
                [cell layoutIfNeeded];
            }];
        }
    });
}

@end
