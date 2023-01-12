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

#import <AVKit/AVKit.h>

#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoTrack.h>

#import "DBImageColorPicker.h"
#import "JDStatusBarNotification.h"
#import "UIImageView+AFNetworking.h"

#import "CallKitManager.h"
#import "CallParticipantViewCell.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCAudioController.h"
#import "NCCallController.h"
#import "NCDatabaseManager.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCSignalingMessage.h"
#import "NCUtils.h"

#import "NextcloudTalk-Swift.h"

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
    UIView <RTCVideoRenderer> *_screenView;
    CGSize _screensharingSize;
    UITapGestureRecognizer *_tapGestureForDetailedView;
    NSTimer *_detailedViewTimer;
    NSTimer *_proximityTimer;
    NSString *_displayName;
    BOOL _isAudioOnly;
    BOOL _isDetailedViewVisible;
    BOOL _userDisabledVideo;
    BOOL _userDisabledSpeaker;
    BOOL _videoCallUpgrade;
    BOOL _hangingUp;
    BOOL _pushToTalkActive;
    BOOL _isHandRaised;
    BOOL _proximityState;
    UIImpactFeedbackGenerator *_buttonFeedbackGenerator;
    CGPoint _localVideoDragStartingPosition;
    CGPoint _localVideoOriginPosition;
    AVRoutePickerView *_airplayView;
}

@property (nonatomic, strong) IBOutlet UIButton *audioMuteButton;
@property (nonatomic, strong) IBOutlet UIButton *speakerButton;
@property (nonatomic, strong) IBOutlet UIButton *videoDisableButton;
@property (nonatomic, strong) IBOutlet UIButton *switchCameraButton;
@property (nonatomic, strong) IBOutlet UIButton *hangUpButton;
@property (nonatomic, strong) IBOutlet UIButton *videoCallButton;
@property (nonatomic, strong) IBOutlet UIButton *recordingButton;
@property (nonatomic, strong) IBOutlet UIButton *lowerHandButton;
@property (nonatomic, strong) IBOutlet UIButton *moreMenuButton;
@property (nonatomic, strong) IBOutlet UICollectionView *collectionView;
@property (nonatomic, strong) IBOutlet UIView *topBarView;
@property (nonatomic, strong) IBOutlet UIStackView *topBarButtonStackView;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionDidChangeRoute:) name:AudioSessionDidChangeRouteNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionDidActivate:) name:AudioSessionWasActivatedByProviderNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    
    return self;
}

- (void)startCallWithSessionId:(NSString *)sessionId
{
    _callController = [[NCCallController alloc] initWithDelegate:self inRoom:_room forAudioOnlyCall:_isAudioOnly withSessionId:sessionId andVoiceChatMode:_voiceChatModeAtStart];
    _callController.userDisplayName = _displayName;
    _callController.disableVideoAtStart = _videoDisabledAtStart;
    _callController.silentCall = _silentCall;
    
    [_callController startCall];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setCallState:CallStateJoining];
    
    _tapGestureForDetailedView = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showDetailedViewWithTimer)];
    [_tapGestureForDetailedView setNumberOfTapsRequired:1];
    
    
    UILongPressGestureRecognizer *pushToTalkRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePushToTalk:)];
    pushToTalkRecognizer.delegate = self;
    [self.audioMuteButton addGestureRecognizer:pushToTalkRecognizer];
    
    [_screensharingView setHidden:YES];

    [self.hangUpButton.layer setCornerRadius:self.hangUpButton.frame.size.height / 2];
    [self.closeScreensharingButton.layer setCornerRadius:16.0f];

    [self.collectionView.layer setCornerRadius:30.0f];
    [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentAlways];
    
    _airplayView = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    _airplayView.tintColor = [UIColor whiteColor];
    _airplayView.activeTintColor = [UIColor whiteColor];
        
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
    self.recordingButton.accessibilityLabel = NSLocalizedString(@"Recording", nil);
    self.recordingButton.accessibilityHint = NSLocalizedString(@"Double tap to stop recording", nil);
    self.lowerHandButton.accessibilityLabel = NSLocalizedString(@"Lower hand", nil);
    self.lowerHandButton.accessibilityHint = NSLocalizedString(@"Double tap to lower hand", nil);
    self.moreMenuButton.accessibilityLabel = NSLocalizedString(@"More actions", nil);
    self.moreMenuButton.accessibilityHint = NSLocalizedString(@"Double tap to show more actions", nil);

    self.moreMenuButton.showsMenuAsPrimaryAction = YES;

    // Text color should be always white in the call view
    [self.titleView.titleButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.titleView updateForRoom:_room];

    // The titleView uses the themeColor as a background for the userStatusImage
    // As we always have a black background, we need to change that
    if (_room.statusMessage && ![_room.statusMessage isEqualToString:@""]) {
        [self.titleView.userStatusImage setBackgroundColor:UIColor.blackColor];
    }
    
    self.collectionView.delegate = self;
    
    [self createWaitingScreen];
    
    // We disableLocalVideo here even if the call controller has not been created just to show the video button as disabled
    // also we set _userDisabledVideo = YES so the proximity sensor doesn't enable it.
    if (_videoDisabledAtStart) {
        _userDisabledVideo = YES;
        [self disableLocalVideo];
    }
    
    if (_voiceChatModeAtStart) {
        _userDisabledSpeaker = YES;
    }

    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    // 'conversation-permissions' capability was not added in Talk 13 release, so we check for 'direct-mention-flag' capability
    // as a workaround.
    BOOL serverSupportsConversationPermissions =
    [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityConversationPermissions forAccountId:activeAccount.accountId] ||
    [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag forAccountId:activeAccount.accountId];
    if (serverSupportsConversationPermissions) {
        [self setAudioMuteButtonEnabled:(_room.permissions & NCPermissionCanPublishAudio)];
        [self setVideoDisableButtonEnabled:(_room.permissions & NCPermissionCanPublishVideo)];
    }
    
    [self.collectionView registerNib:[UINib nibWithNibName:kCallParticipantCellNibName bundle:nil] forCellWithReuseIdentifier:kCallParticipantCellIdentifier];
    [self.collectionView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
    
    UIPanGestureRecognizer *localVideoDragGesturure = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(localVideoDragged:)];
    [self.localVideoView addGestureRecognizer:localVideoDragGesturure];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChange:)
                                                 name:UIDeviceProximityStateDidChangeNotification object:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [self.collectionView.collectionViewLayout invalidateLayout];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self setLocalVideoRect];
        [self resizeScreensharingView];
        [self adjustTopBar];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
    }];
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self setLocalVideoRect];
    [self adjustTopBar];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self setLocalVideoRect];
    [self adjustSpeakerButton];
    [self adjustTopBar];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
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

#pragma mark - App lifecycle notifications

-(void)appDidBecomeActive:(NSNotification*)notification
{
    if (!_isAudioOnly && _callController && !_userDisabledVideo) {
        // Only enable video if it was not disabled by the user.
        [self enableLocalVideo];
    }
}

-(void)appWillResignActive:(NSNotification*)notification
{
    if (!_isAudioOnly && _callController && [_callController isVideoEnabled]) {
        // Disable video when the app moves to the background as we can't access the camera anymore.
        [self disableLocalVideo];
    }
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

#pragma mark - Audio controller notifications

- (void)audioSessionDidChangeRoute:(NSNotification *)notification
{
    [self adjustSpeakerButton];
}

- (void)audioSessionDidActivate:(NSNotification *)notification
{
    [self adjustSpeakerButton];
}

#pragma mark - Local video

- (void)setLocalVideoRect
{
    CGSize localVideoSize;
    
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

    UIEdgeInsets safeAreaInsets = self.view.safeAreaInsets;
    _localVideoOriginPosition = CGPointMake(16 + safeAreaInsets.left, 80 + safeAreaInsets.top);

    CGRect localVideoRect = CGRectMake(_localVideoOriginPosition.x, _localVideoOriginPosition.y, localVideoSize.width, localVideoSize.height);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_localVideoView.frame = localVideoRect;
        self->_localVideoView.layer.cornerRadius = 15.0f;
        self->_localVideoView.layer.masksToBounds = YES;
    });
}

#pragma mark - Proximity sensor

- (void)sensorStateChange:(NSNotificationCenter *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_proximityTimer invalidate];
        self->_proximityTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(adjustProximityState) userInfo:nil repeats:NO];
    });
}

- (void)adjustProximityState
{
    BOOL currentProximityState = [[UIDevice currentDevice] proximityState];

    if (currentProximityState == _proximityState) {
        return;
    }

    _proximityState = currentProximityState;

    if (!_isAudioOnly) {
        if (_proximityState == YES) {
            [self disableLocalVideo];
            [self disableSpeaker];
        } else {
            // Only enable video if it was not disabled by the user.
            if (!_userDisabledVideo) {
                [self enableLocalVideo];
            }
            if (!_userDisabledSpeaker) {
                [self enableSpeaker];
            }
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
    self.avatarBackgroundImageView.backgroundColor = [NCAppBranding themeColor];

    if (_room.type == kNCRoomTypeOneToOne) {
        __weak AvatarBackgroundImageView *weakBGView = self.avatarBackgroundImageView;
        [self.avatarBackgroundImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
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
    [self hidePeersInfo];
    [self invalidateDetailedViewTimer];
}

- (void)setAudioMuteButtonActive:(BOOL)active
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *micStatusString = nil;

        if (active) {
            micStatusString = NSLocalizedString(@"Microphone enabled", nil);
            [self->_audioMuteButton setImage:[UIImage imageNamed:@"audio"] forState:UIControlStateNormal];
        } else {
            micStatusString = NSLocalizedString(@"Microphone disabled", nil);
            [self->_audioMuteButton setImage:[UIImage imageNamed:@"audio-off"] forState:UIControlStateNormal];
        }

        self->_audioMuteButton.accessibilityValue = micStatusString;
    });
}

- (void)setAudioMuteButtonEnabled:(BOOL)enabled
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_audioMuteButton.enabled = enabled;
    });
}

- (void)setVideoDisableButtonActive:(BOOL)active
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *cameraStatusString = nil;

        if (active) {
            cameraStatusString = NSLocalizedString(@"Camera enabled", nil);
            [self->_videoDisableButton setImage:[UIImage imageNamed:@"video"] forState:UIControlStateNormal];
        } else {
            cameraStatusString = NSLocalizedString(@"Camera disabled", nil);
            [self->_videoDisableButton setImage:[UIImage imageNamed:@"video-off"] forState:UIControlStateNormal];
        }

        self->_videoDisableButton.accessibilityValue = cameraStatusString;
    });
}

- (void)setVideoDisableButtonEnabled:(BOOL)enabled
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_videoDisableButton.enabled = enabled;
    });
}

- (void)setLocalVideoViewHidden:(BOOL)hidden
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_localVideoView setHidden:hidden];
    });
}

- (void)adjustTopBar
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Enable/Disable video buttons
        self->_videoDisableButton.hidden = self->_isAudioOnly;
        self->_switchCameraButton.hidden = self->_isAudioOnly;
        self->_videoCallButton.hidden = !self->_isAudioOnly;

        self->_lowerHandButton.hidden = !self->_isHandRaised;
        self->_recordingButton.hidden = !self->_room.callRecording;
        self->_speakerButton.hidden = NO;

        // When the horizontal size is compact (e.g. iPhone portrait) we don't show the 'End call' text on the button
        // Don't make assumptions about the device here, because with split screen even an iPad can have a compact width
        if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
            [self->_hangUpButton setTitle:@"" forState:UIControlStateNormal];
            [self->_titleView setHidden:YES];
        } else {
            [self->_hangUpButton setTitle:NSLocalizedString(@"End call", nil) forState:UIControlStateNormal];
            [self->_titleView setHidden:NO];
        }

        // Make sure we get the correct frame for the stack view, after changing the visibility of buttons
        [self->_topBarView setNeedsLayout];
        [self->_topBarView layoutIfNeeded];

        // Hide the speaker button to make some more room for higher priority buttons
        // This should only be the case for iPhone SE (1st Gen) when recording is active and/or hand is raised
        if (self->_topBarButtonStackView.frame.origin.x < 0) {
            self->_speakerButton.hidden = YES;
        }

        [self adjustMoreButtonMenu];
    });
}

- (void)adjustMoreButtonMenu
{
    // When we target iOS 15, we might want to use an uncached UIDeferredMenuElement

    NSMutableArray *items = [[NSMutableArray alloc] init];

    // Add speaker button to menu if it was hidden from topbar
    if ([self.speakerButton isHidden]) {
        // TODO: Adjust for AirPlay?
        UIImage *speakerImage = [[UIImage imageNamed:@"speaker"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        NSString *speakerActionTitle = NSLocalizedString(@"Speaker", nil);

        if ([[NCAudioController sharedInstance] isSpeakerActive]) {
            speakerImage = [[UIImage imageNamed:@"speaker-off"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }

        UIAction *speakerAction = [UIAction actionWithTitle:speakerActionTitle image:speakerImage identifier:nil handler:^(UIAction *action) {
            [self speakerButtonPressed:nil];
        }];

        [items addObject:speakerAction];
    }

    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRaiseHand]) {
        NSString *raiseHandTitel = NSLocalizedString(@"Raise hand", nil);

        if (_isHandRaised) {
            raiseHandTitel = NSLocalizedString(@"Lower hand", nil);
        }

        UIAction *raiseHandAction = [UIAction actionWithTitle:raiseHandTitel image:[UIImage imageNamed:@"hand"] identifier:nil handler:^(UIAction *action) {
            [self->_callController raiseHand:!self->_isHandRaised];
            self->_isHandRaised = !self->_isHandRaised;
            [self adjustTopBar];
        }];

        [items addObject:raiseHandAction];
    }

    if ([self->_room canModerate] && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRecordingV1]) {
        UIImage *recordingImage = [UIImage imageNamed:@"record-circle"];
        NSString *recordingActionTitle = NSLocalizedString(@"Start recording", nil);

        if (self->_room.callRecording) {
            recordingImage = [UIImage imageNamed:@"stop-circle"];
            recordingActionTitle = NSLocalizedString(@"Stop recording", nil);
        }

        UIAction *recordingAction = [UIAction actionWithTitle:recordingActionTitle image:recordingImage identifier:nil handler:^(UIAction *action) {
            if (self->_room.callRecording) {
                [self showStopRecordingConfirmationDialog];
            } else {
                [self->_callController startRecording];
            }
        }];

        [items addObject:recordingAction];
    }

    self.moreMenuButton.menu = [UIMenu menuWithTitle:@"" children:items];
}

- (void)adjustSpeakerButton
{
    AVAudioSession *audioSession = [NCAudioController sharedInstance].rtcAudioSession.session;
    AVAudioSessionPortDescription *currentOutput = nil;
    if (audioSession.currentRoute.outputs.count > 0) {
        currentOutput = audioSession.currentRoute.outputs[0];
    }
    if ([currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
        [self setSpeakerButtonActive:YES];
    } else {
        [self setSpeakerButtonActive:NO];
    }
    
    // Show AirPlay button if there are more audio routes available
    if (audioSession.availableInputs.count > 1) {
        [self setSpeakerButtonWithAirplayButton];
    } else {
        [_airplayView removeFromSuperview];
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
    UIEdgeInsets safeAreaInsets = _localVideoView.superview.safeAreaInsets;
    UIEdgeInsets edgeInsets = UIEdgeInsetsMake(16 + _topBarView.frame.origin.y + _topBarView.frame.size.height, 16 + safeAreaInsets.left, 16 + safeAreaInsets.bottom, 16 + safeAreaInsets.right);

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
    if (position.x > parentSize.width - viewSize.width - edgeInsets.right) {
        position = CGPointMake(parentSize.width - viewSize.width - edgeInsets.right, position.y);
    }

    // Adjust bottom
    if (position.y > parentSize.height - viewSize.height - edgeInsets.bottom) {
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

        [_buttonFeedbackGenerator impactOccurred];
        _pushToTalkActive = YES;
    }
}

- (void)pushToTalkEnd
{
    if (_pushToTalkActive) {
        [self muteAudio];

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
    }
}

- (void)forceMuteAudio
{
    [self muteAudio];

    NSString *micDisabledString = NSLocalizedString(@"Microphone disabled", nil);
    NSString *forceMutedString = NSLocalizedString(@"You have been muted by a moderator", nil);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[JDStatusBarNotificationPresenter sharedPresenter] presentWithTitle:micDisabledString subtitle:forceMutedString includedStyle:JDStatusBarNotificationIncludedStyleDark completion:nil];
        [[JDStatusBarNotificationPresenter sharedPresenter] dismissAfterDelay:7.0];
    });
}

- (void)muteAudio
{
    [_callController enableAudio:NO];
    [self setAudioMuteButtonActive:NO];
}

- (void)unmuteAudio
{
    [_callController enableAudio:YES];
    [self setAudioMuteButtonActive:YES];
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
    [self setLocalVideoViewHidden:YES];
    [self setVideoDisableButtonActive:NO];
}

- (void)enableLocalVideo
{
    [_callController enableVideo:YES];
    [self setLocalVideoViewHidden:NO];
    [self setVideoDisableButtonActive:YES];
}

- (IBAction)switchCameraButtonPressed:(id)sender
{
    [self switchCamera];
}

- (void)switchCamera
{
    [_callController switchCamera];
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
        _userDisabledSpeaker = YES;
    } else {
        [self enableSpeaker];
        _userDisabledSpeaker = NO;
    }

    [self adjustMoreButtonMenu];
}

- (void)disableSpeaker
{
    [[NCAudioController sharedInstance] setAudioSessionToVoiceChatMode];
    [self setSpeakerButtonActive:NO];
    [self adjustSpeakerButton];
}

- (void)enableSpeaker
{
    [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
    [self setSpeakerButtonActive:YES];
    [self adjustSpeakerButton];
}

- (void)setSpeakerButtonActive:(BOOL)active
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *speakerStatusString = nil;

        if (active) {
            speakerStatusString = NSLocalizedString(@"Speaker enabled", nil);
            [self.speakerButton setImage:[UIImage imageNamed:@"speaker"] forState:UIControlStateNormal];
        } else {
            speakerStatusString = NSLocalizedString(@"Speaker disabled", nil);
            [self.speakerButton setImage:[UIImage imageNamed:@"speaker-off"] forState:UIControlStateNormal];
        }

        self.speakerButton.accessibilityValue = speakerStatusString;
        self.speakerButton.accessibilityHint = NSLocalizedString(@"Double tap to enable or disable the speaker", nil);
    });
}

- (void)setSpeakerButtonWithAirplayButton
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.speakerButton setImage:nil forState:UIControlStateNormal];
        self.speakerButton.accessibilityValue = NSLocalizedString(@"AirPlay button", nil);
        self.speakerButton.accessibilityHint = NSLocalizedString(@"Double tap to select different audio routes", nil);
        [self.speakerButton addSubview:self->_airplayView];
    });
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NCPeerConnection *peerConnection in self->_peersInCall) {
                // Video renderers
                RTCMTLVideoView *videoRenderer = [self->_videoRenderersDict objectForKey:peerConnection.peerId];
                [[peerConnection.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
                [self->_videoRenderersDict removeObjectForKey:peerConnection.peerId];
                // Screen renderers
                RTCMTLVideoView *screenRenderer = [self->_screenRenderersDict objectForKey:peerConnection.peerId];
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

        if (!_isAudioOnly) {
            [self.view bringSubviewToFront:_localVideoView];
        }

        [self removeTapGestureForDetailedView];
    } else {
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

- (IBAction)lowerHandButtonPressed:(id)sender
{
    self->_isHandRaised = NO;
    [self->_callController raiseHand:NO];
    [self adjustTopBar];
}

- (IBAction)videoRecordingButtonPressed:(id)sender
{
    if (![_room canModerate]) {
        return;
    }

    [self showStopRecordingConfirmationDialog];
}

- (void)showStopRecordingConfirmationDialog
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Stop recording", nil)
                                        message:NSLocalizedString(@"Do you want to stop the recording?", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *stopAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Stop", @"Action to 'Stop' a recording") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self->_callController stopRecording];
    }];
    [confirmDialog addAction:stopAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];

    [self presentViewController:confirmDialog animated:YES completion:nil];
}

#pragma mark - CallParticipantViewCell delegate

- (void)cellWantsToPresentScreenSharing:(CallParticipantViewCell *)participantCell
{
    [self showScreenOfPeerId:participantCell.peerId];
}

- (void)cellWantsToChangeZoom:(CallParticipantViewCell *)participantCell showOriginalSize:(BOOL)showOriginalSize
{
    NCPeerConnection *peer = [self peerConnectionForPeerId:participantCell.peerId];
    
    if (peer) {
        [peer setShowRemoteVideoInOriginalSize:showOriginalSize];
    }
}

#pragma mark - UICollectionView Datasource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    [self setCallStateForPeersInCall];
    return [_peersInCall count];
}

- (void)updateParticipantCell:(CallParticipantViewCell *)cell withPeerConnection:(NCPeerConnection *)peerConnection
{
    BOOL isVideoDisabled = peerConnection.isRemoteVideoDisabled;

    if (_isAudioOnly || peerConnection.remoteStream == nil || [peerConnection.remoteStream.videoTracks count] == 0) {
        isVideoDisabled = YES;
    }
    
    [cell setVideoView:[_videoRenderersDict objectForKey:peerConnection.peerId]];
    [cell setUserAvatar:[_callController getUserIdFromSessionId:peerConnection.peerId]];
    [cell setDisplayName:peerConnection.peerName];
    [cell setAudioDisabled:peerConnection.isRemoteAudioDisabled];
    [cell setScreenShared:[_screenRenderersDict objectForKey:peerConnection.peerId]];
    [cell setVideoDisabled: isVideoDisabled];
    [cell setShowOriginalSize:peerConnection.showRemoteVideoInOriginalSize];
    [cell setRaiseHand:peerConnection.isHandRaised];
    [cell.peerNameLabel setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
    [cell.audioOffIndicator setAlpha:_isDetailedViewVisible ? 1.0 : 0.0];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CallParticipantViewCell *cell = (CallParticipantViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:kCallParticipantCellIdentifier forIndexPath:indexPath];
    NCPeerConnection *peerConnection = [_peersInCall objectAtIndex:indexPath.row];
    cell.peerId = peerConnection.peerId;
    cell.actionsDelegate = self;
    
    [self updateParticipantCell:cell withPeerConnection:peerConnection];
    
    return cell;
}

-(void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    CallParticipantViewCell *participantCell = (CallParticipantViewCell *)cell;
    NCPeerConnection *peerConnection = [_peersInCall objectAtIndex:indexPath.row];
    
    [self updateParticipantCell:participantCell withPeerConnection:peerConnection];
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
    // Always add a joined peer, even if the peer doesn't publish any streams (yet)
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [self indexPathForPeerId:peer.peerId];
        if (!indexPath) {
            [self->_peersInCall addObject:peer];
            NSIndexPath *insertionIndexPath = [NSIndexPath indexPathForRow:self->_peersInCall.count - 1 inSection:0];
            [self.collectionView insertItemsAtIndexPaths:@[insertionIndexPath]];
        }
    });
    
}

- (void)callController:(NCCallController *)callController peerLeft:(NCPeerConnection *)peer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Video renderers
        RTCMTLVideoView *videoRenderer = [self->_videoRenderersDict objectForKey:peer.peerId];
        [[peer.remoteStream.videoTracks firstObject] removeRenderer:videoRenderer];
        [self->_videoRenderersDict removeObjectForKey:peer.peerId];
        // Screen renderers
        [self removeScreensharingOfPeer:peer];
        
        NSIndexPath *indexPath = [self indexPathForPeerId:peer.peerId];
        if (indexPath) {
            [self->_peersInCall removeObjectAtIndex:indexPath.row];
            [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
        }
    });
}

- (void)callController:(NCCallController *)callController didCreateLocalVideoCapturer:(RTCCameraVideoCapturer *)videoCapturer
{
    _localVideoView.captureSession = videoCapturer.captureSession;
}

- (void)callController:(NCCallController *)callController userPermissionsChanged:(NSInteger)permissions
{
    [self setAudioMuteButtonEnabled:(permissions & NCPermissionCanPublishAudio)];
    [self setVideoDisableButtonEnabled:(permissions & NCPermissionCanPublishVideo)];
}

- (void)callController:(NCCallController *)callController didCreateLocalAudioTrack:(RTCAudioTrack *)audioTrack
{
    [self setAudioMuteButtonActive:audioTrack.isEnabled];
}

- (void)callController:(NCCallController *)callController didCreateLocalVideoTrack:(RTCVideoTrack *)videoTrack
{
    [self setLocalVideoViewHidden:!videoTrack.isEnabled];
    [self setVideoDisableButtonActive:videoTrack.isEnabled];
    
    // We set _userDisabledVideo = YES so the proximity sensor doesn't enable it.
    if (!videoTrack.isEnabled) {
        _userDisabledVideo = YES;
    }
}

- (void)callController:(NCCallController *)callController didAddStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCMTLVideoView *renderView = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
        renderView.delegate = self;
        RTCVideoTrack *remoteVideoTrack = [remotePeer.remoteStream.videoTracks firstObject];
        [remoteVideoTrack addRenderer:renderView];
        
        if ([remotePeer.roomType isEqualToString:kRoomTypeVideo]) {
            [self->_videoRenderersDict setObject:renderView forKey:remotePeer.peerId];
            NSIndexPath *indexPath = [self indexPathForPeerId:remotePeer.peerId];
            if (!indexPath) {
                [self->_peersInCall addObject:remotePeer];
                NSIndexPath *insertionIndexPath = [NSIndexPath indexPathForRow:self->_peersInCall.count - 1 inSection:0];
                [self.collectionView insertItemsAtIndexPaths:@[insertionIndexPath]];
            } else {
                [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
            }
        } else if ([remotePeer.roomType isEqualToString:kRoomTypeScreen]) {
            [self->_screenRenderersDict setObject:renderView forKey:remotePeer.peerId];
            [self showScreenOfPeerId:remotePeer.peerId];
            [self updatePeer:remotePeer block:^(CallParticipantViewCell *cell) {
                [cell setScreenShared:YES];
            }];
        }
    });
}

- (void)callController:(NCCallController *)callController didRemoveStream:(RTCMediaStream *)remoteStream ofPeer:(NCPeerConnection *)remotePeer
{
    
}

- (void)callController:(NCCallController *)callController iceStatusChanged:(RTCIceConnectionState)state ofPeer:(NCPeerConnection *)peer
{
    if (state == RTCIceConnectionStateClosed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([peer.roomType isEqualToString:kRoomTypeVideo]) {
                NSIndexPath *indexPath = [self indexPathForPeerId:peer.peerId];
                if (indexPath) {
                    [self->_peersInCall removeObjectAtIndex:indexPath.row];
                    [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
                }
            } else if ([peer.roomType isEqualToString:kRoomTypeScreen]) {
                [self removeScreensharingOfPeer:peer];
            }
        });
    } else if ([peer.roomType isEqualToString:kRoomTypeVideo]) {
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
    } else if ([message isEqualToString:@"raiseHand"]) {
        [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
            [cell setRaiseHand:peer.isHandRaised];
        }];
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
    [self removeScreensharingOfPeer:peer];
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

- (void)callControllerWantsToHangUpCall:(NCCallController *)callController
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hangup];
    });
}

- (void)callControllerDidChangeRecording:(NCCallController *)callController
{
    [self adjustTopBar];
}

#pragma mark - Screensharing

- (void)showScreenOfPeerId:(NSString *)peerId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCMTLVideoView *renderView = [self->_screenRenderersDict objectForKey:peerId];
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

- (void)removeScreensharingOfPeer:(NCPeerConnection *)peer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RTCMTLVideoView *screenRenderer = [self->_screenRenderersDict objectForKey:peer.peerId];
        [[peer.remoteStream.videoTracks firstObject] removeRenderer:screenRenderer];
        [self->_screenRenderersDict removeObjectForKey:peer.peerId];
        [self updatePeer:peer block:^(CallParticipantViewCell *cell) {
            [cell setScreenShared:NO];
        }];
        if (self->_screenView == screenRenderer) {
            [self closeScreensharingButtonPressed:self];
        }
    });
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

- (void)videoView:(RTCMTLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (RTCMTLVideoView *rendererView in [self->_videoRenderersDict allValues]) {
            if ([videoView isEqual:rendererView]) {
                rendererView.frame = CGRectMake(0, 0, size.width, size.height);
                NSArray *keys = [self->_videoRenderersDict allKeysForObject:videoView];
                if (keys.count) {
                    NSIndexPath *indexPath = [self indexPathForPeerId:keys[0]];
                    if (indexPath) {
                        CallParticipantViewCell *participantCell = (CallParticipantViewCell *) [self.collectionView cellForItemAtIndexPath:indexPath];
                        [participantCell setRemoteVideoSize:size];
                    }
                }
            }
        }
        for (RTCMTLVideoView *rendererView in [self->_screenRenderersDict allValues]) {
            if ([videoView isEqual:rendererView]) {
                rendererView.frame = CGRectMake(0, 0, size.width, size.height);
                if ([self->_screenView isEqual:rendererView]) {
                    self->_screensharingSize = rendererView.frame.size;
                    [self resizeScreensharingView];
                }
            }
        }
    });
}

#pragma mark - Cell updates

- (NSIndexPath *)indexPathForPeerId:(NSString *)peerId
{
    NSIndexPath *indexPath = nil;
    for (int i = 0; i < _peersInCall.count; i ++) {
        NCPeerConnection *peer = [_peersInCall objectAtIndex:i];
        if ([peer.peerId isEqualToString:peerId]) {
            indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        }
    }
    
    return indexPath;
}

- (void)updatePeer:(NCPeerConnection *)peer block:(void(^)(CallParticipantViewCell* cell))block
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [self indexPathForPeerId:peer.peerId];
        if (indexPath) {
            CallParticipantViewCell *cell = (id)[self.collectionView cellForItemAtIndexPath:indexPath];
            block(cell);
        }
    });
}

- (NCPeerConnection *)peerConnectionForPeerId:(NSString *)peerId {
    for (NCPeerConnection *peerConnection in self->_peersInCall) {
        if ([peerConnection.peerId isEqualToString:peerId]) {
            return peerConnection;
        }
    }
    
    return nil;
}

- (void)showPeersInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *visibleCells = [self->_collectionView visibleCells];
        for (CallParticipantViewCell *cell in visibleCells) {
            [UIView animateWithDuration:0.3f animations:^{
                [cell.peerNameLabel setAlpha:1.0f];
                [cell.audioOffIndicator setAlpha:1.0f];
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
                // Don't hide raise hand indicator, that should always be visible
                [cell.peerNameLabel setAlpha:0.0f];
                [cell.audioOffIndicator setAlpha:0.0f];
                [cell layoutIfNeeded];
            }];
        }
    });
}

@end
