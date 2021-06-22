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

#import "CallViewController.h"

#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCVideoTrack.h>

#import "ARDCaptureController.h"
#import "DBImageColorPicker.h"
#import "PulsingHaloLayer.h"
#import "UIImageView+AFNetworking.h"
#import "UIView+Toast.h"

#import "CallKitManager.h"
#import "CallParticipantViewCell.h"
#import "NBMPeersFlowLayout.h"
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCCallController.h"
#import "NCDatabaseManager.h"
#import "NCImageSessionManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCSignalingMessage.h"
#import "NCUtils.h"

typedef NS_ENUM(NSInteger, CallState) {
    CallStateJoining,
    CallStateWaitingParticipants,
    CallStateReconnecting,
    CallStateInCall
};

@interface CallViewController () <NCCallControllerDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, RTCVideoViewDelegate, CallParticipantViewCellDelegate, UIGestureRecognizerDelegate>
{
    CallState _callState;
    NSMutableArray *_peersInCall;
    NSMutableDictionary *_videoRenderersDict;
    NSMutableDictionary *_screenRenderersDict;
    NCCallController *_callController;
    NCChatViewController *_chatViewController;
    UINavigationController *_chatNavigationController;
    ARDCaptureController *_captureController;
    UIView <RTCVideoRenderer> *_screenView;
    CGSize _screensharingSize;
    UITapGestureRecognizer *_tapGestureForDetailedView;
    NSTimer *_detailedViewTimer;
    NSString *_displayName;
    BOOL _isAudioOnly;
    BOOL _isDetailedViewVisible;
    BOOL _userDisabledVideo;
    BOOL _videoCallUpgrade;
    BOOL _hangingUp;
    BOOL _pushToTalkActive;
    PulsingHaloLayer *_halo;
    PulsingHaloLayer *_haloPushToTalk;
    UIImpactFeedbackGenerator *_buttonFeedbackGenerator;
    CGPoint _localVideoDragStartingPosition;
    CGPoint _localVideoOriginPosition;
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
    
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    
    _room = room;
    _displayName = displayName;
    _isAudioOnly = audioOnly;
    _peersInCall = [[NSMutableArray alloc] init];
    _videoRenderersDict = [[NSMutableDictionary alloc] init];
    _screenRenderersDict = [[NSMutableDictionary alloc] init];
    _buttonFeedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyleLight)];
    
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
    _callController.disableVideoAtStart = _videoDisabledAtStart;
    
    [_callController startCall];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _tapGestureForDetailedView = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showDetailedViewWithTimer)];
    [_tapGestureForDetailedView setNumberOfTapsRequired:1];
    
    
    UILongPressGestureRecognizer *pushToTalkRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePushToTalk:)];
    pushToTalkRecognizer.delegate = self;
    [self.audioMuteButton addGestureRecognizer:pushToTalkRecognizer];
    
    [_screensharingView setHidden:YES];
    
    [self.audioMuteButton.layer setCornerRadius:30.0f];
    [self.speakerButton.layer setCornerRadius:30.0f];
    [self.videoDisableButton.layer setCornerRadius:30.0f];
    [self.hangUpButton.layer setCornerRadius:30.0f];
    [self.videoCallButton.layer setCornerRadius:30.0f];
    [self.toggleChatButton.layer setCornerRadius:30.0f];
    [self.closeScreensharingButton.layer setCornerRadius:16.0f];
        
    self.audioMuteButton.accessibilityLabel = NSLocalizedString(@"Microphone", nil);
    self.audioMuteButton.accessibilityValue = NSLocalizedString(@"Microphone enabled", nil);
    self.audioMuteButton.accessibilityHint = NSLocalizedString(@"Double tap to enable or disable the microphone", nil);
    self.speakerButton.accessibilityLabel = NSLocalizedString(@"Speaker", nil);
    self.speakerButton.accessibilityValue = NSLocalizedString(@"Speaker disabled", nil);
    self.speakerButton.accessibilityHint = NSLocalizedString(@"Double tap to enable or disable the speaker", nil);
    self.videoDisableButton.accessibilityLabel = NSLocalizedString(@"Camera", nil);
    self.videoDisableButton.accessibilityValue = NSLocalizedString(@"Camera enabled", nil);
    self.videoDisableButton.accessibilityHint = NSLocalizedString(@"Double tap to enable or disable the camera", nil);
    self.hangUpButton.accessibilityLabel = NSLocalizedString(@"Hang up", nil);
    self.hangUpButton.accessibilityHint = NSLocalizedString(@"Double tap to hang up the call", nil);
    self.videoCallButton.accessibilityLabel = NSLocalizedString(@"Camera", nil);
    self.videoCallButton.accessibilityHint = NSLocalizedString(@"Double tap to upgrade this voice call to a video call", nil);
    self.toggleChatButton.accessibilityLabel = NSLocalizedString(@"Chat", nil);
    self.toggleChatButton.accessibilityHint = NSLocalizedString(@"Double tap to show or hide chat view", nil);
    
    [self adjustButtonsConainer];
    [self showButtonsContainerAnimated:NO];
    [self showChatToggleButtonAnimated:NO];
    
    self.collectionView.delegate = self;
    
    [self createWaitingScreen];
    
    // We disableLocalVideo here even if the call controller has not been created just to show the video button as disabled
    // also we set _userDisabledVideo = YES so the proximity sensor doesn't enable it.
    if (_videoDisabledAtStart) {
        _userDisabledVideo = YES;
        [self disableLocalVideo];
    }
    
    [self.collectionView registerNib:[UINib nibWithNibName:kCallParticipantCellNibName bundle:nil] forCellWithReuseIdentifier:kCallParticipantCellIdentifier];
    
    if (@available(iOS 11.0, *)) {
        [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    }
    
    UIPanGestureRecognizer *localVideoDragGesturure = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(localVideoDragged:)];
    [self.localVideoView addGestureRecognizer:localVideoDragGesturure];
        
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:)
                                                 name:@"UIDeviceProximityStateDidChangeNotification" object:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self.collectionView.collectionViewLayout invalidateLayout];
    [_halo setHidden:YES];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self setLocalVideoRect];
        for (UICollectionViewCell *cell in self->_collectionView.visibleCells) {
            CallParticipantViewCell * participantCell = (CallParticipantViewCell *) cell;
            [participantCell resizeRemoteVideoView];
        }
        [self resizeScreensharingView];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self setHaloToToggleChatButton];
        // Workaround to move buttons to correct position (visible/not visible) so there is always an animation
        if (self->_isDetailedViewVisible) {
            [self showButtonsContainerAnimated:NO];
            [self showChatToggleButtonAnimated:NO];
        } else {
            [self hideButtonsContainerAnimated:NO];
            [self hideChatToggleButtonAnimated:NO];
        }
    }];
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self setLocalVideoRect];
    // Workaround to move buttons to correct position (visible/not visible) so there is always an animation
    if (_isDetailedViewVisible) {
        [self showButtonsContainerAnimated:NO];
        [self showChatToggleButtonAnimated:NO];
    } else {
        [self hideButtonsContainerAnimated:NO];
        [self hideChatToggleButtonAnimated:NO];
    }
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [self setLocalVideoRect];
    
    // Fix missing hallo after the view controller disappears
    // e.g. when presenting file preview
    if (_chatNavigationController) {
        [self setHaloToToggleChatButton];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    // No push-to-talk while in chat
    if (!_chatNavigationController) {
        for (UIPress* press in presses) {
            if (press.key.keyCode == UIKeyboardHIDUsageKeyboardSpacebar) {
                [self pushToTalkStart];
                
                return;
            }
        }
    }
    
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
    // No push-to-talk while in chat
    if (!_chatNavigationController) {
        for (UIPress* press in presses) {
            if (press.key.keyCode == UIKeyboardHIDUsageKeyboardSpacebar) {
                [self pushToTalkEnd];
                
                return;
            }
        }
    }
    
    [super pressesEnded:presses withEvent:event];
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
        [self presentJoinError:[notification.userInfo objectForKey:@"errorReason"]];
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
    
    CGFloat width = [UIScreen mainScreen].bounds.size.width / 6;
    CGFloat height = [UIScreen mainScreen].bounds.size.height / 6;
    
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
    
    _localVideoOriginPosition = CGPointMake(16, 60);
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets safeAreaInsets = self.view.safeAreaInsets;
        _localVideoOriginPosition = CGPointMake(16 + safeAreaInsets.left, 60 + safeAreaInsets.top);
    }
    
    CGRect localVideoRect = CGRectMake(_localVideoOriginPosition.x, _localVideoOriginPosition.y, localVideoSize.width, localVideoSize.height);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_localVideoView.frame = localVideoRect;
        self->_localVideoView.layer.cornerRadius = 4.0f;
        self->_localVideoView.layer.masksToBounds = YES;
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
    
    [self pushToTalkEnd];
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
                                                  NSDictionary *headers = [response allHeaderFields];
                                                  id customAvatarHeader = [headers objectForKey:@"X-NC-IsCustomAvatar"];
                                                  BOOL shouldShowBlurBackground = YES;
                                                  if (customAvatarHeader) {
                                                      shouldShowBlurBackground = [customAvatarHeader boolValue];
                                                  } else if ([response statusCode] == 201) {
                                                      shouldShowBlurBackground = NO;
                                                  }
                                                  
                                                  if (shouldShowBlurBackground) {
                                                      UIImage *blurImage = [NCUtils blurImageFromImage:image];
                                                      [weakBGView setImage:blurImage];
                                                      weakBGView.contentMode = UIViewContentModeScaleAspectFill;
                                                  } else {
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
    NSString *waitingMessage = NSLocalizedString(@"Waiting for others to join call …", nil);
    if (_room.type == kNCRoomTypeOneToOne) {
        waitingMessage = [NSString stringWithFormat:NSLocalizedString(@"Waiting for %@ to join call …", nil), _room.displayName];
    }
    
    if (_callState == CallStateReconnecting) {
        waitingMessage = NSLocalizedString(@"Connecting to the call …", nil);
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
        [self.view addGestureRecognizer:self->_tapGestureForDetailedView];
    });
}

- (void)removeTapGestureForDetailedView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view removeGestureRecognizer:self->_tapGestureForDetailedView];
    });
}

- (void)showDetailedView
{
    _isDetailedViewVisible = YES;
    [self showButtonsContainerAnimated:YES];
    [self showChatToggleButtonAnimated:YES];
    [self showPeersInfo];
}

- (void)showDetailedViewWithTimer
{
    if (_isDetailedViewVisible) {
        [self hideDetailedView];
    } else {
        [self showDetailedView];
        [self setDetailedViewTimer];
    }
}

- (void)hideDetailedView
{
    // Keep detailed view visible while push to talk is active
    if (_pushToTalkActive) {
        [self setDetailedViewTimer];
        return;
    }
    
    _isDetailedViewVisible = NO;
    [self hideButtonsContainerAnimated:YES];
    [self hideChatToggleButtonAnimated:YES];
    [self hidePeersInfo];
    [self invalidateDetailedViewTimer];
}

- (void)hideAudioMuteButton
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3f animations:^{
            [self.audioMuteButton setAlpha:0.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)showAudioMuteButton
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3f animations:^{
            [self.audioMuteButton setAlpha:1.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)showButtonsContainerAnimated:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.buttonsContainerView setAlpha:1.0f];
        CGFloat duration = animated ? 0.3 : 0.0;
        [UIView animateWithDuration:duration animations:^{
            CGRect buttonsFrame = self.buttonsContainerView.frame;
            buttonsFrame.origin.y = self.view.frame.size.height - buttonsFrame.size.height - 16;
            if (@available(iOS 11.0, *)) {
                buttonsFrame.origin.y -= self.view.safeAreaInsets.bottom;
            }
            self.buttonsContainerView.frame = buttonsFrame;
        } completion:^(BOOL finished) {
            [self adjustLocalVideoPositionFromOriginPosition:self->_localVideoOriginPosition];
        }];
        [UIView animateWithDuration:0.3f animations:^{
            [self.switchCameraButton setAlpha:1.0f];
            [self.closeScreensharingButton setAlpha:1.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)hideButtonsContainerAnimated:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat duration = animated ? 0.3 : 0.0;
        [UIView animateWithDuration:duration animations:^{
            CGRect buttonsFrame = self.buttonsContainerView.frame;
            buttonsFrame.origin.y = self.view.frame.size.height;
            self.buttonsContainerView.frame = buttonsFrame;
        } completion:^(BOOL finished) {
            [self adjustLocalVideoPositionFromOriginPosition:self->_localVideoOriginPosition];
            [self.buttonsContainerView setAlpha:0.0f];
        }];
        [UIView animateWithDuration:0.3f animations:^{
            [self.switchCameraButton setAlpha:0.0f];
            [self.closeScreensharingButton setAlpha:0.0f];
            [self.view layoutIfNeeded];
        }];
    });
}

- (void)showChatToggleButtonAnimated:(BOOL)animated
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.toggleChatButton setAlpha:1.0f];
        CGFloat duration = animated ? 0.3 : 0.0;
        [UIView animateWithDuration:duration animations:^{
            CGRect buttonFrame = self.toggleChatButton.frame;
            buttonFrame.origin.x = self.view.frame.size.width - buttonFrame.size.width - 16;
            buttonFrame.origin.y = 60;
            if (@available(iOS 11.0, *)) {
                buttonFrame.origin.x -= self.view.safeAreaInsets.right;
                buttonFrame.origin.y = self.view.safeAreaInsets.top + 60;
            }
            self.toggleChatButton.frame = buttonFrame;
        }];
    });
}

- (void)hideChatToggleButtonAnimated:(BOOL)animated
{
    if (!_chatNavigationController) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat duration = animated ? 0.3 : 0.0;
            [UIView animateWithDuration:duration animations:^{
                CGRect buttonFrame = self.toggleChatButton.frame;
                buttonFrame.origin.x = self.view.frame.size.width;
                buttonFrame.origin.y = 60;
                if (@available(iOS 11.0, *)) {
                    buttonFrame.origin.y = self.view.safeAreaInsets.top + 60;
                }
                self.toggleChatButton.frame = buttonFrame;
            } completion:^(BOOL finished) {
                [self.toggleChatButton setAlpha:0.0f];
            }];
        });
    }
}

- (void)adjustButtonsConainer
{
    if (_isAudioOnly) {
        _videoDisableButton.hidden = YES;
        _switchCameraButton.hidden = YES;
        _videoCallButton.hidden = NO;
    } else {
        _speakerButton.hidden = YES;
        _videoCallButton.hidden = YES;
        // Center audio - video - hang up buttons
        CGRect audioButtonFrame = _audioMuteButton.frame;
        audioButtonFrame.origin.x = 40;
        _audioMuteButton.frame = audioButtonFrame;
        CGRect videoButtonFrame = _videoDisableButton.frame;
        videoButtonFrame.origin.x = 130;
        _videoDisableButton.frame = videoButtonFrame;
        CGRect hangUpButtonFrame = _hangUpButton.frame;
        hangUpButtonFrame.origin.x = 220;
        _hangUpButton.frame = hangUpButtonFrame;
    }
    
    // Only show speaker button in iPhones
    if(![[UIDevice currentDevice].model isEqualToString:@"iPhone"] && _isAudioOnly) {
        _speakerButton.hidden = YES;
        // Center audio - video - hang up buttons
        CGRect audioButtonFrame = _audioMuteButton.frame;
        audioButtonFrame.origin.x = 40;
        _audioMuteButton.frame = audioButtonFrame;
        CGRect videoButtonFrame = _videoCallButton.frame;
        videoButtonFrame.origin.x = 130;
        _videoCallButton.frame = videoButtonFrame;
        CGRect hangUpButtonFrame = _hangUpButton.frame;
        hangUpButtonFrame.origin.x = 220;
        _hangUpButton.frame = hangUpButtonFrame;
    }
}

- (void)setDetailedViewTimer
{
    [self invalidateDetailedViewTimer];
    _detailedViewTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(hideDetailedView) userInfo:nil repeats:NO];
}

- (void)invalidateDetailedViewTimer
{
    [_detailedViewTimer invalidate];
    _detailedViewTimer = nil;
}

- (void)presentJoinError:(NSString *)alertMessage
{
    NSString *alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Could not join %@ call", nil), _room.displayName];
    if (_room.type == kNCRoomTypeOneToOne) {
        alertTitle = [NSString stringWithFormat:NSLocalizedString(@"Could not join call with %@", nil), _room.displayName];
    }
    
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                    message:alertMessage
                                                             preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
                                                         [self hangup];
                                                     }];
    [alert addAction:okButton];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)adjustLocalVideoPositionFromOriginPosition:(CGPoint)position
{
    UIEdgeInsets edgeInsets = UIEdgeInsetsMake(16, 16, 16, 16);
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets safeAreaInsets = _localVideoView.superview.safeAreaInsets;
        edgeInsets = UIEdgeInsetsMake(16 + safeAreaInsets.top, 16 + safeAreaInsets.left,16 + safeAreaInsets.bottom,16 + safeAreaInsets.right);
    }

    CGSize parentSize = _localVideoView.superview.bounds.size;
    CGSize viewSize = _localVideoView.bounds.size;

    // Adjust left
    if (position.x < edgeInsets.left) {
        position = CGPointMake(edgeInsets.left, position.y);
    }
    // Adjust top
    if (position.y < edgeInsets.top) {
        position = CGPointMake(position.x, edgeInsets.top);
    }
    // Adjust right
    BOOL isChatButtonVisible = _toggleChatButton.frame.origin.x < parentSize.width;
    if (isChatButtonVisible && position.x > _toggleChatButton.frame.origin.x - viewSize.height - edgeInsets.right) {
        position = CGPointMake(_toggleChatButton.frame.origin.x - viewSize.width - edgeInsets.right, position.y);
    } else if (position.x > parentSize.width - viewSize.width - edgeInsets.right) {
        position = CGPointMake(parentSize.width - viewSize.width - edgeInsets.right, position.y);
    }
    // Adjust bottom
    if (_isDetailedViewVisible && position.y > _buttonsContainerView.frame.origin.y - viewSize.height - edgeInsets.bottom) {
        position = CGPointMake(position.x, _buttonsContainerView.frame.origin.y - viewSize.height - edgeInsets.bottom);
    } else if (position.y > parentSize.height - viewSize.height - edgeInsets.bottom) {
        position = CGPointMake(position.x, parentSize.height - viewSize.height - edgeInsets.bottom);
    }
    CGRect frame = _localVideoView.frame;
    frame.origin.x = position.x;
    frame.origin.y = position.y;

    [UIView animateWithDuration:0.3 animations:^{
        self->_localVideoView.frame = frame;
    }];
}

- (void)localVideoDragged:(UIPanGestureRecognizer *)gesture
{
    if (gesture.view == _localVideoView) {
        if (gesture.state == UIGestureRecognizerStateBegan) {
            _localVideoDragStartingPosition = gesture.view.center;
        } else if (gesture.state == UIGestureRecognizerStateChanged) {
            CGPoint translation = [gesture translationInView:gesture.view];
            _localVideoView.center = CGPointMake(_localVideoDragStartingPosition.x + translation.x, _localVideoDragStartingPosition.y + translation.y);
        } else if (gesture.state == UIGestureRecognizerStateEnded) {
            _localVideoOriginPosition = gesture.view.frame.origin;
            [self adjustLocalVideoPositionFromOriginPosition:_localVideoOriginPosition];
        }
    }
}

#pragma mark - Call actions

-(void)handlePushToTalk:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self pushToTalkStart];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self pushToTalkEnd];
    }
}

- (void)pushToTalkStart
{
    if (_callController && ![_callController isAudioEnabled]) {
        [self unmuteAudio];
        
        [self setHaloToAudioMuteButton];
        [_buttonFeedbackGenerator impactOccurred];
        _pushToTalkActive = YES;
    }
}

- (void)pushToTalkEnd
{
    if (_pushToTalkActive) {
        [self muteAudio];
        
        [self removeHaloFromAudioMuteButton];
        _pushToTalkActive = NO;
    }
}

- (IBAction)audioButtonPressed:(id)sender
{
    if (!_callController) {return;}
    
    if ([_callController isAudioEnabled]) {
        if ([CallKitManager isCallKitAvailable]) {
            [[CallKitManager sharedInstance] reportAudioMuted:YES forCall:_room.token];
        } else {
            [self muteAudio];
        }
    } else {
        if ([CallKitManager isCallKitAvailable]) {
            [[CallKitManager sharedInstance] reportAudioMuted:NO forCall:_room.token];
        } else {
            [self unmuteAudio];
        }
        
        if ((!_isAudioOnly && _callState == CallStateInCall) || _screenView) {
            // Audio was disabled -> make sure the permanent visible audio button is hidden again
            [self showDetailedViewWithTimer];
        }
    }
}

- (void)forceMuteAudio
{
    NSString *forceMutedString = NSLocalizedString(@"You have been muted by a moderator", nil);
    [self muteAudioWithReason:forceMutedString];
}

-(void)muteAudioWithReason:(NSString*)reason
{
    [_callController enableAudio:NO];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_audioMuteButton setImage:[UIImage imageNamed:@"audio-off"] forState:UIControlStateNormal];
        [self showAudioMuteButton];
        
        NSString *micDisabledString = NSLocalizedString(@"Microphone disabled", nil);
        NSTimeInterval duration = 1.5;
        UIView *toast;
        
        if (reason) {
            // Nextcloud uses a default timeout of 7s for toasts
            duration = 7.0;

            toast = [self.view toastViewForMessage:reason title:micDisabledString image:nil style:nil];
        } else {
            toast = [self.view toastViewForMessage:micDisabledString title:nil image:nil style:nil];
        }
        
        [self.view showToast:toast duration:duration position:CSToastPositionCenter completion:nil];
    });
}

- (void)muteAudio
{
    [self muteAudioWithReason:nil];
}

- (void)unmuteAudio
{
    [_callController enableAudio:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_audioMuteButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
        NSString *micEnabledString = NSLocalizedString(@"Microphone enabled", nil);
        self->_audioMuteButton.accessibilityValue = micEnabledString;
        [self.view makeToast:micEnabledString duration:1.5 position:CSToastPositionCenter];
    });
}

- (IBAction)videoButtonPressed:(id)sender
{
    if (!_callController) {return;}
    
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
    NSString *cameraDisabledString = NSLocalizedString(@"Camera disabled", nil);
    _videoDisableButton.accessibilityValue = cameraDisabledString;
    if (!_isAudioOnly) {
        [self.view makeToast:cameraDisabledString duration:1.5 position:CSToastPositionCenter];
    }
}

- (void)enableLocalVideo
{
    [_callController enableVideo:YES];
    [_captureController startCapture];
    [_localVideoView setHidden:NO];
    [_videoDisableButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
    _videoDisableButton.accessibilityValue = NSLocalizedString(@"Camera enabled", nil);
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
    NSString *speakerDisabledString = NSLocalizedString(@"Speaker disabled", nil);
    _speakerButton.accessibilityValue = speakerDisabledString;
    [self.view makeToast:speakerDisabledString duration:1.5 position:CSToastPositionCenter];
}

- (void)enableSpeaker
{
    [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
    [_speakerButton setImage:[UIImage imageNamed:@"speaker"] forState:UIControlStateNormal];
    NSString *speakerEnabledString = NSLocalizedString(@"Speaker enabled", nil);
    _speakerButton.accessibilityValue = speakerEnabledString;
    [self.view makeToast:speakerEnabledString duration:1.5 position:CSToastPositionCenter];
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NCPeerConnection *peerConnection in self->_peersInCall) {
                // Video renderers
                RTCEAGLVideoView *videoRenderer = [self->_videoRenderersDict objectForKey:peerConnection.peerId];
                [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
                [self->_videoRenderersDict removeObjectForKey:peerConnection.peerId];
                // Screen renderers
                RTCEAGLVideoView *screenRenderer = [self->_screenRenderersDict objectForKey:peerConnection.peerId];
                [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
                [self->_screenRenderersDict removeObjectForKey:peerConnection.peerId];
            }
        });
        
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
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Do you want to enable your camera?", nil)
                                        message:NSLocalizedString(@"If you enable your camera, this call will be interrupted for a few seconds.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Enable", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self upgradeToVideoCall];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)upgradeToVideoCall
{
    _videoCallUpgrade = YES;
    [self hangup];
}

- (IBAction)toggleChatButtonPressed:(id)sender
{
    [self toggleChatView];
}

- (void)toggleChatView
{
    if (!_chatNavigationController) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        NCRoom *room = [[NCRoomsManager sharedInstance] roomWithToken:_room.token forAccountId:activeAccount.accountId];
        _chatViewController = [[NCChatViewController alloc] initForRoom:room];
        _chatViewController.presentedInCall = YES;
        _chatNavigationController = [[UINavigationController alloc] initWithRootViewController:_chatViewController];
        [self addChildViewController:_chatNavigationController];
        
        [self.view addSubview:_chatNavigationController.view];
        _chatNavigationController.view.frame = self.view.bounds;
        _chatNavigationController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_chatNavigationController didMoveToParentViewController:self];
        
        [self setHaloToToggleChatButton];
        
        [self showChatToggleButtonAnimated:NO];
        [_toggleChatButton setImage:[UIImage imageNamed:@"phone"] forState:UIControlStateNormal];
        if (!_isAudioOnly) {
            [self.view bringSubviewToFront:_localVideoView];
        }
        [self.view bringSubviewToFront:_toggleChatButton];
        [self removeTapGestureForDetailedView];
    } else {
        [_toggleChatButton setImage:[UIImage imageNamed:@"chat"] forState:UIControlStateNormal];
        [_halo removeFromSuperlayer];
        
        [self.view bringSubviewToFront:_buttonsContainerView];
        
        [_chatViewController leaveChat];
        _chatViewController = nil;
        
        [_chatNavigationController willMoveToParentViewController:nil];
        [_chatNavigationController.view removeFromSuperview];
        [_chatNavigationController removeFromParentViewController];
        
        _chatNavigationController = nil;
        
        if ((!_isAudioOnly && _callState == CallStateInCall) || _screenView) {
            [self addTapGestureForDetailedView];
            [self showDetailedViewWithTimer];
        }
    }
}

- (void)setHaloToToggleChatButton
{
    [_halo removeFromSuperlayer];
    
    if (_chatNavigationController) {
        _halo = [PulsingHaloLayer layer];
        _halo.position = _toggleChatButton.center;
        UIColor *color = [UIColor colorWithRed:118/255.f green:213/255.f blue:114/255.f alpha:1];
        _halo.backgroundColor = color.CGColor;
        _halo.radius = 40.0;
        _halo.haloLayerNumber = 2;
        _halo.keyTimeForHalfOpacity = 0.75;
        _halo.fromValueForRadius = 0.75;
        [_chatNavigationController.view.layer addSublayer:_halo];
        [_halo start];
    }
}

- (void)setHaloToAudioMuteButton
{
    [_haloPushToTalk removeFromSuperlayer];
    
    if (_buttonsContainerView) {
        _haloPushToTalk = [PulsingHaloLayer layer];
        _haloPushToTalk.position = _audioMuteButton.center;
        UIColor *color = [UIColor colorWithRed:118/255.f green:213/255.f blue:114/255.f alpha:1];
        _haloPushToTalk.backgroundColor = color.CGColor;
        _haloPushToTalk.radius = 40.0;
        _haloPushToTalk.haloLayerNumber = 2;
        _haloPushToTalk.keyTimeForHalfOpacity = 0.75;
        _haloPushToTalk.fromValueForRadius = 0.75;
        [_buttonsContainerView.layer addSublayer:_haloPushToTalk];
        [_haloPushToTalk start];
        
        [_buttonsContainerView bringSubviewToFront:_audioMuteButton];
    }
    
}

- (void)removeHaloFromAudioMuteButton
{
    if (_haloPushToTalk) {
        [_haloPushToTalk removeFromSuperlayer];
    }
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
    [cell.peerNameLabel setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
    [cell.buttonsContainerView setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
    
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGRect frame = [NBMPeersFlowLayout frameForWithNumberOfItems:_peersInCall.count
                                                             row:indexPath.row
                                                     contentSize:self.collectionView.frame.size];
    return frame.size;
}

-(void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    CallParticipantViewCell *participantCell = (CallParticipantViewCell *)cell;
    NCPeerConnection *peerConnection = [_peersInCall objectAtIndex:indexPath.row];
    
    [participantCell setVideoView:[_videoRenderersDict objectForKey:peerConnection.peerId]];
    [participantCell setUserAvatar:[_callController getUserIdFromSessionId:peerConnection.peerId]];
    [participantCell setDisplayName:peerConnection.peerName];
    [participantCell setAudioDisabled:peerConnection.isRemoteAudioDisabled];
    [participantCell setScreenShared:[_screenRenderersDict objectForKey:peerConnection.peerId]];
    [participantCell setVideoDisabled: (_isAudioOnly) ? YES : peerConnection.isRemoteVideoDisabled];
    [participantCell.peerNameLabel setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
    [participantCell.buttonsContainerView setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
}

#pragma mark - Call Controller delegate

- (void)callControllerDidJoinCall:(NCCallController *)callController
{
    [self setCallState:CallStateWaitingParticipants];
}

- (void)callControllerDidFailedJoiningCall:(NCCallController *)callController statusCode:(NSNumber *)statusCode errorReason:(NSString *) errorReason
{
    [self presentJoinError:errorReason];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        // Video renderers
        RTCEAGLVideoView *videoRenderer = [self->_videoRenderersDict objectForKey:peer.peerId];
        [[peer.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
        [self->_videoRenderersDict removeObjectForKey:peer.peerId];
        // Screen renderers
        RTCEAGLVideoView *screenRenderer = [self->_screenRenderersDict objectForKey:peer.peerId];
        [[peer.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
        [self->_screenRenderersDict removeObjectForKey:peer.peerId];
        
        [self->_peersInCall removeObject:peer];
    
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
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCEAGLVideoView *renderView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectZero];
        renderView.delegate = self;
        RTCVideoTrack *remoteVideoTrack = [remotePeer.remoteStream.videoTracks firstObject];
        [remoteVideoTrack addRenderer:renderView];
        
        if ([remotePeer.roomType isEqualToString:kRoomTypeVideo]) {
            [self->_videoRenderersDict setObject:renderView forKey:remotePeer.peerId];
            [self->_peersInCall addObject:remotePeer];
        } else if ([remotePeer.roomType isEqualToString:kRoomTypeScreen]) {
            [self->_screenRenderersDict setObject:renderView forKey:remotePeer.peerId];
            [self showScreenOfPeerId:remotePeer.peerId];
        }
        
        [self.collectionView reloadData];
    });
}

- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    
}

- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer
{
    if (state == RTCIceConnectionStateClosed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_peersInCall removeObject:peer];
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
    } else if ([message isEqualToString:@"speaking"] || [message isEqualToString:@"stoppedSpeaking"]) {
        if ([_peersInCall count] > 1) {
            [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
                [cell setSpeaking:peer.isPeerSpeaking];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCEAGLVideoView *screenRenderer = [self->_screenRenderersDict objectForKey:peer.peerId];
        [[peer.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
        [self->_screenRenderersDict removeObjectForKey:peer.peerId];
        [self closeScreensharingButtonPressed:self];
    
        [self.collectionView reloadData];
    });
}

- (void)callController:(NCCallController *)callController didReceiveForceMuteActionForPeerId:(NSString *)peerId
{
    if ([peerId isEqualToString:callController.userSessionId]) {
        [self forceMuteAudio];
    } else {
        NSLog(@"Peer was force muted: %@", peerId);
    }
}

- (void)callControllerIsReconnectingCall:(NCCallController *)callController
{
    [self setCallState:CallStateReconnecting];
}

#pragma mark - Screensharing

- (void)showScreenOfPeerId:(NSString *)peerId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCEAGLVideoView *renderView = [self->_screenRenderersDict objectForKey:peerId];
        [self->_screenView removeFromSuperview];
        self->_screenView = nil;
        self->_screenView = renderView;
        self->_screensharingSize = renderView.frame.size;
        [self->_screensharingView addSubview:self->_screenView];
        [self->_screensharingView bringSubviewToFront:self->_closeScreensharingButton];
        [UIView transitionWithView:self->_screensharingView duration:0.4
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{self->_screensharingView.hidden = NO;}
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
        [self->_screenView removeFromSuperview];
        self->_screenView = nil;
        [UIView transitionWithView:self->_screensharingView duration:0.4
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{self->_screensharingView.hidden = YES;}
                        completion:nil];
    });
    // Back to normal voice only UI
    if (_isAudioOnly) {
        [self invalidateDetailedViewTimer];
        [self showDetailedView];
        [self removeTapGestureForDetailedView];
    }
}

#pragma mark - RTCVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (RTCEAGLVideoView *rendererView in [self->_videoRenderersDict allValues]) {
            if ([videoView isEqual:rendererView]) {
                rendererView.frame = CGRectMake(0, 0, size.width, size.height);
            }
        }
        for (RTCEAGLVideoView *rendererView in [self->_screenRenderersDict allValues]) {
            if ([videoView isEqual:rendererView]) {
                rendererView.frame = CGRectMake(0, 0, size.width, size.height);
                if ([self->_screenView isEqual:rendererView]) {
                    self->_screensharingSize = rendererView.frame.size;
                    [self resizeScreensharingView];
                }
            }
        }
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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [self indexPathOfPeer:peer];
        CallParticipantViewCell *cell = (id)[self.collectionView cellForItemAtIndexPath:indexPath];
        block(cell);
    });
}

- (void)showPeersInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *visibleCells = [self->_collectionView visibleCells];
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
        NSArray *visibleCells = [self->_collectionView visibleCells];
        for (CallParticipantViewCell *cell in visibleCells) {
            [UIView animateWithDuration:0.3f animations:^{
                [cell.peerNameLabel setAlpha:0.0f];
                [cell.buttonsContainerView setAlpha:0.0f];
                [cell layoutIfNeeded];
            }];
        }
    });
}

- (IBAction)toggleChatButton:(id)sender {
}
@end
