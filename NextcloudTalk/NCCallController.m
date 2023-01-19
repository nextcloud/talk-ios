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

#import "NCCallController.h"

#import <WebRTC/RTCConfiguration.h>
#import <WebRTC/RTCDataChannelConfiguration.h>
#import <WebRTC/RTCMediaConstraints.h>
#import <WebRTC/RTCMediaStream.h>
#import <WebRTC/RTCPeerConnectionFactory.h>
#import <WebRTC/RTCAudioTrack.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCVideoCapturer.h>
#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>
#import <WebRTC/RTCDefaultVideoDecoderFactory.h>

#import "ARDCaptureController.h"

#import "CallConstants.h"
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCSignalingController.h"
#import "NCExternalSignalingController.h"

#import "NextcloudTalk-Swift.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface NCCallController () <NCPeerConnectionDelegate, NCSignalingControllerObserver, NCExternalSignalingControllerDelegate>

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
@property (nonatomic, strong) NSTimer *sendNickTimer;
@property (nonatomic, strong) NSArray *usersInRoom;
@property (nonatomic, strong) NSArray *sessionsInCall;
@property (nonatomic, strong) NSArray *peersInCall;
@property (nonatomic, strong) NCPeerConnection *publisherPeerConnection;
@property (nonatomic, strong) NSMutableDictionary *connectionsDict;
@property (nonatomic, strong) NSMutableDictionary *pendingOffersDict;
@property (nonatomic, strong) RTCAudioTrack *localAudioTrack;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property (nonatomic, strong) RTCCameraVideoCapturer *localVideoCapturer;
@property (nonatomic, strong) ARDCaptureController *localVideoCaptureController;
@property (nonatomic, strong) NCSignalingController *signalingController;
@property (nonatomic, strong) NCExternalSignalingController *externalSignalingController;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NSURLSessionTask *joinCallTask;
@property (nonatomic, strong) NSURLSessionTask *getPeersForCallTask;

@end

@implementation NCCallController

- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId andVoiceChatMode:(BOOL)voiceChatMode
{
    self = [super init];
    
    if (self) {
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
        _externalSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:_account.accountId];
        _externalSignalingController.delegate = self;
        
        // 'conversation-permissions' capability was not added in Talk 13 release, so we check for 'direct-mention-flag' capability
        // as a workaround.
        _serverSupportsConversationPermissions =
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityConversationPermissions forAccountId:_account.accountId] ||
        [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDirectMentionFlag forAccountId:_account.accountId];
        
        if (audioOnly || voiceChatMode) {
            [[NCAudioController sharedInstance] setAudioSessionToVoiceChatMode];
        } else {
            [[NCAudioController sharedInstance] setAudioSessionToVideoChatMode];
        }
        
        [self initRecorder];
    }
    
    return self;
}

- (void)startCall
{
    [self createLocalMedia];
    [self joinCall];
}

- (NSString *)signalingSessionId
{
    if ([_externalSignalingController isEnabled]) {
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
    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token withCallFlags:[self joinCallFlags] silently:_silentCall forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (!error) {
            [self.delegate callControllerDidJoinCall:self];
            [self getPeersForCall];
            [self startMonitoringMicrophoneAudioLevel];
            if ([self->_externalSignalingController isEnabled]) {
                if ([self->_externalSignalingController hasMCU]) {
                    [self createPublisherPeerConnection];
                }
            } else {
                [self->_signalingController startPullingSignalingMessages];
            }
            self->_joinedCallOnce = YES;
            self->_joinCallAttempts = 0;
        } else {
            if (self->_joinCallAttempts < 3) {
                NSLog(@"Could not join call, retrying. %ld", (long)self->_joinCallAttempts);
                self->_joinCallAttempts += 1;
                [self joinCall];
                return;
            } 
            [self.delegate callControllerDidFailedJoiningCall:self statusCode:@(statusCode) errorReason:[self getJoinCallErrorReason:statusCode]];
            NSLog(@"Could not join call. Error: %@", error.description);
        }
    }];
}

- (NSString *)getJoinCallErrorReason:(NSInteger)statusCode
{
    NSString *errorReason = NSLocalizedString(@"Unknown error occurred", nil);
    
    switch (statusCode) {
        case 0:
            errorReason = NSLocalizedString(@"No response from server", nil);
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
    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token withCallFlags:[self joinCallFlags] silently:_silentCall forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
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
            [self.delegate callControllerDidFailedJoiningCall:self statusCode:@(statusCode) errorReason:[self getJoinCallErrorReason:statusCode]];
            NSLog(@"Could not rejoin call. Error: %@", error.description);
        }
    }];
}

- (void)willRejoinCall
{
    NSLog(@"willRejoinCall");
    _userInCall = 0;
    [self cleanCurrentPeerConnections];
    [self.delegate callControllerIsReconnectingCall:self];
    _preparedForRejoin = YES;
}


- (void)forceReconnect
{
    NSLog(@"forceReconnect");
    _userInCall = 0;
    [self cleanCurrentPeerConnections];
    [self.delegate callControllerIsReconnectingCall:self];
    
    // Remember current audio and video status before rejoin the call
    _disableAudioAtStart = ![self isAudioEnabled];
    _disableVideoAtStart = ![self isVideoEnabled];
    
    if ([_externalSignalingController isEnabled]) {
        [_externalSignalingController forceReconnect];
    } else {
        [self rejoinCallUsingInternalSignaling];
    }
}

- (void)rejoinCallUsingInternalSignaling
{
    [[NCAPIController sharedInstance] leaveCall:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            self->_shouldRejoinCallUsingInternalSignaling = YES;
        }
    }];
}

- (void)leaveCall
{
    [self setLeavingCall:YES];
    [self stopSendingNick];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _externalSignalingController.delegate = nil;
    
    [self cleanCurrentPeerConnections];
    
    [_localVideoCapturer stopCapture];
    _localVideoCapturer = nil;
    _localAudioTrack = nil;
    _localVideoTrack = nil;
    _connectionsDict = nil;
    
    [self stopMonitoringMicrophoneAudioLevel];
    [_signalingController stopAllRequests];
    
    if (_userInCall) {
        [_getPeersForCallTask cancel];
        _getPeersForCallTask = nil;
        
        [[NCAPIController sharedInstance] leaveCall:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
            [self.delegate callControllerDidEndCall:self];
            if (error) {
                NSLog(@"Could not leave call. Error: %@", error.description);
            }
        }];
    } else {
        [_joinCallTask cancel];
        _joinCallTask = nil;
        [self.delegate callControllerDidEndCall:self];
    }
    
    [[NCAudioController sharedInstance] disableAudioSession];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"NCCallController dealloc");
}

- (BOOL)isVideoEnabled
{
    return _localVideoTrack ? _localVideoTrack.isEnabled : NO;
}

- (BOOL)isAudioEnabled
{
    return _localAudioTrack ? _localAudioTrack.isEnabled : NO;
}

- (void)switchCamera
{
    [_localVideoCaptureController switchCamera];
}

- (void)enableVideo:(BOOL)enable
{
    if (enable) {
        [_localVideoCaptureController startCapture];
    } else {
        [_localVideoCaptureController stopCapture];
    }
    
    [_localVideoTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"videoOn" : @"videoOff" withPayload:nil];
}

- (void)enableAudio:(BOOL)enable
{
    [_localAudioTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"audioOn" : @"audioOff" withPayload:nil];
    if (!enable) {
        _speaking = NO;
        [self sendDataChannelMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
    }
}

- (void)raiseHand:(BOOL)raised
{
    NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970] * 1000;

    NSDictionary *payload = @{
        @"state": @(raised),
        @"timestamp": [NSString stringWithFormat:@"%.0f", timeStamp]
    };

    for (NCPeerConnection *peer in [_connectionsDict allValues]) {
        NCRaiseHandMessage *message = [[NCRaiseHandMessage alloc] initWithFrom:[self signalingSessionId]
                                                                        sendTo:peer.peerId
                                                                   withPayload:payload
                                                                   forRoomType:peer.roomType];

        if ([_externalSignalingController isEnabled]) {
            [_externalSignalingController sendCallMessage:message];
        } else {
            [_signalingController sendSignalingMessage:message];
        }
    }
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

#pragma mark - Call controller

- (void)cleanCurrentPeerConnections
{
    for (NCPeerConnection *peerConnectionWrapper in [_connectionsDict allValues]) {
        if (!peerConnectionWrapper.isMCUPublisherPeer) {
            [self.delegate callController:self peerLeft:peerConnectionWrapper];
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
}

- (void)cleanPeerConnectionForSessionId:(NSString *)sessionId ofType:(NSString *)roomType
{
    NSString *peerKey = [sessionId stringByAppendingString:roomType];
    NCPeerConnection *removedPeerConnection = [_connectionsDict objectForKey:peerKey];
    if (removedPeerConnection) {
        if ([roomType isEqualToString:kRoomTypeVideo]) {
            NSLog(@"Removing peer from call: %@", sessionId);
            [self.delegate callController:self peerLeft:removedPeerConnection];
        } else if ([roomType isEqualToString:kRoomTypeScreen]) {
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
    [self cleanPeerConnectionForSessionId:sessionId ofType:kRoomTypeVideo];
    [self cleanPeerConnectionForSessionId:sessionId ofType:kRoomTypeScreen];
    
    // Invalidate possible request timers
    NSString *peerVideoKey = [sessionId stringByAppendingString:kRoomTypeVideo];
    NSTimer *pendingVideoRequestTimer = [_pendingOffersDict objectForKey:peerVideoKey];
    if (pendingVideoRequestTimer) {
        [pendingVideoRequestTimer invalidate];
    }
    NSString *peerScreenKey = [sessionId stringByAppendingString:kRoomTypeVideo];
    NSTimer *pendingScreenRequestTimer = [_pendingOffersDict objectForKey:peerScreenKey];
    if (pendingScreenRequestTimer) {
        [pendingScreenRequestTimer invalidate];
    }
}

#pragma mark - Microphone audio level

- (void)startMonitoringMicrophoneAudioLevel
{
    _micAudioLevelTimer = [NSTimer scheduledTimerWithTimeInterval:1.0  target:self selector:@selector(checkMicAudioLevel) userInfo:nil repeats:YES];
}

- (void)stopMonitoringMicrophoneAudioLevel
{
    [_micAudioLevelTimer invalidate];
    _micAudioLevelTimer = nil;
    [_recorder stop];
    _recorder = nil;
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
    if ([self isAudioEnabled]) {
        [_recorder updateMeters];
        float averagePower = [_recorder averagePowerForChannel:0];
        if (averagePower >= -50.0f && !_speaking) {
            _speaking = YES;
            [self sendDataChannelMessageToAllOfType:@"speaking" withPayload:nil];
        } else if (averagePower < -50.0f && _speaking) {
            _speaking = NO;
            [self sendDataChannelMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
        }
    }
}

#pragma mark - Call participants

- (void)getPeersForCall
{
    _getPeersForCallTask = [[NCAPIController sharedInstance] getPeersForCall:_room.token forAccount:_account withCompletionBlock:^(NSMutableArray *peers, NSError *error) {
        if (!error) {
            self->_peersInCall = peers;
        }
    }];
}

#pragma mark - Audio & Video senders

- (void)createLocalAudioTrack
{
    RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
    RTCAudioSource *source = [peerConnectionFactory audioSourceWithConstraints:nil];
    _localAudioTrack = [peerConnectionFactory audioTrackWithSource:source trackId:kNCAudioTrackId];
    [_localAudioTrack setIsEnabled:!_disableAudioAtStart];
    
    [self.delegate callController:self didCreateLocalAudioTrack:_localAudioTrack];
}

- (void)createLocalVideoTrack
{
#if !TARGET_IPHONE_SIMULATOR
    RTCPeerConnectionFactory *peerConnectionFactory = [WebRTCCommon shared].peerConnectionFactory;
    RTCVideoSource *source = [peerConnectionFactory videoSource];
    _localVideoCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    _localVideoCaptureController = [[ARDCaptureController alloc] initWithCapturer:_localVideoCapturer settings:[[NCSettingsController sharedInstance] videoSettingsModel]];
    [_localVideoCaptureController startCapture];
    
    [self.delegate callController:self didCreateLocalVideoCapturer:_localVideoCapturer];
    
    _localVideoTrack = [peerConnectionFactory videoTrackWithSource:source trackId:kNCVideoTrackId];
    [_localVideoTrack setIsEnabled:!_disableVideoAtStart];
    
    [self.delegate callController:self didCreateLocalVideoTrack:_localVideoTrack];
#endif
}

- (void)createLocalMedia
{
    _localAudioTrack = nil;
    _localVideoTrack = nil;
    [_localVideoCapturer stopCapture];
    _localVideoCapturer = nil;
    
    if ((_userPermissions & NCPermissionCanPublishAudio) != 0 || !_serverSupportsConversationPermissions) {
        [self createLocalAudioTrack];
    } else {
        [self.delegate callController:self didCreateLocalAudioTrack:nil];
    }
    
    if (!_isAudioOnly && ((_userPermissions & NCPermissionCanPublishVideo) != 0 || !_serverSupportsConversationPermissions)) {
        [self createLocalVideoTrack];
    } else {
        [self.delegate callController:self didCreateLocalVideoTrack:nil];
    }
}

#pragma mark - Peer Connection Wrapper

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId ofType:(NSString *)roomType
{
    NSString *peerKey = [sessionId stringByAppendingString:roomType];
    NCPeerConnection *peerConnectionWrapper = [_connectionsDict objectForKey:peerKey];
    
    return peerConnectionWrapper;
}

- (NCPeerConnection *)getOrCreatePeerConnectionWrapperForSessionId:(NSString *)sessionId ofType:(NSString *)roomType
{
    NSString *peerKey = [sessionId stringByAppendingString:roomType];
    NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:sessionId ofType:roomType];
    
    if (!peerConnectionWrapper) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        NSArray *iceServers = [_signalingController getIceServers];
        BOOL screensharingPeer = [roomType isEqualToString:kRoomTypeScreen];
        peerConnectionWrapper = [[NCPeerConnection alloc] initWithSessionId:sessionId andICEServers:iceServers forAudioOnlyCall:screensharingPeer ? NO : _isAudioOnly];
        peerConnectionWrapper.roomType = roomType;
        peerConnectionWrapper.delegate = self;
        
        // Try to get displayName early
        NSString *displayName = [self getDisplayNameFromSessionId:sessionId];
        if (displayName) {
            [peerConnectionWrapper setPeerName:displayName];
        }
        
        // Do not add local stream when using a MCU or to screensharing peers
        if (![_externalSignalingController hasMCU] || !screensharingPeer) {
            if (_localAudioTrack) {
                [peerConnectionWrapper.peerConnection addTrack:_localAudioTrack streamIds:@[kNCMediaStreamId]];
            }
            if (_localVideoTrack) {
                [peerConnectionWrapper.peerConnection addTrack:_localVideoTrack streamIds:@[kNCMediaStreamId]];
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

- (NCPeerConnection *)peerConnectionWrapperForConnection:(RTCPeerConnection *)connection
{
    NCPeerConnection *peerConnectionWrapper = nil;
    NSArray *connectionWrappers = [self.connectionsDict allValues];
    
    for (NCPeerConnection *wrapper in connectionWrappers) {
        if ([wrapper.peerConnection isEqual:connection]) {
            peerConnectionWrapper = wrapper;
            break;
        }
    }
    
    return peerConnectionWrapper;
}

- (void)sendDataChannelMessageToAllOfType:(NSString *)type withPayload:(id)payload
{
    if ([_externalSignalingController hasMCU]) {
        [_publisherPeerConnection sendDataChannelMessageOfType:type withPayload:payload];
    } else {
        NSArray *connectionWrappers = [self.connectionsDict allValues];
        for (NCPeerConnection *peerConnection in connectionWrappers) {
            [peerConnection sendDataChannelMessageOfType:type withPayload:payload];
        }
    }
}

#pragma mark - External signaling support

- (void)createPublisherPeerConnection
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_publisherPeerConnection || (!self->_localAudioTrack && !self->_localVideoTrack)) {
            NSLog(@"Not creating publisher peer connection. Already created or no local media.");
            return;
        }
        
        NSLog(@"Creating publisher peer connection with sessionId: %@", [self signalingSessionId]);
        
        NSArray *iceServers = [self->_signalingController getIceServers];
        self->_publisherPeerConnection = [[NCPeerConnection alloc] initForPublisherWithSessionId:[self signalingSessionId] andICEServers:iceServers forAudioOnlyCall:YES];
        self->_publisherPeerConnection.roomType = kRoomTypeVideo;
        self->_publisherPeerConnection.delegate = self;
        NSString *peerKey = [[self signalingSessionId] stringByAppendingString:kRoomTypeVideo];
        [self->_connectionsDict setObject:self->_publisherPeerConnection forKey:peerKey];
        if (self->_localAudioTrack) {
            [self->_publisherPeerConnection.peerConnection addTrack:self->_localAudioTrack streamIds:@[kNCMediaStreamId]];
        }
        if (self->_localVideoTrack) {
            [self->_publisherPeerConnection.peerConnection addTrack:self->_localVideoTrack streamIds:@[kNCMediaStreamId]];
        }
        [self->_publisherPeerConnection sendPublisherOffer];
    });
}

- (void)sendNick
{
    NSDictionary *payload = @{
                              @"userid":_account.userId,
                              @"name":_account.userDisplayName
                              };
    [self sendDataChannelMessageToAllOfType:@"nickChanged" withPayload:payload];
}

- (void)startSendingNick
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_sendNickTimer invalidate];
        self->_sendNickTimer = nil;
        self->_sendNickTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(sendNick) userInfo:nil repeats:YES];
    });
}

- (void)stopSendingNick
{
    [_sendNickTimer invalidate];
    _sendNickTimer = nil;
}

- (void)requestNewOffer:(NSTimer *)timer
{
    NSString *sessionId = [timer.userInfo objectForKey:@"sessionId"];
    NSString *roomType = [timer.userInfo objectForKey:@"roomType"];
    NSInteger timeout = [[timer.userInfo objectForKey:@"timeout"] integerValue];
    
    if ([[NSDate date] timeIntervalSince1970] < timeout) {
        [_externalSignalingController requestOfferForSessionId:sessionId andRoomType:roomType];
    } else {
        [timer invalidate];
    }
}

- (void)checkIfPendingOffer:(NCSignalingMessage *)signalingMessage
{
    if (signalingMessage.messageType == kNCSignalingMessageTypeOffer) {
        NSString *peerKey = [signalingMessage.from stringByAppendingString:signalingMessage.roomType];
        NSTimer *pendingRequestTimer = [_pendingOffersDict objectForKey:peerKey];
        
        if (pendingRequestTimer) {
            NSLog(@"Pending requested offer arrived. Removing timer.");
            [pendingRequestTimer invalidate];
        }
    }
}

#pragma mark - External Signaling Controller Delegate

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedSignalingMessage:(NSDictionary *)signalingMessageDict
{
    //NSLog(@"External signaling message received: %@", signalingMessageDict);
    
    NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromExternalSignalingJSONDictionary:signalingMessageDict];
    [self checkIfPendingOffer:signalingMessage];
    [self processSignalingMessage:signalingMessage];
}

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedParticipantListMessage:(NSDictionary *)participantListMessageDict
{
    //NSLog(@"External participants message received: %@", participantListMessageDict);
    
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
}

- (void)externalSignalingControllerShouldRejoinCall:(NCExternalSignalingController *)externalSignalingController
{
    // Call controller should rejoin the call if it was notifiy with the willRejoin notification first.
    // Also we should check that it has joined the call first with the startCall method.
    if (_preparedForRejoin && _joinedCallOnce) {
        _preparedForRejoin = NO;
        [self shouldRejoinCall];
    }
}

- (void)externalSignalingControllerWillRejoinCall:(NCExternalSignalingController *)externalSignalingController
{
    [self willRejoinCall];
}

#pragma mark - Signaling Controller Delegate

- (void)signalingController:(NCSignalingController *)signalingController didReceiveSignalingMessage:(NSDictionary *)message
{
    NSString *messageType = [message objectForKey:@"type"];
    
    if (_leavingCall) {return;}
    
    if ([messageType isEqualToString:@"usersInRoom"]) {
        [self processUsersInRoom:[message objectForKey:@"data"]];
    } else if ([messageType isEqualToString:@"message"]) {
        NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromJSONString:[message objectForKey:@"data"]];
        [self processSignalingMessage:signalingMessage];
    } else {
        NSLog(@"Uknown message: %@", [message objectForKey:@"data"]);
    }
}

#pragma mark - Signaling functions

- (void)processSignalingMessage:(NCSignalingMessage *)signalingMessage
{
    if (signalingMessage) {
        switch (signalingMessage.messageType) {
            case kNCSignalingMessageTypeOffer:
            case kNCSignalingMessageTypeAnswer:
            {
                NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                NCSessionDescriptionMessage *sdpMessage = (NCSessionDescriptionMessage *)signalingMessage;
                RTCSessionDescription *sessionDescription = sdpMessage.sessionDescription;
                [peerConnectionWrapper setPeerName:sdpMessage.nick];
                [peerConnectionWrapper setRemoteDescription:sessionDescription];
                break;
            }
            case kNCSignalingMessageTypeCandidate:
            {
                NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                NCICECandidateMessage *candidateMessage = (NCICECandidateMessage *)signalingMessage;
                [peerConnectionWrapper addICECandidate:candidateMessage.candidate];
                break;
            }
            case kNCSignalingMessageTypeUnshareScreen:
            {
                NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                if (peerConnectionWrapper) {
                    NSString *peerKey = [peerConnectionWrapper.peerId stringByAppendingString:kRoomTypeScreen];
                    NCPeerConnection *screenPeerConnection = [_connectionsDict objectForKey:peerKey];
                    if (screenPeerConnection) {
                        [screenPeerConnection close];
                        [_connectionsDict removeObjectForKey:peerKey];
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
            case kNCSignalingMessageTypeUnknown:
                NSLog(@"Received an unknown signaling message: %@", signalingMessage);
                break;
        }
    }
}

- (void)processUsersInRoom:(NSArray *)users
{
    _usersInRoom = users;
    
    NSInteger previousUserInCall = _userInCall;
    NSMutableArray *newSessions = [self getInCallSessionsFromUsersInRoom:users];
    
    if (_leavingCall) {return;}
    
    // Detect if user should rejoin call (internal signaling)
    if (!_userInCall && _shouldRejoinCallUsingInternalSignaling) {
        _shouldRejoinCallUsingInternalSignaling = NO;
        [self shouldRejoinCall];
    }
    
    if (!previousUserInCall) {
        // Do nothing if app user is stil not in the call
        if (!_userInCall) {return;}
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
    
    if (newSessions.count > 0) {
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
            NCPeerConnection *peerConnectionWrapper = [self getOrCreatePeerConnectionWrapperForSessionId:sessionId ofType:kRoomTypeVideo];
            if ([_externalSignalingController hasMCU]) {
                // Only request offer if user is sharing audio or video streams
                if ([self userHasStreams:sessionId]) {
                    NSLog(@"Requesting offer to the MCU for session: %@", sessionId);
                    [_externalSignalingController requestOfferForSessionId:sessionId andRoomType:kRoomTypeVideo];
                }
            } else {
                NSComparisonResult result = [sessionId compare:[self signalingSessionId]];
                if (result == NSOrderedAscending) {
                    NSLog(@"Creating offer...");
                    [peerConnectionWrapper sendOffer];
                } else {
                    NSLog(@"Waiting for offer...");
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
        // Set inCall flag for app user
        if ([sessionId isEqualToString:[self signalingSessionId]]) {
            _userInCall = inCall;
        }
        // Add session if inCall
        if (inCall) {
            [sessions addObject:sessionId];
        }
    }
    //NSLog(@"InCall sessions: %@", sessions);
    return sessions;
}

- (NSString *)getUserIdFromSessionId:(NSString *)sessionId
{
    if ([_externalSignalingController isEnabled]) {
        return [_externalSignalingController getUserIdFromSessionId:sessionId];
    }
    NSInteger callAPIVersion = [[NCAPIController sharedInstance] callAPIVersionForAccount:_account];
    NSString *userId = nil;
    for (NSMutableDictionary *user in _peersInCall) {
        NSString *userSessionId = [user objectForKey:@"sessionId"];
        if ([userSessionId isEqualToString:sessionId]) {
            userId = [user objectForKey:@"userId"];
            if (callAPIVersion >= APIv3) {
                userId = [user objectForKey:@"actorId"];
            }
        }
    }
    return userId;
}

- (NSString *)getDisplayNameFromSessionId:(NSString *)sessionId
{    
    if ([_externalSignalingController isEnabled]) {
        return [_externalSignalingController getDisplayNameFromSessionId:sessionId];
    }
    for (NSMutableDictionary *user in _peersInCall) {
        NSString *userSessionId = [user objectForKey:@"sessionId"];
        if ([userSessionId isEqualToString:sessionId]) {
            return [user objectForKey:@"displayName"];
        }
    }
    
    return nil;
}

#pragma mark - NCPeerConnectionDelegate

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
        // If publisher peer failed then reconnect
        if (peerConnection.isMCUPublisherPeer) {
            [self forceReconnect];
        // If another peer failed using MCU then request a new offer
        } else if ([_externalSignalingController hasMCU]) {
            NSString *sessionId = [peerConnection.peerId copy];
            NSString *roomType = [peerConnection.roomType copy];
            NSNumber *timeout = [NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970] + 60];
            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
            [userInfo setObject:sessionId forKey:@"sessionId"];
            [userInfo setObject:roomType forKey:@"roomType"];
            [userInfo setValue:timeout forKey:@"timeout"];
            
            // Close failed peer connection
            [self cleanPeerConnectionForSessionId:peerConnection.peerId ofType:peerConnection.roomType];
            // Request new offer
            [_externalSignalingController requestOfferForSessionId:peerConnection.peerId andRoomType:peerConnection.roomType];
            // Set timeout to request new offer
            NSTimer *pendingOfferTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(requestNewOffer:) userInfo:userInfo repeats:YES];
            
            NSString *peerKey = [peerConnection.peerId stringByAppendingString:peerConnection.roomType];
            [_pendingOffersDict setObject:pendingOfferTimer forKey:peerKey];
        }
    }
    
    if (!peerConnection.isMCUPublisherPeer) {
        [self.delegate callController:self iceStatusChanged:newState ofPeer:peerConnection];
    }
}

- (void)peerConnectionDidOpenStatusDataChannel:(NCPeerConnection *)peerConnection
{
    // Send current audio state
    if (self.isAudioEnabled) {
        NSLog(@"Send audioOn");
        [peerConnection sendDataChannelMessageOfType:@"audioOn" withPayload:nil];
    } else {
        NSLog(@"Send audioOff");
        [peerConnection sendDataChannelMessageOfType:@"audioOff" withPayload:nil];
    }
    
    // Send current video state
    if (self.isVideoEnabled) {
        NSLog(@"Send videoOn");
        [peerConnection sendDataChannelMessageOfType:@"videoOn" withPayload:nil];
    } else {
        NSLog(@"Send videoOff");
        [peerConnection sendDataChannelMessageOfType:@"videoOff" withPayload:nil];
    }
    
    // Send nick using mcu
    if (peerConnection.isMCUPublisherPeer) {
        [self startSendingNick];
    }
}

- (void)peerConnection:(NCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NCICECandidateMessage *message = [[NCICECandidateMessage alloc] initWithCandidate:candidate
                                                                                 from:[self signalingSessionId]
                                                                                   to:peerConnection.peerId
                                                                                  sid:nil
                                                                             roomType:peerConnection.roomType];
    
    if ([_externalSignalingController isEnabled]) {
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
                                            sid:nil
                                            roomType:peerConnection.roomType
                                            nick:_userDisplayName];
    
    if ([_externalSignalingController isEnabled]) {
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
