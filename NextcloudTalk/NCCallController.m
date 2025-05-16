/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCCallController.h"

#import <WebRTC/RTCConfiguration.h>
#import <WebRTC/RTCDataChannelConfiguration.h>
#import <WebRTC/RTCMediaConstraints.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCPeerConnectionFactory.h>
#import <WebRTC/RTCAudioTrack.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCVideoCapturer.h>
#import <WebRTC/RTCVideoSource.h>
#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>
#import <WebRTC/RTCDefaultVideoDecoderFactory.h>

#import "ARDCaptureController.h"

#import "CallConstants.h"
#import "CallKitManager.h"
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCSignalingController.h"
#import "NCExternalSignalingController.h"
#import "NCScreensharingController.h"

#import "NextcloudTalk-Swift.h"

static NSString * const kNCMediaStreamId    = @"NCMS";
static NSString * const kNCAudioTrackId     = @"NCa0";
static NSString * const kNCVideoTrackId     = @"NCv0";
static NSString * const kNCVideoTrackKind   = @"video";
static NSString * const kNCScreenTrackId    = @"NCs0";
static NSString * const kNCScreenTrackKind  = @"screen";

@interface NCCallController () <NCPeerConnectionDelegate, NCSignalingControllerObserver, NCExternalSignalingControllerDelegate, NCCameraControllerDelegate>

@property (nonatomic, assign) BOOL isAudioOnly;
@property (nonatomic, assign) BOOL leavingCall;
@property (nonatomic, assign) BOOL preparedForRejoin;
@property (nonatomic, assign) BOOL joinedCallOnce;
@property (nonatomic, assign) BOOL shouldRejoinCallUsingInternalSignaling;
@property (nonatomic, assign) BOOL serverSupportsConversationPermissions;
@property (nonatomic, assign) NSInteger joinCallAttempts;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSTimer *micAudioLevelTimer;
@property (nonatomic, assign) BOOL speaking;
@property (nonatomic, assign) NSInteger userInCall;
@property (nonatomic, assign) NSInteger userPermissions;
@property (nonatomic, strong) NSTimer *sendCurrentStateTimer;
@property (nonatomic, strong) NSArray *usersInRoom;
@property (nonatomic, strong) NSArray *sessionsInCall;
@property (nonatomic, strong) NSArray *peersInCall;
@property (nonatomic, strong) NCPeerConnection *publisherPeerConnection;
@property (nonatomic, strong) NCPeerConnection *screenPublisherPeerConnection;
@property (nonatomic, strong) NSMutableDictionary *connectionsDict;
@property (nonatomic, strong) NSMutableDictionary *pendingOffersDict;
@property (nonatomic, strong) RTCAudioTrack *localAudioTrack;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property (nonatomic, strong) RTCVideoTrack *localScreenTrack;
@property (nonatomic, strong) ARDCaptureController *localVideoCaptureController;
@property (nonatomic, strong) NCSignalingController *signalingController;
@property (nonatomic, strong) NCExternalSignalingController *externalSignalingController;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NSURLSessionTask *joinCallTask;
@property (nonatomic, strong) NSURLSessionTask *getPeersForCallTask;
@property (nonatomic, strong) NCCameraController *cameraController;
@property (nonatomic, strong) NCScreensharingController *screensharingController;

@end

@implementation NCCallController

- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId andVoiceChatMode:(BOOL)voiceChatMode
{
    self = [super init];
    
    if (self) {
        [NCUtils log:[NSString stringWithFormat:@"Creating call controller for token %@", room.token]];

        _delegate = delegate;
        _room = room;
        _userPermissions = _room.permissions;
        _isAudioOnly = audioOnly;
        _userSessionId = sessionId;
        _connectionsDict = [[NSMutableDictionary alloc] init];
        _pendingOffersDict = [[NSMutableDictionary alloc] init];
        _usersInRoom = [[NSArray alloc] init];
        _sessionsInCall = [[NSArray alloc] init];
        _peersInCall = [[NSArray alloc] init];
        
        _signalingController = [[NCSignalingController alloc] initForRoom:room];
        _signalingController.observer = self;
        
        _account = [[NCDatabaseManager sharedInstance] activeAccount];

        // NCCallController is only initialized after joining the room. At that point we ensured that there's
        // an external signaling controller set, in case we are using external signaling.
        _externalSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:_account.accountId];
        _externalSignalingController.delegate = self;
        
        // 'conversation-permissions' capability was not added in Talk 13 release, so we check for 'direct-mention-flag' capability
        // as a workaround.
        _serverSupportsConversationPermissions =
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityConversationPermissions forAccountId:_account.accountId] ||
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag forAccountId:_account.accountId];

        [[WebRTCCommon shared] dispatch:^{
            if (audioOnly || voiceChatMode) {
                [[NCAudioController sharedInstance] setAudioSessionToVoiceChatMode];
            } else {
                [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
            }
        }];
        
        [self initRecorder];

        // Screensharing is done in an extension, therefore we need to listen to systemwide notifications#
        [[DarwinNotificationCenter shared] addHandlerWithNotificationName:DarwinNotificationCenter.broadcastStartedNotification owner:self completionBlock:^{
            [[WebRTCCommon shared] dispatch:^{
                [self startScreenshare];
            }];
        }];

        [[DarwinNotificationCenter shared] addHandlerWithNotificationName:DarwinNotificationCenter.broadcastStoppedNotification owner:self completionBlock:^{
            [[WebRTCCommon shared] dispatch:^{
                [self stopScreenshare];
            }];
        }];

        _screensharingController = [[NCScreensharingController alloc] init];

        [[AllocationTracker shared] addAllocation:@"NCCallController"];
    }
    
    return self;
}

- (void)startCall
{
    [NCUtils log:[NSString stringWithFormat:@"Start call in NCCallController for token %@", self.room.token]];

    // Make sure the signaling controller has retrieved the settings before joining a call
    [_signalingController updateSignalingSettingsWithCompletionBlock:^(SignalingSettings *signalingSettings) {
        AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

        if (!self->_isAudioOnly && authStatus == AVAuthorizationStatusNotDetermined) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                [self createLocalMedia];
                [self joinCall];
            }];

            return;
        }

        [self createLocalMedia];
        [self joinCall];
    }];
}

- (NSString *)signalingSessionId
{
    if (_externalSignalingController) {
        return [_externalSignalingController sessionId];
    }
    return _userSessionId;
}

- (NSInteger)joinCallFlags
{
    NSInteger flags = CallFlagInCall;
    
    if ((_userPermissions & NCPermissionCanPublishAudio) != 0 || !_serverSupportsConversationPermissions) {
        flags += CallFlagWithAudio;
    }
    
    if (!_isAudioOnly && ((_userPermissions & NCPermissionCanPublishVideo) != 0 || !_serverSupportsConversationPermissions)) {
        flags += CallFlagWithVideo;
    }
    
    return flags;
}

- (void)joinCall
{
    [NCUtils log:[NSString stringWithFormat:@"Join call in NCCallController for token %@", self.room.token]];

    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token withCallFlags:[self joinCallFlags] silently:_silentCall silentFor:_silentFor recordingConsent:_recordingConsent forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        [[WebRTCCommon shared] dispatch:^{
            if (!error) {
                [NCUtils log:[NSString stringWithFormat:@"Did join call in NCCallController for token %@", self.room.token]];

                [self.delegate callControllerDidJoinCall:self];
                [self startMonitoringMicrophoneAudioLevel];

                if (self->_externalSignalingController) {
                    if ([self->_externalSignalingController hasMCU]) {
                        [self createPublisherPeerConnection];
                    }
                } else {
                    // Only with internal signaling we need to query the API for peers in call
                    [self getPeersForCall];
                    [self->_signalingController startPullingSignalingMessages];
                }

                self->_joinedCallOnce = YES;
                self->_joinCallAttempts = 0;
            } else {
                if (error.code == NSURLErrorCancelled) {
                    self->_joinCallAttempts = 0;
                    return;
                }

                if (self->_joinCallAttempts < 3) {
                    [NCUtils log:[NSString stringWithFormat:@"Could not join call in %@, retrying. %ld", self.room.token, self.joinCallAttempts]];
                    self->_joinCallAttempts += 1;

                    if (statusCode == 404) {
                        // The conversation was not correctly joined by us / our session expired
                        // Instead of joining again, try to reconnect to correctly join the conversation again
                        [self forceReconnect];
                    } else {
                        [self joinCall];
                    }

                    return;
                }

                [self.delegate callControllerDidFailedJoiningCall:self statusCode:statusCode errorReason:[self getJoinCallErrorReason:statusCode]];
                [NCUtils log:[NSString stringWithFormat:@"Could not join call in %@, StatusCode: %ld, Error: %@", self.room.token, statusCode, error.description]];
            }
        }];
    }];
}

- (NSString *)getJoinCallErrorReason:(NSInteger)statusCode
{
    NSString *errorReason = NSLocalizedString(@"Unknown error occurred", nil);
    
    switch (statusCode) {
        case 0:
            errorReason = NSLocalizedString(@"No response from server", nil);
            break;

        case 400:
            errorReason = NSLocalizedString(@"Recording consent is required", nil);
            break;

        case 403:
            errorReason = NSLocalizedString(@"This conversation is read-only", nil);
            break;
            
        case 404:
            errorReason = NSLocalizedString(@"Conversation not found or not joined", nil);
            break;
            
        case 412:
            errorReason = NSLocalizedString(@"Lobby is still active and you're not a moderator", nil);
            break;
    }
    
    return errorReason;
}

- (void)shouldRejoinCall
{
    [self createLocalMedia];

    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token withCallFlags:[self joinCallFlags] silently:_silentCall silentFor:_silentFor recordingConsent:_recordingConsent forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        [[WebRTCCommon shared] dispatch:^{
            if (!error) {
                [self.delegate callControllerDidJoinCall:self];
                NSLog(@"Rejoined call");

                if ([self->_externalSignalingController hasMCU]) {
                    [self createPublisherPeerConnection];
                }

                self->_joinCallAttempts = 0;
            } else {
                if (self->_joinCallAttempts < 3) {
                    NSLog(@"Could not rejoin call, retrying. %ld", (long)self->_joinCallAttempts);
                    self->_joinCallAttempts += 1;
                    [self shouldRejoinCall];
                    return;
                }

                [self.delegate callControllerDidFailedJoiningCall:self statusCode:statusCode errorReason:[self getJoinCallErrorReason:statusCode]];
                NSLog(@"Could not rejoin call. Error: %@", error.description);
            }
        }];
    }];
}

- (void)willRejoinCall
{
    NSLog(@"willRejoinCall");

    [[WebRTCCommon shared] dispatch:^{
        self->_userInCall = 0;
        [self cleanCurrentPeerConnections];
        [self.delegate callControllerIsReconnectingCall:self];
        self->_preparedForRejoin = YES;
    }];
}

- (void)willSwitchToCall:(NSString *)token
{
    NSLog(@"willSwitchToCall");

    [[WebRTCCommon shared] dispatch:^{
        BOOL isAudioEnabled = [self isAudioEnabled];
        BOOL isVideoEnabled = [self isVideoEnabled];

        [self stopCallController];

        [self leaveCallInServerForAll:NO withCompletionBlock:^(NSError *error) {
            if (error) {
                NSLog(@"Could not leave call. Error: %@", error.description);
            }
            [self.delegate callController:self isSwitchingToCall:token withAudioEnabled:isAudioEnabled andVideoEnabled:isVideoEnabled];
        }];
    }];
}


- (void)forceReconnect
{
    [NCUtils log:@"Force reconnect"];

    [[WebRTCCommon shared] dispatch:^{
        [self.joinCallTask cancel];
        self.joinCallTask = nil;

        self->_userInCall = 0;
        [self cleanCurrentPeerConnections];
        [self.delegate callControllerIsReconnectingCall:self];

        // Remember current audio and video status before rejoin the call
        self->_disableAudioAtStart = ![self isAudioEnabled];
        self->_disableVideoAtStart = ![self isVideoEnabled];

        if (!self->_externalSignalingController) {
            [self rejoinCallUsingInternalSignaling];
            return;
        }

        [self->_externalSignalingController forceReconnectForRejoin];
    }];
}

- (void)rejoinCallUsingInternalSignaling
{
    [[NCAPIController sharedInstance] leaveCall:_room.token forAllParticipants:NO forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            self->_shouldRejoinCallUsingInternalSignaling = YES;
        }
    }];
}

- (void)stopCallController
{
    [self setLeavingCall:YES];
    [self stopSendingCurrentState];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[DarwinNotificationCenter shared] removeHandlerWithNotificationName:DarwinNotificationCenter.broadcastStartedNotification owner:self];
    [[DarwinNotificationCenter shared] removeHandlerWithNotificationName:DarwinNotificationCenter.broadcastStoppedNotification owner:self];

    _externalSignalingController.delegate = nil;

    [self->_cameraController stopAVCaptureSession];
    
    [[WebRTCCommon shared] dispatch:^{
        [self stopScreenshare];
        [self cleanCurrentPeerConnections];
        self->_localAudioTrack = nil;
        self->_localVideoTrack = nil;
        self->_connectionsDict = nil;
    }];
    
    [self stopMonitoringMicrophoneAudioLevel];
    [_signalingController stopAllRequests];
    
    [_getPeersForCallTask cancel];
    _getPeersForCallTask = nil;
    
    [_joinCallTask cancel];
    _joinCallTask = nil;
}

- (void)leaveCallInServerForAll:(BOOL)allParticipants withCompletionBlock:(LeaveCallCompletionBlock)block
{
    if (_userInCall) {
        [[NCAPIController sharedInstance] leaveCall:_room.token forAllParticipants:allParticipants forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
            block(error);
        }];
    } else {
        block(nil);
    }
}

- (void)leaveCallForAll:(BOOL)allParticipants
{
    [self stopCallController];

    [self leaveCallInServerForAll:allParticipants withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Could not leave call. Error: %@", error.description);
        }
        [self.delegate callControllerDidEndCall:self];
    }];

    [[WebRTCCommon shared] dispatch:^{
        [[NCAudioController sharedInstance] disableAudioSession];
    }];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[DarwinNotificationCenter shared] removeHandlerWithNotificationName:DarwinNotificationCenter.broadcastStartedNotification owner:self];
    [[DarwinNotificationCenter shared] removeHandlerWithNotificationName:DarwinNotificationCenter.broadcastStoppedNotification owner:self];
    [[AllocationTracker shared] removeAllocation:@"NCCallController"];
    NSLog(@"NCCallController dealloc");
}

- (BOOL)isVideoEnabled
{
    [[WebRTCCommon shared] assertQueue];

    return _localVideoTrack ? _localVideoTrack.isEnabled : NO;
}

- (BOOL)isAudioEnabled
{
    [[WebRTCCommon shared] assertQueue];

    return _localAudioTrack ? _localAudioTrack.isEnabled : NO;
}

- (void)getVideoEnabledStateWithCompletionBlock:(GetAudioEnabledStateCompletionBlock)block
{
    [[WebRTCCommon shared] dispatch:^{
        if (block) {
            block([self isVideoEnabled]);
        }
    }];
}

- (void)getAudioEnabledStateWithCompletionBlock:(GetAudioEnabledStateCompletionBlock)block
{
    [[WebRTCCommon shared] dispatch:^{
        if (block) {
            block([self isAudioEnabled]);
        }
    }];
}

- (void)switchCamera
{
    [self.cameraController switchCamera];
}

- (void)enableVideo:(BOOL)enable
{
    [[WebRTCCommon shared] dispatch:^{
        if (enable) {
            [self->_localVideoCaptureController startCapture];
        } else {
            [self->_localVideoCaptureController stopCapture];
        }

        [self->_localVideoTrack setIsEnabled:enable];
        [self sendMessageToAllOfType:enable ? @"videoOn" : @"videoOff" withPayload:nil];
    }];
}

- (void)enableAudio:(BOOL)enable
{
    [[WebRTCCommon shared] dispatch:^{
        [self->_localAudioTrack setIsEnabled:enable];
        [self sendMessageToAllOfType:enable ? @"audioOn" : @"audioOff" withPayload:nil];

        if (!enable) {
            self->_speaking = NO;
            [self sendMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
        }
    }];
}

- (BOOL)isBackgroundBlurEnabled
{
    return [self.cameraController isBackgroundBlurEnabled];
}

- (void)enableBackgroundBlur:(BOOL)enable
{
    [self.cameraController enableBackgroundBlurWithEnable:enable];
}

- (BOOL)isCameraAccessAvailable {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusAuthorized);
}

- (BOOL)isMicrophoneAccessAvailable
{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    return (authStatus == AVAuthorizationStatusAuthorized);
}

- (void)stopCapturing
{
    [self.cameraController stopAVCaptureSession];
}

- (void)raiseHand:(BOOL)raised
{
    [[WebRTCCommon shared] dispatch:^{
        NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970] * 1000;

        NSDictionary *payload = @{
            @"state": @(raised),
            @"timestamp": [NSString stringWithFormat:@"%.0f", timeStamp]
        };

        for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
            NCRaiseHandMessage *message = [[NCRaiseHandMessage alloc] initWithFrom:[self signalingSessionId]
                                                                                to:peer.peerId
                                                                               sid:peer.sid
                                                                          roomType:peer.roomType
                                                                           payload:payload];

            if (self->_externalSignalingController) {
                [self->_externalSignalingController sendCallMessage:message];
            } else {
                [self->_signalingController sendSignalingMessage:message];
            }
        }
    }];

    // Request or stop requesting assistance if we are in a breakout room and we are not moderators
    if (![_room isBreakoutRoom] || _room.canModerate) {
        return;
    }

    if (raised) {
        [[NCAPIController sharedInstance] requestAssistanceInRoom:_room.token forAccount:_account withCompletionBlock:^(NSError *error) {
            if (error) {
                NSLog(@"Error requesting assistance");
            }
        }];
    } else {
        [[NCAPIController sharedInstance] stopRequestingAssistanceInRoom:_room.token forAccount:_account withCompletionBlock:^(NSError *error) {
            if (error) {
                NSLog(@"Error on stop requesting assisntance");
            }
        }];
    }
}

- (void)sendReaction:(NSString *)reaction
{
    [[WebRTCCommon shared] dispatch:^{
        NSDictionary *payload = @{
            @"reaction": reaction
        };

        for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
            NCReactionMessage *message = [[NCReactionMessage alloc] initWithFrom:[self signalingSessionId]
                                                                              to:peer.peerId
                                                                             sid:peer.sid
                                                                        roomType:peer.roomType
                                                                         payload:payload];

            if (self->_externalSignalingController) {
                [self->_externalSignalingController sendCallMessage:message];
            } else {
                [self->_signalingController sendSignalingMessage:message];
            }
        }
    }];
}

- (void)startRecording
{
    [[NCAPIController sharedInstance] startRecording:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Could not start call recording. Error: %@", error.description);
        }
    }];
}

- (void)stopRecording
{
    [[NCAPIController sharedInstance] stopRecording:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Could not stop call recording. Error: %@", error.description);
        }
    }];
}

- (void)startScreenshare
{
    [[WebRTCCommon shared] assertQueue];

    if (_screensharingActive) {
        return;
    }

    RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
    RTCVideoSource *videoSource = [peerConnectionFactory videoSource];
    RTCVideoCapturer *videoCapturer = [[RTCVideoCapturer alloc] initWithDelegate:videoSource];

    [_screensharingController startCaptureWithVideoSource:videoSource withVideoCapturer:videoCapturer];
    _localScreenTrack = [peerConnectionFactory videoTrackWithSource:videoSource trackId:kNCScreenTrackId];

    if (_externalSignalingController && [_externalSignalingController hasMCU]) {
        [self createScreenPublisherPeerConnection];
    } else {
        for (NSString *session in _sessionsInCall) {
            if (![session isEqualToString:[self signalingSessionId]]) {
                [self sendScreensharingOfferToSessionId:session];
            }
        }
    }

    _screensharingActive = YES;
    [self.delegate callControllerDidChangeScreenrecording:self];
}

- (void)sendScreensharingOfferToSessionId:(NSString *)sessionId
{
    NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:sessionId withSid:nil ofType:kRoomTypeScreen forOwnScreenshare:YES];
    [peerConnectionWrapper sendPublisherOffer];
}

- (void)stopScreenshare {
    [[WebRTCCommon shared] assertQueue];

    [_screensharingController stopCapture];

    if (_externalSignalingController) {
        // Close screen publisher peer connection
        [self->_screenPublisherPeerConnection close];
        self->_screenPublisherPeerConnection = nil;

        NSString *peerKey = [self getPeerKeyWithSessionId:[self signalingSessionId] ofType:kRoomTypeScreen forOwnScreenshare:YES];
        [_connectionsDict removeObjectForKey:peerKey];

        // Send unshare screen signaling message to all the other peers
        [_externalSignalingController sendRoomMessageOfType:@"unshareScreen" andRoomType:kRoomTypeScreen];
    } else {
        for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
            // Close all own screen peer connections
            if (peer.isOwnScreensharePeer) {
                [self cleanPeerConnectionForSessionId:peer.peerId ofType:kRoomTypeScreen forOwnScreenshare:YES];
            }
            // Send unshare screen signaling message to all the other peers
            else {
                NCSignalingMessage *message = [[NCUnshareScreenMessage alloc] initWithFrom:[self signalingSessionId]
                                                                                        to:peer.peerId
                                                                                       sid:peer.sid
                                                                                  roomType:peer.roomType
                                                                                   payload:@{}];
                [_signalingController sendSignalingMessage:message];
            }
        }
    }

    _screensharingActive = NO;
    [self.delegate callControllerDidChangeScreenrecording:self];
}

#pragma mark - Call controller

- (void)cleanCurrentPeerConnections
{
    [[WebRTCCommon shared] assertQueue];

    for (NCPeerConnection *peerConnectionWrapper in [_connectionsDict allValues]) {
        if (!peerConnectionWrapper.isMCUPublisherPeer) {
            if ([peerConnectionWrapper.roomType isEqualToString:kRoomTypeVideo]) {
                [self.delegate callController:self peerLeft:peerConnectionWrapper];
            } else if ([peerConnectionWrapper.roomType isEqualToString:kRoomTypeScreen]) {
                [self.delegate callController:self didReceiveUnshareScreenFromPeer:peerConnectionWrapper];
            }
        }

        peerConnectionWrapper.delegate = nil;
        [peerConnectionWrapper close];
    }

    for (NSTimer *pendingOfferTimer in [_pendingOffersDict allValues]) {
        [pendingOfferTimer invalidate];
    }

    _connectionsDict = [[NSMutableDictionary alloc] init];
    _pendingOffersDict = [[NSMutableDictionary alloc] init];
    _usersInRoom = [[NSArray alloc] init];
    _sessionsInCall = [[NSArray alloc] init];
    _publisherPeerConnection = nil;
    _screenPublisherPeerConnection = nil;
}

- (void)cleanPeerConnectionForSessionId:(NSString *)sessionId ofType:(NSString *)roomType forOwnScreenshare:(BOOL)ownScreenshare
{
    [[WebRTCCommon shared] assertQueue];

    NSString *peerKey = [self getPeerKeyWithSessionId:sessionId ofType:roomType forOwnScreenshare:ownScreenshare];
    NCPeerConnection *removedPeerConnection = [_connectionsDict objectForKey:peerKey];

    if (removedPeerConnection) {
        if ([roomType isEqualToString:kRoomTypeVideo]) {
            NSLog(@"Removing peer from call: %@", sessionId);
            [self.delegate callController:self peerLeft:removedPeerConnection];
        } else if ([roomType isEqualToString:kRoomTypeScreen] && !ownScreenshare) {
            NSLog(@"Removing screensharing from peer: %@", sessionId);
            [self.delegate callController:self didReceiveUnshareScreenFromPeer:removedPeerConnection];
        }

        removedPeerConnection.delegate = nil;
        [removedPeerConnection close];

        [_connectionsDict removeObjectForKey:peerKey];
    }
}

- (void)cleanAllPeerConnectionsForSessionId:(NSString *)sessionId
{
    [[WebRTCCommon shared] assertQueue];

    [self cleanPeerConnectionForSessionId:sessionId ofType:kRoomTypeVideo forOwnScreenshare:NO];
    [self cleanPeerConnectionForSessionId:sessionId ofType:kRoomTypeScreen forOwnScreenshare:NO];
    
    // Invalidate possible request timers
    NSString *peerVideoKey = [sessionId stringByAppendingString:kRoomTypeVideo];
    NSTimer *pendingVideoRequestTimer = [_pendingOffersDict objectForKey:peerVideoKey];

    if (pendingVideoRequestTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [pendingVideoRequestTimer invalidate];
        });
    }

    NSString *peerScreenKey = [sessionId stringByAppendingString:kRoomTypeVideo];
    NSTimer *pendingScreenRequestTimer = [_pendingOffersDict objectForKey:peerScreenKey];

    if (pendingScreenRequestTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [pendingScreenRequestTimer invalidate];
        });
    }
}

#pragma mark - Microphone audio level

- (void)startMonitoringMicrophoneAudioLevel
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_micAudioLevelTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkMicAudioLevel) userInfo:nil repeats:YES];
    });
}

- (void)stopMonitoringMicrophoneAudioLevel
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_micAudioLevelTimer invalidate];
        self->_micAudioLevelTimer = nil;
        [self->_recorder stop];
        self->_recorder = nil;
    });
}

- (void)initRecorder
{
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat: 44100.0],                 AVSampleRateKey,
                              [NSNumber numberWithInt: kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt: 0],                         AVNumberOfChannelsKey,
                              [NSNumber numberWithInt: AVAudioQualityMax],         AVEncoderAudioQualityKey,
                              nil];
    
    NSError *error;
    
    _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
    if (_recorder) {
        [_recorder prepareToRecord];
        _recorder.meteringEnabled = YES;
        [_recorder record];
    } else {
        NSLog(@"Failed initializing recorder.");
    }
}

- (void)checkMicAudioLevel
{
    [[WebRTCCommon shared] dispatch:^{
        if ([self isAudioEnabled]) {
            [self->_recorder updateMeters];
            float averagePower = [self->_recorder averagePowerForChannel:0];

            if (averagePower >= -50.0f && !self->_speaking) {
                self->_speaking = YES;
                [self sendMessageToAllOfType:@"speaking" withPayload:nil];
            } else if (averagePower < -50.0f && self->_speaking) {
                self->_speaking = NO;
                [self sendMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
            }
        }
    }];
}

#pragma mark - Call participants (internal signaling)

- (void)getPeersForCall
{
    _getPeersForCallTask = [[NCAPIController sharedInstance] getPeersForCall:_room.token forAccount:_account withCompletionBlock:^(NSMutableArray *peers, NSError *error, NSInteger statusCode) {
        if (error) {
            return;
        }

        [[WebRTCCommon shared] dispatch:^{
            self->_peersInCall = peers;
        }];
    }];
}

#pragma mark - Audio & Video senders

- (void)createLocalAudioTrack
{
    [[WebRTCCommon shared] assertQueue];

    RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
    RTCAudioSource *source = [peerConnectionFactory audioSourceWithConstraints:nil];
    _localAudioTrack = [peerConnectionFactory audioTrackWithSource:source trackId:kNCAudioTrackId];
    [_localAudioTrack setIsEnabled:!_disableAudioAtStart];
    if ([CallKitManager isCallKitAvailable]) {
        [[CallKitManager sharedInstance] changeAudioMuted:_disableAudioAtStart forCall:_room.token];
    }
    
    [self.delegate callController:self didCreateLocalAudioTrack:_localAudioTrack];
}

- (void)createLocalVideoTrack
{
    [[WebRTCCommon shared] assertQueue];

#if !TARGET_IPHONE_SIMULATOR
    RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
    RTCVideoSource *videoSource = [peerConnectionFactory videoSource];
    RTCVideoCapturer *videoCapturer = [[RTCVideoCapturer alloc] initWithDelegate:videoSource];

    _localVideoTrack = [peerConnectionFactory videoTrackWithSource:videoSource trackId:kNCVideoTrackId];
    [_localVideoTrack setIsEnabled:!_disableVideoAtStart];

    [self.delegate callController:self didCreateLocalVideoTrack:_localVideoTrack];

    self.cameraController = [[NCCameraController alloc] initWithVideoSource:videoSource videoCapturer:videoCapturer];
    self.cameraController.delegate = self;

    [self.delegate callController:self didCreateCameraController:self.cameraController];
#endif
}

- (void)createLocalMedia
{
    [self->_cameraController stopAVCaptureSession];
    
    [[WebRTCCommon shared] dispatch:^{
        self->_localAudioTrack = nil;
        self->_localVideoTrack = nil;

        BOOL hasPublishAudioPermission = ((self->_userPermissions & NCPermissionCanPublishAudio) != 0 || !self->_serverSupportsConversationPermissions);

        if (hasPublishAudioPermission && [self isMicrophoneAccessAvailable]) {
            [self createLocalAudioTrack];
        } else {
            [self.delegate callController:self didCreateLocalAudioTrack:nil];
        }

        BOOL hasPublishVideoPermission = ((self->_userPermissions & NCPermissionCanPublishVideo) != 0 || !self->_serverSupportsConversationPermissions);

        if (!self->_isAudioOnly && hasPublishVideoPermission && [self isCameraAccessAvailable]) {
            [self createLocalVideoTrack];
        } else {
            [self.delegate callController:self didCreateLocalVideoTrack:nil];
        }
    }];
}

#pragma mark - Peer Connection Wrapper

- (NSString *)getPeerKeyWithSessionId:(NSString *)sessionId ofType:(NSString *)roomType forOwnScreenshare:(BOOL)ownScreenshare
{
    NSString *peerKey = [sessionId stringByAppendingString:roomType];

    if (ownScreenshare) {
        // If this is our own screensharing peer, we add "own" to the key, to distinguish our peer
        // to a receiving peer in case we are using internal signaling
        peerKey = [peerKey stringByAppendingString:@"own"];
    }

    return peerKey;
}

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId ofType:(NSString *)roomType
{
    return [self getPeerConnectionWrapperForSessionId:sessionId ofType:roomType forOwnScreenshare:NO];
}

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId ofType:(NSString *)roomType forOwnScreenshare:(BOOL)ownScreenshare
{
    [[WebRTCCommon shared] assertQueue];

    NSString *peerKey = [self getPeerKeyWithSessionId:sessionId ofType:roomType forOwnScreenshare:ownScreenshare];
    NCPeerConnection *peerConnectionWrapper = [_connectionsDict objectForKey:peerKey];

    return peerConnectionWrapper;
}

- (NCPeerConnection *)getOrCreatePeerConnectionWrapperForSessionId:(NSString *)sessionId withSid:(NSString *)sid ofType:(NSString *)roomType
{
    return [self getOrCreatePeerConnectionWrapperForSessionId:sessionId withSid:sid ofType:roomType forOwnScreenshare:NO];
}

- (NCPeerConnection *)getOrCreatePeerConnectionWrapperForSessionId:(NSString *)sessionId withSid:(NSString *)sid ofType:(NSString *)roomType forOwnScreenshare:(BOOL)ownScreenshare
{
    [[WebRTCCommon shared] assertQueue];

    NSString *peerKey = [self getPeerKeyWithSessionId:sessionId ofType:roomType forOwnScreenshare:ownScreenshare];
    NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:sessionId ofType:roomType forOwnScreenshare:ownScreenshare];

    // When using internal signaling, if you and another participant are sharing the screen and you receive a candidate message
    // we can not know whether the message is for the sending or the received screen share only from the "from" field and the type.
    // We need to use the "sid"
    BOOL screensharingPeer = [roomType isEqualToString:kRoomTypeScreen];
    if (screensharingPeer) {
        // We check if the signaling message was send to our own screen peer.
        // If the "sid" doesn't match, we have grabbed the correct peer connection above (if it existed)
        NCPeerConnection *ownScreenPeerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:sessionId ofType:roomType forOwnScreenshare:YES];
        if (ownScreenPeerConnectionWrapper && [ownScreenPeerConnectionWrapper.sid isEqualToString:sid]) {
            peerConnectionWrapper = ownScreenPeerConnectionWrapper;
        }
    }

    if (!peerConnectionWrapper) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        NSArray *iceServers = [_signalingController getIceServers];
        peerConnectionWrapper = [[NCPeerConnection alloc] initWithSessionId:sessionId sid:sid andICEServers:iceServers forAudioOnlyCall:screensharingPeer ? NO : _isAudioOnly];
        peerConnectionWrapper.roomType = roomType;
        peerConnectionWrapper.delegate = self;
        peerConnectionWrapper.isOwnScreensharePeer = ownScreenshare;
        
        // Try to get displayName early
        TalkActor *actor = [self getActorFromSessionId:sessionId];
        if (actor && ![actor.rawDisplayName isEqualToString:@""]) {
            [peerConnectionWrapper setPeerName:actor.displayName];
        }
        
        // Do not add local stream when using a MCU or to screensharing peers
        if (![_externalSignalingController hasMCU]) {
            RTCPeerConnection *peerConnection = [peerConnectionWrapper getPeerConnection];

            if (!screensharingPeer) {
                if (_localAudioTrack) {
                    [peerConnection addTrack:_localAudioTrack streamIds:@[kNCMediaStreamId]];
                }
                if (_localVideoTrack) {
                    [peerConnection addTrack:_localVideoTrack streamIds:@[kNCMediaStreamId]];
                }
            } else if (_localScreenTrack) {
                [peerConnection addTrack:_localScreenTrack streamIds:@[kNCMediaStreamId]];
            }
        }
        
        // Add peer connection to the connections dictionary
        [_connectionsDict setObject:peerConnectionWrapper forKey:peerKey];

        // Notify about the new peer
        if (!screensharingPeer) {
            [self.delegate callController:self peerJoined:peerConnectionWrapper];
        }
    }
    
    return peerConnectionWrapper;
}

- (void)sendMessageToAllOfType:(NSString *)type withPayload:(id)payload
{
    [[WebRTCCommon shared] assertQueue];

    if ([self->_externalSignalingController hasMCU]) {
        [self->_publisherPeerConnection sendDataChannelMessageOfType:type withPayload:payload];
    } else {
        NSArray *connectionWrappers = [self.connectionsDict allValues];
        for (NCPeerConnection *peerConnection in connectionWrappers) {
            [peerConnection sendDataChannelMessageOfType:type withPayload:payload];
        }
    }

    // Send a signaling message only if we are using an external signaling server
    if (!self->_externalSignalingController) {
        return;
    }
    
    for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
        NCSignalingMessage *message = nil;
        NSDictionary *payload = nil;
        NSString *from = [self signalingSessionId];

        if ([type isEqualToString:@"audioOn"]) {
            payload = @{@"name": @"audio"};
            message = [[NCUnmuteMessage alloc] initWithFrom:from to:peer.peerId sid:peer.sid roomType:peer.roomType payload:payload];
        } else if ([type isEqualToString:@"audioOff"]) {
            payload = @{@"name": @"audio"};
            message = [[NCMuteMessage alloc] initWithFrom:from to:peer.peerId sid:peer.sid roomType:peer.roomType payload:payload];
        } else if ([type isEqualToString:@"videoOn"]) {
            payload = @{@"name": @"video"};
            message = [[NCUnmuteMessage alloc] initWithFrom:from to:peer.peerId sid:peer.sid roomType:peer.roomType payload:payload];
        } else if ([type isEqualToString:@"videoOff"]) {
            payload = @{@"name": @"video"};
            message = [[NCMuteMessage alloc] initWithFrom:from to:peer.peerId sid:peer.sid roomType:peer.roomType payload:payload];
        } else if ([type isEqualToString:@"nickChanged"]) {
            payload = @{@"name": _account.userDisplayName};
            message = [[NCNickChangedMessage alloc] initWithFrom:from to:peer.peerId sid:peer.sid roomType:peer.roomType payload:payload];
        }

        if (message) {
            [self->_externalSignalingController sendCallMessage:message];
        }
    }
}

#pragma mark - External signaling support

- (void)createPublisherPeerConnection
{
    [[WebRTCCommon shared] assertQueue];

    if (self->_publisherPeerConnection || (!self->_localAudioTrack && !self->_localVideoTrack)) {
        NSLog(@"Not creating publisher peer connection. Already created or no local media.");
        return;
    }

    [NCUtils log:[NSString stringWithFormat:@"Creating publisher peer connection with sessionId: %@", [self signalingSessionId]]];

    NSArray *iceServers = [self->_signalingController getIceServers];
    self->_publisherPeerConnection = [[NCPeerConnection alloc] initForPublisherWithSessionId:[self signalingSessionId] andICEServers:iceServers forAudioOnlyCall:YES];
    self->_publisherPeerConnection.roomType = kRoomTypeVideo;
    self->_publisherPeerConnection.delegate = self;

    NSString *peerKey = [[self signalingSessionId] stringByAppendingString:kRoomTypeVideo];
    [self->_connectionsDict setObject:self->_publisherPeerConnection forKey:peerKey];

    RTCPeerConnection *peerConnection = [self->_publisherPeerConnection getPeerConnection];

    if (self->_localAudioTrack) {
        [peerConnection addTrack:self->_localAudioTrack streamIds:@[kNCMediaStreamId]];
    }

    if (self->_localVideoTrack) {
        [peerConnection addTrack:self->_localVideoTrack streamIds:@[kNCMediaStreamId]];
    }

    [self->_publisherPeerConnection sendPublisherOffer];
}

- (void)createScreenPublisherPeerConnection
{
    [[WebRTCCommon shared] assertQueue];

    if (self->_screenPublisherPeerConnection || !self->_localScreenTrack) {
        NSLog(@"Not creating publisher peer connection. Already created or no local media.");
        return;
    }

    NSLog(@"Creating publisher peer connection with sessionId: %@", [self signalingSessionId]);

    NSArray *iceServers = [self->_signalingController getIceServers];
    self->_screenPublisherPeerConnection = [[NCPeerConnection alloc] initForPublisherWithSessionId:[self signalingSessionId] andICEServers:iceServers forAudioOnlyCall:YES];
    self->_screenPublisherPeerConnection.roomType = kRoomTypeScreen;
    self->_screenPublisherPeerConnection.isOwnScreensharePeer = YES;
    self->_screenPublisherPeerConnection.delegate = self;

    NSString *peerKey = [self getPeerKeyWithSessionId:[self signalingSessionId] ofType:kRoomTypeScreen forOwnScreenshare:YES];
    [self->_connectionsDict setObject:self->_screenPublisherPeerConnection forKey:peerKey];

    if (self->_localScreenTrack) {
        RTCPeerConnection *peerConnection = [self->_screenPublisherPeerConnection getPeerConnection];
        [peerConnection addTrack:self->_localScreenTrack streamIds:@[kNCMediaStreamId]];
    }

    [self->_screenPublisherPeerConnection sendPublisherOffer];
}

- (void)requestOfferWithRepetitionForSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType
{
    [[WebRTCCommon shared] assertQueue];

    NSNumber *timeout = [NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970] + 60];
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:sessionId forKey:@"sessionId"];
    [userInfo setObject:roomType forKey:@"roomType"];
    [userInfo setValue:timeout forKey:@"timeout"];

    NSTimer *pendingOfferTimer = [NSTimer timerWithTimeInterval:8.0 target:self selector:@selector(requestNewOffer:) userInfo:userInfo repeats:YES];
    NSString *peerKey = [sessionId stringByAppendingString:roomType];
    
    [self->_pendingOffersDict setObject:pendingOfferTimer forKey:peerKey];

    // Request new offer
    [self->_externalSignalingController requestOfferForSessionId:sessionId andRoomType:roomType];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSRunLoop mainRunLoop] addTimer:pendingOfferTimer forMode:NSDefaultRunLoopMode];
    });
}

- (void)requestNewOffer:(NSTimer *)timer
{
    NSString *sessionId = [timer.userInfo objectForKey:@"sessionId"];
    NSString *roomType = [timer.userInfo objectForKey:@"roomType"];
    NSInteger timeout = [[timer.userInfo objectForKey:@"timeout"] integerValue];

    [[WebRTCCommon shared] dispatch:^{
        if ([[NSDate date] timeIntervalSince1970] < timeout) {
            NSLog(@"Re-requesting an offer to session: %@", sessionId);
            [self->_externalSignalingController requestOfferForSessionId:sessionId andRoomType:roomType];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [timer invalidate];
            });
        }
    }];
}

- (void)checkIfPendingOffer:(NCSignalingMessage *)signalingMessage
{
    if (signalingMessage.messageType == kNCSignalingMessageTypeOffer) {
        NSString *peerKey = [signalingMessage.from stringByAppendingString:signalingMessage.roomType];
        NSTimer *pendingRequestTimer = [_pendingOffersDict objectForKey:peerKey];
        
        if (pendingRequestTimer) {
            NSLog(@"Pending requested offer arrived. Removing timer.");

            dispatch_async(dispatch_get_main_queue(), ^{
                [pendingRequestTimer invalidate];
            });
        }
    }
}

#pragma mark - Nick & Media info

- (void)sendNick
{
    NSDictionary *payload = @{
                              @"userid":_account.userId,
                              @"name":_account.userDisplayName
                              };

    [[WebRTCCommon shared] dispatch:^{
        [self sendMessageToAllOfType:@"nickChanged" withPayload:payload];
    }];
}

- (void)sendMediaState
{
    [[WebRTCCommon shared] dispatch:^{
        // Send current audio state
        if (self.isAudioEnabled) {
            NSLog(@"Send audioOn to all");
            [self sendMessageToAllOfType:@"audioOn" withPayload:nil];
        } else {
            NSLog(@"Send audioOff to all");
            [self sendMessageToAllOfType:@"audioOff" withPayload:nil];
        }

        // Send current video state
        if (self.isVideoEnabled) {
            NSLog(@"Send videoOn to all");
            [self sendMessageToAllOfType:@"videoOn" withPayload:nil];
        } else {
            NSLog(@"Send videoOff to all");
            [self sendMessageToAllOfType:@"videoOff" withPayload:nil];
        }
    }];
}

- (void)startSendingCurrentState
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_sendCurrentStateTimer invalidate];
        self->_sendCurrentStateTimer = nil;

        [self sendCurrentStateWithTimer:nil];
    });
}

- (void)stopSendingCurrentState
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_sendCurrentStateTimer invalidate];
        self->_sendCurrentStateTimer = nil;
    });
}

- (void)sendCurrentStateWithTimer:(NSTimer *)timer
{
    __block NSInteger interval = [[timer.userInfo objectForKey:@"interval"] integerValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendNick];
        [self sendMediaState];
        
        if (interval == 0) {
            interval = 1;
        } else {
            interval *= 2;
        }

        if (interval > 16) {
            return;
        }

        NSDictionary *userInfo = @{@"interval" : @(interval)};
        self->_sendCurrentStateTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(sendCurrentStateWithTimer:) userInfo:userInfo repeats:NO];
    });
}

#pragma mark - Control support

- (void)forceMuteOthers
{
    [[WebRTCCommon shared] dispatch:^{
        for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
            NSDictionary *payload = @{@"action": @"forceMute", @"peerId": peer.peerId};

            NCControlMessage *message = [[NCControlMessage alloc] initWithFrom:[self signalingSessionId]
                                                                            to:peer.peerId
                                                                           sid:peer.sid
                                                                      roomType:peer.roomType
                                                                       payload:payload];

            if (self->_externalSignalingController) {
                [self->_externalSignalingController sendCallMessage:message];
            } else {
                [self->_signalingController sendSignalingMessage:message];
            }
        }
    }];
}

#pragma mark - External Signaling Controller Delegate

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedSignalingMessage:(NSDictionary *)signalingMessageDict
{
    //NSLog(@"External signaling message received: %@", signalingMessageDict);

    [[WebRTCCommon shared] dispatch:^{
        NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromExternalSignalingJSONDictionary:signalingMessageDict];
        [self checkIfPendingOffer:signalingMessage];
        [self processSignalingMessage:signalingMessage];
    }];
}

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedParticipantListMessage:(NSDictionary *)participantListMessageDict
{
    //NSLog(@"External participants message received: %@", participantListMessageDict);

    [[WebRTCCommon shared] dispatch:^{
        NSArray *usersInRoom = [participantListMessageDict objectForKey:@"users"];

        // Update for "all" participants
        if ([[participantListMessageDict objectForKey:@"all"] boolValue]) {
            // Check if "incall" key exist
            if ([[participantListMessageDict allKeys] containsObject:@"incall"]) {
                // Clear usersInRoom array if incall=false
                if (![[participantListMessageDict objectForKey:@"incall"] boolValue]) {
                    usersInRoom = @[];
                }
            }
        }

        [self processUsersInRoom:usersInRoom];
    }];
}

- (void)externalSignalingControllerShouldRejoinCall:(NCExternalSignalingController *)externalSignalingController
{
    // Call controller should rejoin the call if it was notifiy with the willRejoin notification first.
    // Also we should check that it has joined the call first with the startCall method.

    [[WebRTCCommon shared] dispatch:^{
        if (self->_preparedForRejoin) {
            self->_preparedForRejoin = NO;

            if (self->_joinedCallOnce) {
                [self shouldRejoinCall];
            } else {
                [self joinCall];
            }
        }
    }];
}

- (void)externalSignalingControllerWillRejoinCall:(NCExternalSignalingController *)externalSignalingController
{
    [[WebRTCCommon shared] dispatch:^{
        [self willRejoinCall];
    }];
}

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController shouldSwitchToCall:(NSString *)roomToken
{
    [self willSwitchToCall:roomToken];
}

#pragma mark - Signaling Controller Delegate

- (void)signalingController:(NCSignalingController *)signalingController didReceiveSignalingMessage:(NSDictionary *)message
{
    [[WebRTCCommon shared] dispatch:^{
        NSString *messageType = [message objectForKey:@"type"];

        if (self->_leavingCall) {
            return;
        }

        if ([messageType isEqualToString:@"usersInRoom"]) {
            [self processUsersInRoom:[message objectForKey:@"data"]];
        } else if ([messageType isEqualToString:@"message"]) {
            NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromJSONString:[message objectForKey:@"data"]];
            [self processSignalingMessage:signalingMessage];
        } else {
            NSLog(@"Uknown message: %@", [message objectForKey:@"data"]);
        }
    }];
}

#pragma mark - NCCamera Controller Delegate

- (void)didDrawFirstFrameOnLocalView {
    [self.delegate callControllerDidDrawFirstLocalFrame:self];
}

#pragma mark - Signaling functions

- (void)processSignalingMessage:(NCSignalingMessage *)signalingMessage
{
    if (!signalingMessage) {
        return;
    }

    [[WebRTCCommon shared] assertQueue];

    switch (signalingMessage.messageType) {
        case kNCSignalingMessageTypeOffer:
        case kNCSignalingMessageTypeAnswer:
        {
            // If we receive an answer to a "screen" type, it can only be our own publishing peer
            BOOL isAnswerToOwnScreenshare = signalingMessage.messageType == kNCSignalingMessageTypeAnswer && [signalingMessage.roomType isEqualToString:kRoomTypeScreen];

            // If there is already a peer connection but a new offer is received with a different sid the existing
            // peer connection is stale, so it needs to be removed and a new one created instead.
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType forOwnScreenshare:isAnswerToOwnScreenshare];
            NSString *peerName;
            if (signalingMessage.messageType == kNCSignalingMessageTypeOffer && peerConnectionWrapper &&
                signalingMessage.sid.length > 0 && ![signalingMessage.sid isEqualToString:peerConnectionWrapper.sid]) {

                // Remember the peerName for the new connectionWrapper
                peerName = peerConnectionWrapper.peerName;
                [self cleanPeerConnectionForSessionId:signalingMessage.from ofType:signalingMessage.roomType forOwnScreenshare:isAnswerToOwnScreenshare];
            }

            peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:signalingMessage.from withSid:signalingMessage.sid ofType:signalingMessage.roomType forOwnScreenshare:isAnswerToOwnScreenshare];
            NCSessionDescriptionMessage *sdpMessage = (NCSessionDescriptionMessage *)signalingMessage;
            RTCSessionDescription *sessionDescription = sdpMessage.sessionDescription;
            [peerConnectionWrapper setRemoteDescription:sessionDescription];

            if (sdpMessage.nick && ![sdpMessage.nick isEqualToString:@""]) {
                [peerConnectionWrapper setPeerName:sdpMessage.nick];
            } else if (peerName) {
                [peerConnectionWrapper setPeerName:peerName];
            }

            break;
        }
        case kNCSignalingMessageTypeCandidate:
        {
            NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:signalingMessage.from withSid:signalingMessage.sid ofType:signalingMessage.roomType];
            NCICECandidateMessage *candidateMessage = (NCICECandidateMessage *)signalingMessage;
            [peerConnectionWrapper addICECandidate:candidateMessage.candidate];
            break;
        }
        case kNCSignalingMessageTypeUnshareScreen:
        {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
            if (peerConnectionWrapper) {
                NSString *peerKey = [self getPeerKeyWithSessionId:peerConnectionWrapper.peerId ofType:kRoomTypeScreen forOwnScreenshare:NO];
                NCPeerConnection *screenPeerConnection = [self->_connectionsDict objectForKey:peerKey];
                if (screenPeerConnection) {
                    [screenPeerConnection close];
                    [self->_connectionsDict removeObjectForKey:peerKey];
                }
                [self.delegate callController:self didReceiveUnshareScreenFromPeer:peerConnectionWrapper];
            }
            break;
        }
        case kNCSignalingMessageTypeControl:
        {
            NSString *action = [signalingMessage.payload objectForKey:@"action"];
            if ([action isEqualToString:@"forceMute"]) {
                NSString *peerId = [signalingMessage.payload objectForKey:@"peerId"];
                [self.delegate callController:self didReceiveForceMuteActionForPeerId:peerId];
            }
            break;
        }
        case kNCSignalingMessageTypeMute:
        case kNCSignalingMessageTypeUnmute:
        {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
            if (peerConnectionWrapper) {
                NSString *name = [signalingMessage.payload objectForKey:@"name"];
                if ([name isEqualToString:@"audio"]) {
                    NSString *messageType = (signalingMessage.messageType == kNCSignalingMessageTypeMute) ? @"audioOff" : @"audioOn";
                    [peerConnectionWrapper setStatusForDataChannelMessageType:messageType withPayload:nil];
                } else if ([name isEqualToString:@"video"]) {
                    NSString *messageType = (signalingMessage.messageType == kNCSignalingMessageTypeMute) ? @"videoOff" : @"videoOn";
                    [peerConnectionWrapper setStatusForDataChannelMessageType:messageType withPayload:nil];
                }
            }
            break;
        }
        case kNCSignalingMessageTypeNickChanged:
        {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
            if (peerConnectionWrapper) {
                NSString *name = [signalingMessage.payload objectForKey:@"name"];
                if (name.length > 0) {
                    [peerConnectionWrapper setStatusForDataChannelMessageType:@"nickChanged" withPayload:name];
                }
            }
            break;
        }
        case kNCSignalingMessageTypeRaiseHand:
        {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
            if (peerConnectionWrapper) {
                BOOL raised = [[signalingMessage.payload objectForKey:@"state"] boolValue];
                [peerConnectionWrapper setStatusForDataChannelMessageType:@"raiseHand" withPayload:@(raised)];
            }
            break;
        }
        case kNCSignalingMessageTypeRecording:
        {
            NCRecordingMessage *recordingMessage = (NCRecordingMessage *)signalingMessage;
            self->_room.callRecording = recordingMessage.status;
            [self.delegate callControllerDidChangeRecording:self];

            break;
        }
        case kNCSignalingMessageTypeReaction:
        {
            NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
            if (peerConnectionWrapper) {
                NSString *reaction = [signalingMessage.payload objectForKey:@"reaction"];
                [self.delegate callController:self didReceiveReaction:reaction fromPeer:peerConnectionWrapper];
            }
            break;
        }
        case kNCSignalingMessageTypeUnknown:
            NSLog(@"Received an unknown signaling message: %@", signalingMessage);
            break;
    }
}

- (void)processUsersInRoom:(NSArray *)users
{
    [[WebRTCCommon shared] assertQueue];

    _usersInRoom = users;
    
    NSInteger previousUserInCall = _userInCall;
    NSMutableArray *newSessions = [self getInCallSessionsFromUsersInRoom:users];
    
    if (_leavingCall) {
        return;
    }
    
    // Detect if user should rejoin call (internal signaling)
    if (!_userInCall && _shouldRejoinCallUsingInternalSignaling) {
        _shouldRejoinCallUsingInternalSignaling = NO;
        [self shouldRejoinCall];
    }
    
    if (!previousUserInCall) {
        // Do nothing if app user is stil not in the call
        if (!_userInCall) {
            return;
        }

        // Create publisher peer connection
        if ([_externalSignalingController hasMCU]) {
            [self createPublisherPeerConnection];
        }
    }
    
    NSMutableArray *oldSessions = [NSMutableArray arrayWithArray:_sessionsInCall];
    
    //Save current sessions in call
    _sessionsInCall = [NSArray arrayWithArray:newSessions];
    
    // Calculate sessions that left the call
    NSMutableArray *leftSessions = [NSMutableArray arrayWithArray:oldSessions];
    [leftSessions removeObjectsInArray:newSessions];
    
    // Calculate sessions that join the call
    [newSessions removeObjectsInArray:oldSessions];
    
    if (newSessions.count > 0 && !_externalSignalingController) {
        [self getPeersForCall];
    }
    
    if (_serverSupportsConversationPermissions) {
        [self checkUserPermissionsChange];
    }
    
    // Create new peer connections for new sessions in call
    for (NSString *sessionId in newSessions) {
        NSString *peerKey = [sessionId stringByAppendingString:kRoomTypeVideo];
        if (![_connectionsDict objectForKey:peerKey] && ![[self signalingSessionId] isEqualToString:sessionId]) {
            // Always create a peer connection, so the peer is added to the call view.
            // When using a MCU we request an offer, but in case there are no streams published, we won't get an offer.
            // When using internal signaling if we and the other participant are not publishing any stream,
            // we won't receive or send any offer.
            NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:sessionId withSid:nil ofType:kRoomTypeVideo];
            if ([_externalSignalingController hasMCU]) {
                // Only request offer if user is sharing audio or video streams
                if ([self userHasStreams:sessionId]) {
                    NSLog(@"Requesting offer to the MCU for session: %@", sessionId);
                    [self requestOfferWithRepetitionForSessionId:sessionId andRoomType:kRoomTypeVideo];
                } else {
                    // Set peer as dummyPeer if it has no streams
                    peerConnectionWrapper.isDummyPeer = YES;
                }
            } else {
                NSComparisonResult result = [sessionId compare:[self signalingSessionId]];
                if (result == NSOrderedAscending) {
                    NSLog(@"Creating offer...");
                    [peerConnectionWrapper sendOffer];
                } else {
                    NSLog(@"Waiting for offer...");
                }

                if (self.screensharingActive) {
                    // If screensharing is active and we are using internal signaling, we need to send a offer to the newly joined user
                    [self sendScreensharingOfferToSessionId:peerConnectionWrapper.peerId];
                }
            }
        }
    }
    
    // Close old peer connections for sessions that left the call
    for (NSString *sessionId in leftSessions) {
        // Hang up call if user sessionId is no longer in the call
        // Could be because a moderator "ended the call for everyone"
        if ([[self signalingSessionId] isEqualToString:sessionId]) {
            NSLog(@"User sessionId is no longer in the call -> hang up call");
            [self.delegate callControllerWantsToHangUpCall:self];

            return;
        }

        // Remove all peer connections for that user
        [self cleanAllPeerConnectionsForSessionId:sessionId];
    }
}

- (BOOL)userHasStreams:(NSString *)sessionId
{
    for (NSMutableDictionary *user in _usersInRoom) {
        NSString *userSession = [user objectForKey:@"sessionId"];
        if ([userSession isEqualToString:sessionId]) {
            NSInteger userCallFlags = [[user objectForKey:@"inCall"] integerValue];
            NSInteger requiredFlags = CallFlagWithAudio | CallFlagWithVideo;
            return (userCallFlags & requiredFlags) != 0;
        }
    }
    
    return NO;
}

- (void)checkUserPermissionsChange
{
    for (NSMutableDictionary *user in _usersInRoom) {
        NSString *userSession = [user objectForKey:@"sessionId"];
        id userPermissionValue = [user objectForKey:@"participantPermissions"];
        if ([userSession isEqualToString:[self signalingSessionId]] && [userPermissionValue isKindOfClass:[NSNumber class]]) {
            NSInteger userPermissions = [userPermissionValue integerValue];
            NSInteger changedPermissions = userPermissions ^ _userPermissions;
            if ((changedPermissions & NCPermissionCanPublishAudio) || (changedPermissions & NCPermissionCanPublishVideo)) {
                [NCUtils log:@"User permissions changed"];
                _userPermissions = userPermissions;
                [self.delegate callController:self userPermissionsChanged:_userPermissions];
                [self forceReconnect];
            }
        }
    }
}

- (NSMutableArray *)getInCallSessionsFromUsersInRoom:(NSArray *)users
{
    NSMutableArray *sessions = [[NSMutableArray alloc] init];
    for (NSMutableDictionary *user in users) {
        NSString *sessionId = [user objectForKey:@"sessionId"];
        NSInteger inCall = [[user objectForKey:@"inCall"] integerValue];
        BOOL internalClient = [[user objectForKey:@"internal"] boolValue];

        // Set inCall flag for app user
        if ([sessionId isEqualToString:[self signalingSessionId]]) {
            _userInCall = inCall;
        }

        // Add session if inCall and if it's not an internal client
        if (inCall && !internalClient) {
            [sessions addObject:sessionId];
        }
    }
    //NSLog(@"InCall sessions: %@", sessions);
    return sessions;
}

- (TalkActor * _Nullable)getActorFromSessionId:(NSString *)sessionId
{
    [[WebRTCCommon shared] assertQueue];

    if (_externalSignalingController) {
        return [_externalSignalingController getParticipantFromSessionId:sessionId].actor;
    }

    NSInteger callAPIVersion = [[NCAPIController sharedInstance] callAPIVersionForAccount:_account];

    for (NSMutableDictionary *user in _peersInCall) {
        NSString *userSessionId = [user objectForKey:@"sessionId"];
        if ([userSessionId isEqualToString:sessionId]) {
            TalkActor *actor = [[TalkActor alloc] initWithActorId:[user objectForKey:@"userId"] actorType:@"users" actorDisplayName:[user objectForKey:@"displayName"]];

            if (callAPIVersion >= APIv3) {
                [actor setId:[user objectForKey:@"actorId"]];
                [actor setType:[user objectForKey:@"actorType"]];
            }

            return actor;
        }
    }

    return nil;
}

#pragma mark - NCPeerConnectionDelegate
// Delegates from NCPeerConnection are already dispatched to the webrtc worker queue

- (void)peerConnection:(NCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    if (!peerConnection.isMCUPublisherPeer) {
        [self.delegate callController:self didAddStream:stream ofPeer:peerConnection];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    if (!peerConnection.isMCUPublisherPeer) {
        [self.delegate callController:self didRemoveStream:stream ofPeer:peerConnection];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    if (newState == RTCIceConnectionStateFailed) {
        if ([peerConnection.roomType isEqualToString:kRoomTypeScreen]) {
            [self stopScreenshare];
            return;
        }

        // If publisher peer failed then reconnect
        if (peerConnection.isMCUPublisherPeer) {
            [NCUtils log:@"Publisher peer connection failed"];
            [self forceReconnect];
        // If another peer failed using MCU then request a new offer
        } else if ([_externalSignalingController hasMCU]) {
            NSString *sessionId = [peerConnection.peerId copy];
            NSString *roomType = [peerConnection.roomType copy];
            // Close failed peer connection
            [self cleanPeerConnectionForSessionId:sessionId ofType:roomType forOwnScreenshare:NO];
            // Request new offer
            [self requestOfferWithRepetitionForSessionId:sessionId andRoomType:roomType];
        }
    }

    if (newState == RTCIceConnectionStateConnected) {
        [self startSendingCurrentState];

        if (self.externalSignalingController && peerConnection.isMCUPublisherPeer) {
            [NCUtils log:@"Publisher peer changed to connected"];
        }

        if (self.externalSignalingController && self.screensharingActive) {
            if (peerConnection.isMCUPublisherPeer) {
                // This is our screensharing publisher peer which connected just now, so ask everyone to request our peer now
                for (NCPeerConnection *peer in [self->_connectionsDict allValues]) {
                    if ([peer.peerId isEqualToString:_screenPublisherPeerConnection.peerId]) {
                        continue;
                    }

                    [_externalSignalingController sendSendOfferMessageWithSessionId:peer.peerId andRoomType:kRoomTypeScreen];
                }
            } else {
                // Another new peer joined, tell the peer that we are screensharing and it needs to request the screen peer
                [self.externalSignalingController sendSendOfferMessageWithSessionId:peerConnection.peerId andRoomType:kRoomTypeScreen];
            }
        }
    }

    if (!peerConnection.isMCUPublisherPeer) {
        [self.delegate callController:self iceStatusChanged:newState ofPeer:peerConnection];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NCICECandidateMessage *message = [[NCICECandidateMessage alloc] initWithCandidate:candidate
                                                                                 from:[self signalingSessionId]
                                                                                   to:peerConnection.peerId
                                                                                  sid:peerConnection.sid
                                                                             roomType:peerConnection.roomType
                                                                          broadcaster:peerConnection.isOwnScreensharePeer ? [self signalingSessionId] : nil];
    
    if (_externalSignalingController) {
        [_externalSignalingController sendCallMessage:message];
    } else {
        [_signalingController sendSignalingMessage:message];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection needsToSendSessionDescription:(RTCSessionDescription *)sessionDescription
{
    NCSessionDescriptionMessage *message = [[NCSessionDescriptionMessage alloc]
                                            initWithSessionDescription:sessionDescription
                                            from:[self signalingSessionId]
                                            to:peerConnection.peerId
                                            sid:peerConnection.sid
                                            roomType:peerConnection.roomType
                                            broadcaster:peerConnection.isOwnScreensharePeer ? [self signalingSessionId] : nil
                                            nick:_userDisplayName];
    
    if (_externalSignalingController) {
        [_externalSignalingController sendCallMessage:message];
    } else {
        [_signalingController sendSignalingMessage:message];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didReceiveStatusDataChannelMessage:(NSString *)type
{
    [self.delegate callController:self didReceiveDataChannelMessage:type fromPeer:peerConnection];
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didReceivePeerNick:(NSString *)nick
{
    [self.delegate callController:self didReceiveNick:nick fromPeer:peerConnection];
}


@end
