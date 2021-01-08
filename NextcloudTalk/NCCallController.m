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
#import "NCAPIController.h"
#import "NCAudioController.h"
#import "NCSettingsController.h"
#import "NCSignalingController.h"
#import "NCExternalSignalingController.h"

static NSString * const kNCMediaStreamId = @"NCMS";
static NSString * const kNCAudioTrackId = @"NCa0";
static NSString * const kNCVideoTrackId = @"NCv0";
static NSString * const kNCVideoTrackKind = @"video";

@interface NCCallController () <NCPeerConnectionDelegate, NCSignalingControllerObserver, NCExternalSignalingControllerDelegate>

@property (nonatomic, assign) BOOL isAudioOnly;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) BOOL leavingCall;
@property (nonatomic, assign) BOOL preparedForRejoin;
@property (nonatomic, assign) BOOL joinedCallOnce;
@property (nonatomic, assign) NSInteger joinCallAttempts;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSTimer *micAudioLevelTimer;
@property (nonatomic, assign) BOOL speaking;
@property (nonatomic, strong) NSTimer *sendNickTimer;
@property (nonatomic, strong) NSArray *pendingUsersInRoom;
@property (nonatomic, strong) NSArray *usersInRoom;
@property (nonatomic, strong) NSArray *peersInCall;
@property (nonatomic, strong) NCPeerConnection *ownPeerConnection;
@property (nonatomic, strong) NSMutableDictionary *connectionsDict;
@property (nonatomic, strong) NSMutableDictionary *pendingOffersDict;
@property (nonatomic, strong) RTCMediaStream *localStream;
@property (nonatomic, strong) RTCAudioTrack *localAudioTrack;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong) NCSignalingController *signalingController;
@property (nonatomic, strong) NCExternalSignalingController *externalSignalingController;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NSURLSessionTask *joinCallTask;
@property (nonatomic, strong) NSURLSessionTask *getPeersForCallTask;

@end

@implementation NCCallController

- (instancetype)initWithDelegate:(id<NCCallControllerDelegate>)delegate inRoom:(NCRoom *)room forAudioOnlyCall:(BOOL)audioOnly withSessionId:(NSString *)sessionId
{
    self = [super init];
    
    if (self) {
        _delegate = delegate;
        _room = room;
        _isAudioOnly = audioOnly;
        _userSessionId = sessionId;
        _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] init];
        _connectionsDict = [[NSMutableDictionary alloc] init];
        _pendingOffersDict = [[NSMutableDictionary alloc] init];
        _usersInRoom = [[NSArray alloc] init];
        _peersInCall = [[NSArray alloc] init];
        
        _signalingController = [[NCSignalingController alloc] initForRoom:room];
        _signalingController.observer = self;
        
        _account = [[NCDatabaseManager sharedInstance] activeAccount];
        _externalSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:_account.accountId];
        _externalSignalingController.delegate = self;
        
        if (audioOnly) {
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

- (void)joinCall
{
    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (!error) {
            [self.delegate callControllerDidJoinCall:self];
            [self getPeersForCall];
            [self startMonitoringMicrophoneAudioLevel];
            if ([self->_externalSignalingController isEnabled]) {
                _userSessionId = [self->_externalSignalingController sessionId];
                if ([self->_externalSignalingController hasMCU]) {
                    [self createOwnPublishPeerConnection];
                }
                if (self->_pendingUsersInRoom) {
                    NSLog(@"Procees pending users on start call");;
                    NSArray *usersInRoom = [self->_pendingUsersInRoom copy];
                    self->_pendingUsersInRoom = nil;
                    [self processUsersInRoom:usersInRoom];
                }
            } else {
                [self->_signalingController startPullingSignalingMessages];
            }
            self->_joinedCallOnce = YES;
            [self setInCall:YES];
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
    _userSessionId = [_externalSignalingController sessionId];
    _joinCallTask = [[NCAPIController sharedInstance] joinCall:_room.token forAccount:_account withCompletionBlock:^(NSError *error, NSInteger statusCode) {
        if (!error) {
            [self.delegate callControllerDidJoinCall:self];
            NSLog(@"Rejoined call");
            if ([self->_externalSignalingController hasMCU]) {
                [self createOwnPublishPeerConnection];
            }
            if (self->_pendingUsersInRoom) {
                NSLog(@"Procees pending users on rejoin");
                NSArray *usersInRoom = [self->_pendingUsersInRoom copy];
                self->_pendingUsersInRoom = nil;
                [self processUsersInRoom:usersInRoom];
            }
            [self setInCall:YES];
        } else {
            NSLog(@"Could not rejoin call. Error: %@", error.description);
        }
    }];
}

- (void)willRejoinCall
{
    NSLog(@"willRejoinCall");
    [self setInCall:NO];
    [self cleanCurrentPeerConnections];
    [self.delegate callControllerIsReconnectingCall:self];
    _preparedForRejoin = YES;
}


- (void)forceReconnect
{
    NSLog(@"forceReconnect");
    [self setInCall:NO];
    [self cleanCurrentPeerConnections];
    [self.delegate callControllerIsReconnectingCall:self];
    [_externalSignalingController forceReconnect];
}

- (void)leaveCall
{
    [self setLeavingCall:YES];
    [self stopSendingNick];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _externalSignalingController.delegate = nil;
    
    [self cleanCurrentPeerConnections];
    
    [_localStream removeAudioTrack:_localAudioTrack];
    [_localStream removeVideoTrack:_localVideoTrack];
    _localStream = nil;
    _localAudioTrack = nil;
    _localVideoTrack = nil;
    _peerConnectionFactory = nil;
    _connectionsDict = nil;
    
    [self stopMonitoringMicrophoneAudioLevel];
    [_signalingController stopAllRequests];
    
    if (_inCall) {
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
    RTCVideoTrack *videoTrack = [_localStream.videoTracks firstObject];
    return videoTrack ? videoTrack.isEnabled : NO;
}

- (BOOL)isAudioEnabled
{
    RTCAudioTrack *audioTrack = [_localStream.audioTracks firstObject];
    return audioTrack ? audioTrack.isEnabled : NO;
}

- (void)enableVideo:(BOOL)enable
{
    RTCVideoTrack *videoTrack = [_localStream.videoTracks firstObject];
    [videoTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"videoOn" : @"videoOff" withPayload:nil];
}

- (void)enableAudio:(BOOL)enable
{
    RTCAudioTrack *audioTrack = [_localStream.audioTracks firstObject];
    [audioTrack setIsEnabled:enable];
    [self sendDataChannelMessageToAllOfType:enable ? @"audioOn" : @"audioOff" withPayload:nil];
    if (!enable) {
        _speaking = NO;
        [self sendDataChannelMessageToAllOfType:@"stoppedSpeaking" withPayload:nil];
    }
}

#pragma mark - Call controller

- (void)cleanCurrentPeerConnections
{
    for (NCPeerConnection *peerConnectionWrapper in [_connectionsDict allValues]) {
        [self.delegate callController:self peerLeft:peerConnectionWrapper];
        peerConnectionWrapper.delegate = nil;
        [peerConnectionWrapper close];
    }
    for (NSTimer *pendingOfferTimer in [_pendingOffersDict allValues]) {
        [pendingOfferTimer invalidate];
    }
    _connectionsDict = [[NSMutableDictionary alloc] init];
    _pendingOffersDict = [[NSMutableDictionary alloc] init];
    _usersInRoom = [[NSArray alloc] init];
}

- (void)cleanPeerConnectionsForSessionId:(NSString *)sessionId
{
    NSString *peerKey = [sessionId stringByAppendingString:kRoomTypeVideo];
    NCPeerConnection *removedPeerConnection = [_connectionsDict objectForKey:peerKey];
    if (removedPeerConnection) {
        NSLog(@"Removing peer connection: %@", sessionId);
        [self.delegate callController:self peerLeft:removedPeerConnection];
        removedPeerConnection.delegate = nil;
        [removedPeerConnection close];
        [_connectionsDict removeObjectForKey:peerKey];
    }
    // Close possible screen peers
    peerKey = [sessionId stringByAppendingString:kRoomTypeScreen];
    removedPeerConnection = [_connectionsDict objectForKey:peerKey];
    if (removedPeerConnection) {
        removedPeerConnection.delegate = nil;
        [removedPeerConnection close];
        [_connectionsDict removeObjectForKey:peerKey];
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
    NSDictionary *mandatoryConstraints = @{ kRTCMediaConstraintsLevelControl : kRTCMediaConstraintsValueTrue };
    RTCMediaConstraints *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                          optionalConstraints:nil];
    
    RTCAudioSource *source = [_peerConnectionFactory audioSourceWithConstraints:constraints];
    _localAudioTrack = [_peerConnectionFactory audioTrackWithSource:source trackId:kNCAudioTrackId];
    [_localStream addAudioTrack:_localAudioTrack];
}

- (void)createLocalVideoTrack
{
#if !TARGET_IPHONE_SIMULATOR
    RTCVideoSource *source = [_peerConnectionFactory videoSource];
    RTCCameraVideoCapturer *capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    
    [self.delegate callController:self didCreateLocalVideoCapturer:capturer];
    
    _localVideoTrack = [_peerConnectionFactory videoTrackWithSource:source trackId:kNCVideoTrackId];
    [_localStream addVideoTrack:_localVideoTrack];
#endif
}

- (void)createLocalMedia
{
    RTCMediaStream *localMediaStream = [_peerConnectionFactory mediaStreamWithStreamId:kNCMediaStreamId];
    self.localStream = localMediaStream;
    [self createLocalAudioTrack];
    if (!_isAudioOnly) {
        [self createLocalVideoTrack];
    }
}

#pragma mark - Peer Connection Wrapper

- (NCPeerConnection *)getPeerConnectionWrapperForSessionId:(NSString *)sessionId ofType:(NSString *)roomType
{
    NSString *peerKey = [sessionId stringByAppendingString:roomType];
    NCPeerConnection *peerConnectionWrapper = [_connectionsDict objectForKey:peerKey];
    
    if (!peerConnectionWrapper) {
        // Create peer connection.
        NSLog(@"Creating a peer for %@", sessionId);
        
        NSArray *iceServers = [_signalingController getIceServers];
        BOOL screensharingPeer = [roomType isEqualToString:kRoomTypeScreen];
        peerConnectionWrapper = [[NCPeerConnection alloc] initWithSessionId:sessionId andICEServers:iceServers forAudioOnlyCall:screensharingPeer ? NO : _isAudioOnly];
        peerConnectionWrapper.roomType = roomType;
        peerConnectionWrapper.delegate = self;
        // TODO: Try to get display name here
        if (![_externalSignalingController hasMCU] || !screensharingPeer) {
            [peerConnectionWrapper.peerConnection addStream:_localStream];
        }
        
        [_connectionsDict setObject:peerConnectionWrapper forKey:peerKey];
        NSLog(@"Peer joined: %@", sessionId);
        [self.delegate callController:self peerJoined:peerConnectionWrapper];
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
        [_ownPeerConnection sendDataChannelMessageOfType:type withPayload:payload];
    } else {
        NSArray *connectionWrappers = [self.connectionsDict allValues];
        for (NCPeerConnection *peerConnection in connectionWrappers) {
            [peerConnection sendDataChannelMessageOfType:type withPayload:payload];
        }
    }
}

#pragma mark - External signaling support

- (void)createOwnPublishPeerConnection
{
    if (_ownPeerConnection) {
        _ownPeerConnection.delegate = nil;
        [_ownPeerConnection close];
    }
    NSLog(@"Creating own pusblish peer connection: %@", _userSessionId);
    NSArray *iceServers = [_signalingController getIceServers];
    _ownPeerConnection = [[NCPeerConnection alloc] initForMCUWithSessionId:_userSessionId andICEServers:iceServers forAudioOnlyCall:YES];
    _ownPeerConnection.roomType = kRoomTypeVideo;
    _ownPeerConnection.delegate = self;
    NSString *peerKey = [_userSessionId stringByAppendingString:kRoomTypeVideo];
    [_connectionsDict setObject:_ownPeerConnection forKey:peerKey];
    [_ownPeerConnection.peerConnection addStream:_localStream];
    [_ownPeerConnection sendPublishOfferToMCU];
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
    [_externalSignalingController requestOfferForSessionId:sessionId andRoomType:roomType];
}

- (void)checkIfPendingOffer:(NCSignalingMessage *)signalingMessage
{
    NSTimer *pendingRequestTimer = [_pendingOffersDict objectForKey:signalingMessage.from];
    if (pendingRequestTimer && signalingMessage.messageType == kNCSignalingMessageTypeOffer) {
        NSLog(@"Pending requested offer arrived. Removing timer.");
        [pendingRequestTimer invalidate];
    }
}

#pragma mark - External Signaling Controller Delegate

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedSignalingMessage:(NSDictionary *)signalingMessageDict
{
    NSLog(@"External signaling message received: %@", signalingMessageDict);
    NCSignalingMessage *signalingMessage = [NCSignalingMessage messageFromExternalSignalingJSONDictionary:signalingMessageDict];
    [self checkIfPendingOffer:signalingMessage];
    [self processSignalingMessage:signalingMessage];
}

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedParticipantListMessage:(NSDictionary *)participantListMessageDict
{
    NSLog(@"External participants message received: %@", participantListMessageDict);
    NSArray *usersInRoom = [participantListMessageDict objectForKey:@"users"];
    if (_inCall) {
        [self processUsersInRoom:usersInRoom];
    } else {
        // Store pending usersInRoom since this websocket message could
        // arrive before NCCallController knows that it's in the call.
        _pendingUsersInRoom = usersInRoom;
    }
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
                NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                NCSessionDescriptionMessage *sdpMessage = (NCSessionDescriptionMessage *)signalingMessage;
                RTCSessionDescription *description = sdpMessage.sessionDescription;
                [peerConnectionWrapper setPeerName:sdpMessage.nick];
                [peerConnectionWrapper setRemoteDescription:description];
                break;
            }
            case kNCSignalingMessageTypeCandidate:
            {
                NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                NCICECandidateMessage *candidateMessage = (NCICECandidateMessage *)signalingMessage;
                [peerConnectionWrapper addICECandidate:candidateMessage.candidate];
                break;
            }
            case kNCSignalingMessageTypeUnshareScreen:
            {
                NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:signalingMessage.from ofType:signalingMessage.roomType];
                NSString *peerKey = [peerConnectionWrapper.peerId stringByAppendingString:kRoomTypeScreen];
                NCPeerConnection *screenPeerConnection = [_connectionsDict objectForKey:peerKey];
                if (screenPeerConnection) {
                    [screenPeerConnection close];
                    [_connectionsDict removeObjectForKey:peerKey];
                }
                [self.delegate callController:self didReceiveUnshareScreenFromPeer:peerConnectionWrapper];
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
            case kNCSignalingMessageTypeUknown:
                NSLog(@"Received an unknown signaling message: %@", signalingMessage);
                break;
        }
    }
}

- (void)processUsersInRoom:(NSArray *)users
{
    NSMutableArray *newSessions = [self getInCallSessionsFromUsersInRoom:users];
    NSMutableArray *oldSessions = [NSMutableArray arrayWithArray:_usersInRoom];
    
    //Save current sessions in call
    _usersInRoom = [NSArray arrayWithArray:newSessions];
    
    // Calculate sessions that left the call
    NSMutableArray *leftSessions = [NSMutableArray arrayWithArray:oldSessions];
    [leftSessions removeObjectsInArray:newSessions];
    
    // Calculate sessions that join the call
    [newSessions removeObjectsInArray:oldSessions];
    
    if (_leavingCall) {return;}
    
    if (newSessions.count > 0) {
        [self getPeersForCall];
    }
    
    // Create new peer connections for new sessions in call
    for (NSString *sessionId in newSessions) {
        NSString *peerKey = [sessionId stringByAppendingString:kRoomTypeVideo];
        if (![_connectionsDict objectForKey:peerKey] && ![_userSessionId isEqualToString:sessionId]) {
            if ([_externalSignalingController hasMCU]) {
                NSLog(@"Requesting offer to the MCU for session: %@", sessionId);
                [_externalSignalingController requestOfferForSessionId:sessionId andRoomType:kRoomTypeVideo];
            } else {
                NSComparisonResult result = [sessionId compare:_userSessionId];
                if (result == NSOrderedAscending) {
                    NSLog(@"Creating offer...");
                    NCPeerConnection *peerConnectionWrapper = [self getPeerConnectionWrapperForSessionId:sessionId ofType:kRoomTypeVideo];
                    [peerConnectionWrapper sendOffer];
                } else {
                    NSLog(@"Waiting for offer...");
                }
            }
        }
    }
    
    // Close old peer connections for sessions that left the call
    for (NSString *sessionId in leftSessions) {
        [self cleanPeerConnectionsForSessionId:sessionId];
    }
}

- (NSMutableArray *)getInCallSessionsFromUsersInRoom:(NSArray *)users
{
    NSMutableArray *sessions = [[NSMutableArray alloc] init];
    for (NSMutableDictionary *user in users) {
        NSString *sessionId = [user objectForKey:@"sessionId"];
        BOOL inCall = [[user objectForKey:@"inCall"] boolValue];
        if (inCall) {
            [sessions addObject:sessionId];
        }
    }
    NSLog(@"InCall sessions: %@", sessions);
    return sessions;
}

- (NSString *)getUserIdFromSessionId:(NSString *)sessionId
{
    if ([_externalSignalingController isEnabled]) {
        return [_externalSignalingController getUserIdFromSessionId:sessionId];
    }
    NSString *userId = nil;
    for (NSMutableDictionary *user in _peersInCall) {
        NSString *userSessionId = [user objectForKey:@"sessionId"];
        if ([userSessionId isEqualToString:sessionId]) {
            userId = [user objectForKey:@"userId"];
        }
    }
    return userId;
}

- (void)getUserIdInServerFromSessionId:(NSString *)sessionId withCompletionBlock:(GetUserIdForSessionIdCompletionBlock)block
{
    [[NCAPIController sharedInstance] getPeersForCall:_room.token forAccount:_account withCompletionBlock:^(NSMutableArray *peers, NSError *error) {
        if (!error) {
            NSString *userId = nil;
            for (NSMutableDictionary *user in peers) {
                NSString *userSessionId = [user objectForKey:@"sessionId"];
                if ([userSessionId isEqualToString:sessionId]) {
                    userId = [user objectForKey:@"userId"];
                }
            }
            if (block) {
                block(userId, nil);
            }
        } else {
            if (block) {
                block(nil, error);
            }
        }
    }];
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
    [self.delegate callController:self didRemoveStream:stream ofPeer:peerConnection];
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
            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
            [userInfo setObject:sessionId forKey:@"sessionId"];
            [userInfo setObject:roomType forKey:@"roomType"];
            // Close failed peer connection
            [self cleanPeerConnectionsForSessionId:peerConnection.peerId];
            // Request new offer
            [_externalSignalingController requestOfferForSessionId:peerConnection.peerId andRoomType:peerConnection.roomType];
            // Set timeout to request new offer
            NSTimer *pendingOfferTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(requestNewOffer:) userInfo:userInfo repeats:YES];
            [_pendingOffersDict setObject:pendingOfferTimer forKey:peerConnection.peerId];
        }
    }
    [self.delegate callController:self iceStatusChanged:newState ofPeer:peerConnection];
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
                                                                                 from:_userSessionId
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
                                            from:_userSessionId
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
