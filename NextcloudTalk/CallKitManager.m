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

#import "CallKitManager.h"
#import <CallKit/CXError.h>

#import "CallConstants.h"
#import "NCAudioController.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCNotificationController.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"

#import "NextcloudTalk-Swift.h"

NSString * const CallKitManagerDidAnswerCallNotification        = @"CallKitManagerDidAnswerCallNotification";
NSString * const CallKitManagerDidEndCallNotification           = @"CallKitManagerDidEndCallNotification";
NSString * const CallKitManagerDidStartCallNotification         = @"CallKitManagerDidStartCallNotification";
NSString * const CallKitManagerDidChangeAudioMuteNotification   = @"CallKitManagerDidChangeAudioMuteNotification";
NSString * const CallKitManagerWantsToUpgradeToVideoCall        = @"CallKitManagerWantsToUpgradeToVideoCall";
NSString * const CallKitManagerDidFailRequestingCallTransaction = @"CallKitManagerDidFailRequestingCallTransaction";

NSTimeInterval const kCallKitManagerMaxRingingTimeSeconds       = 45.0;
NSTimeInterval const kCallKitManagerCheckCallStateEverySeconds  = 5.0;

@interface CallKitManager () <CXProviderDelegate>

@property (nonatomic, strong) CXProvider *provider;
@property (nonatomic, strong) CXCallController *callController;
@property (nonatomic, strong) NSMutableDictionary *hangUpTimers; // uuid -> hangUpTimer
@property (nonatomic, strong) NSMutableDictionary *callStateTimers; // uuid -> callStateTimer
@property (nonatomic, assign) BOOL startCallRetried;

@end

@implementation CallKitCall
@end

@implementation CallKitManager

+ (CallKitManager *)sharedInstance
{
    static CallKitManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CallKitManager alloc] init];
        [sharedInstance provider];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.calls = [[NSMutableDictionary alloc] init];
        self.hangUpTimers = [[NSMutableDictionary alloc] init];
        self.callStateTimers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (BOOL)isCallKitAvailable
{
    if ([NCUtils isiOSAppOnMac]) {
        // There's currently no support for CallKit when running on MacOS.
        // If this is enabled on MacOS, there's no audio, because we fail to retrieve
        // the streams from CallKit. Tested with MacOS 12 & 13.
        return NO;
    }

    // CallKit should be deactivated in China as requested by Apple
    return ![NSLocale.currentLocale.countryCode isEqual: @"CN"];
}

#pragma mark - Getters

- (CXProvider *)provider
{
    if (!_provider) {
        CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] init];
        configuration.supportsVideo = YES;
        configuration.maximumCallGroups = 1;
        configuration.maximumCallsPerCallGroup = 1;
        configuration.supportedHandleTypes = [NSSet setWithObjects:@(CXHandleTypePhoneNumber), @(CXHandleTypeEmailAddress), @(CXHandleTypeGeneric), nil];
        configuration.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"app-logo-callkit"]);
        _provider = [[CXProvider alloc] initWithConfiguration:configuration];
        [_provider setDelegate:self queue:nil];
    }
    return _provider;
}

- (CXCallController *)callController
{
    if (!_callController) {
        _callController = [[CXCallController alloc] init];
    }
    return _callController;
}

#pragma mark - Utils

- (CXCallUpdate *)defaultCallUpdate
{
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    update.supportsHolding = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    update.supportsDTMF = NO;
    update.hasVideo = NO;
    
    return update;
}

- (CallKitCall *)callForToken:(NSString *)token
{
    for (CallKitCall *call in [_calls allValues]) {
        if ([call.token isEqualToString:token]) {
            return call;
        }
    }
    
    return nil;;
}

#pragma mark - Actions

- (void)reportIncomingCall:(NSString *)token withDisplayName:(NSString *)displayName forAccountId:(NSString *)accountId
{
    BOOL ongoingCalls = _calls.count > 0;
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    
    // If the app is not active (e.g. in background) and there is an open chat
    BOOL isAppActive = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
    NCChatViewController *chatViewController = [[NCRoomsManager sharedInstance] chatViewController];
    if (!isAppActive && chatViewController) {
        // Leave the chat so it doesn't try to join the chat conversation when the app becomes active.
        [chatViewController leaveChat];
        [[NCUserInterfaceController sharedInstance] presentConversationsList];
    }
    
    // If the incoming call is from a different account
    if (![activeAccount.accountId isEqualToString:accountId]) {
        // If there is an ongoing call then show a local notification
        if (ongoingCalls) {
            [self reportAndCancelIncomingCall:token withDisplayName:displayName forAccountId:accountId];
            return;
        // Change accounts if there are no ongoing calls
        } else {
            [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:accountId];
        }
    }
    
    CXCallUpdate *update = [self defaultCallUpdate];
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:token];
    update.localizedCallerName = displayName;
    
    NSUUID *callUUID = [NSUUID new];
    CallKitCall *call = [[CallKitCall alloc] init];
    call.uuid = callUUID;
    call.token = token;
    call.displayName = displayName;
    call.accountId = accountId;
    call.update = update;
    call.reportedWhileInCall = ongoingCalls;
    call.isRinging = YES;
    
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        if (!error) {
            // Add call to calls array
            [weakSelf.calls setObject:call forKey:callUUID];
            
            // Add hangUpTimer to timers array
            NSTimer *hangUpTimer = [NSTimer scheduledTimerWithTimeInterval:kCallKitManagerMaxRingingTimeSeconds target:self selector:@selector(endCallWithMissedCallNotification:) userInfo:call repeats:NO];
            [weakSelf.hangUpTimers setObject:hangUpTimer forKey:callUUID];
            
            // Add callStateTimer to timers array
            NSTimer *callStateTimer = [NSTimer scheduledTimerWithTimeInterval:kCallKitManagerCheckCallStateEverySeconds target:self selector:@selector(checkCallStateForCall:) userInfo:call repeats:NO];
            [weakSelf.callStateTimers setObject:callStateTimer forKey:callUUID];
   
            // Get call info from server
            [weakSelf getCallInfoForCall:call];
        } else {
            NSLog(@"Provider could not present incoming call view.");
        }
    }];
}

- (void)reportAndCancelIncomingCall:(NSString *)token withDisplayName:(NSString *)displayName forAccountId:(NSString *)accountId
{
    CXCallUpdate *update = [self defaultCallUpdate];
    NSUUID *callUUID = [NSUUID new];
    CallKitCall *call = [[CallKitCall alloc] init];
    call.uuid = callUUID;
    call.token = token;
    call.accountId = accountId;
    call.update = update;
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        if (!error) {
            [weakSelf.calls setObject:call forKey:callUUID];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
            [userInfo setValue:@(kNCLocalNotificationTypeCancelledCall) forKey:@"localNotificationType"];
            [userInfo setObject:call.accountId forKey:@"accountId"];
            [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeCancelledCall withUserInfo:userInfo];
            [weakSelf endCallWithUUID:callUUID];
        } else {
            NSLog(@"Provider could not present incoming call view.");
        }
    }];
}

- (void)reportIncomingCallForNonCallKitDevicesWithPushNotification:(NCPushNotification *)pushNotification
{
    CXCallUpdate *update = [self defaultCallUpdate];
    NSUUID *callUUID = [NSUUID new];
    CallKitCall *call = [[CallKitCall alloc] init];
    call.uuid = callUUID;
    call.token = pushNotification.roomToken;
    call.accountId = pushNotification.accountId;
    call.update = update;
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        if (!error) {
            [weakSelf.calls setObject:call forKey:callUUID];
            [[NCNotificationController sharedInstance] showLocalNotificationForIncomingCallWithPushNotificaion:pushNotification];
            [weakSelf endCallWithUUID:callUUID];
        } else {
            NSLog(@"Provider could not present incoming call view.");
        }
    }];
}

- (void)reportIncomingCallForOldAccount
{
    CXCallUpdate *update = [self defaultCallUpdate];
    update.localizedCallerName = NSLocalizedString(@"Old account", @"Will be used as the caller name when a voip notification can't be decrypted");

    NSUUID *callUUID = [NSUUID new];
    CallKitCall *call = [[CallKitCall alloc] init];
    call.uuid = callUUID;
    call.update = update;
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        if (!error) {
            [weakSelf.calls setObject:call forKey:callUUID];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@(kNCLocalNotificationTypeCallFromOldAccount) forKey:@"localNotificationType"];
            [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeCallFromOldAccount withUserInfo:userInfo];
            [weakSelf endCallWithUUID:callUUID];
        } else {
            NSLog(@"Provider could not present incoming call view.");
        }
    }];
}

- (void)getCallInfoForCall:(CallKitCall *)call
{
    NCRoom *room = [[NCRoomsManager sharedInstance] roomWithToken:call.token forAccountId:call.accountId];
    if (room) {
        [self updateCall:call withDisplayName:room.displayName];
    }
    
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:call.accountId];
    [[NCAPIController sharedInstance] getRoomForAccount:account withToken:call.token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
        if (!error) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:call.accountId];
            [self updateCall:call withDisplayName:room.displayName];
            
            if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityCallFlags forAccountId:call.accountId]) {
                NSInteger callFlag = [[roomDict objectForKey:@"callFlag"] integerValue];
                if (callFlag == CallFlagDisconnected) {
                    [self presentMissedCallNotificationForCall:call];
                    [self endCallWithUUID:call.uuid];
                } else if ((callFlag & CallFlagWithVideo) != 0) {
                    [self updateCall:call hasVideo:YES];
                }
            }
        }
    }];
}

- (void)updateCall:(CallKitCall *)call withDisplayName:(NSString *)displayName
{
    call.displayName = displayName;
    call.update.localizedCallerName = displayName;
    
    [self.provider reportCallWithUUID:call.uuid updated:call.update];
}

- (void)updateCall:(CallKitCall *)call hasVideo:(BOOL)hasVideo
{
    call.update.hasVideo = hasVideo;
    
    [self.provider reportCallWithUUID:call.uuid updated:call.update];
}

- (void)stopHangUpTimerForCallUUID:(NSUUID *)uuid
{
    NSTimer *hangUpTimer = [_hangUpTimers objectForKey:uuid];
    if (hangUpTimer) {
        [hangUpTimer invalidate];
        [_hangUpTimers removeObjectForKey:uuid];
    }
}

- (void)stopCallStateTimerForCallUUID:(NSUUID *)uuid
{
    NSTimer *callStateTimer = [_callStateTimers objectForKey:uuid];
    if (callStateTimer) {
        [callStateTimer invalidate];
        [_callStateTimers removeObjectForKey:uuid];
    }
}

- (void)endCallWithMissedCallNotification:(NSTimer*)timer
{
    CallKitCall *call = [timer userInfo];
    [self presentMissedCallNotificationForCall:call];
    [self endCallWithUUID:call.uuid];
}

- (void)presentMissedCallNotificationForCall:(CallKitCall *)call
{
    if (call) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
        [userInfo setValue:call.displayName forKey:@"displayName"];
        [userInfo setValue:@(kNCLocalNotificationTypeMissedCall) forKey:@"localNotificationType"];
        [userInfo setObject:call.accountId forKey:@"accountId"];
        [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeMissedCall withUserInfo:userInfo];
    }
}

- (void)checkCallStateForCall:(NSTimer *)timer
{
    CallKitCall *call = [timer userInfo];
    if (!call) {
        return;
    }

    __weak CallKitManager *weakSelf = self;
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:call.accountId];
    [[NCAPIController sharedInstance] getPeersForCall:call.token forAccount:account withCompletionBlock:^(NSMutableArray *peers, NSError *error) {
        // Make sure call is still ringing at this point to avoid a race-condition between answering the call on this device and the API callback
        if (!call.isRinging) {
            return;
        }
        
        if (!error && peers.count == 0) {
            // No one is in the call, we can hang up and show missed call notification
            [self presentMissedCallNotificationForCall:call];
            [self endCallWithUUID:call.uuid];
            return;
        }
        
        NSInteger callAPIVersion = [[NCAPIController sharedInstance] callAPIVersionForAccount:account];
        for (NSMutableDictionary *user in peers) {
            NSString *userId = [user objectForKey:@"userId"];
            BOOL isUserActorType = YES;
            if (callAPIVersion >= APIv3) {
                userId = [user objectForKey:@"actorId"];
                isUserActorType = [[user objectForKey:@"actorType"] isEqualToString:@"users"];
            }
            if ([account.userId isEqualToString:userId] && isUserActorType) {
                // Account is already in a call (answered the call on a different device) -> no need to keep ringing
                [self endCallWithUUID:call.uuid];
                return;
            }
        }
        
        // Reschedule next check
        NSTimer *callStateTimer = [NSTimer scheduledTimerWithTimeInterval:kCallKitManagerCheckCallStateEverySeconds target:self selector:@selector(checkCallStateForCall:) userInfo:call repeats:NO];
        [weakSelf.callStateTimers setObject:callStateTimer forKey:call.uuid];
    }];
}

- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName silently:(BOOL)silently withAccountId:(NSString *)accountId
{
    if (![CallKitManager isCallKitAvailable]) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:token forKey:@"roomToken"];
        [userInfo setValue:@(videoEnabled) forKey:@"isVideoEnabled"];
        [userInfo setValue:@(silently) forKey:@"silentCall"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidStartCallNotification
                                                            object:self
                                                          userInfo:userInfo];
        return;
    }
    
    // Start a new call
    if (_calls.count == 0) {
        CXCallUpdate *update = [self defaultCallUpdate];
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:token];
        update.remoteHandle = handle;
        update.localizedCallerName = displayName;
        update.hasVideo = videoEnabled;
        
        NSUUID *callUUID = [NSUUID new];
        CallKitCall *call = [[CallKitCall alloc] init];
        call.uuid = callUUID;
        call.token = token;
        call.displayName = displayName;
        call.accountId = accountId;
        call.update = update;
        call.silentCall = silently;
        
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
        startCallAction.video = videoEnabled;
        startCallAction.contactIdentifier = displayName;
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:startCallAction];
        
        __weak CallKitManager *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
            [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
                if (!error) {
                    self->_startCallRetried = NO;
                    [weakSelf.calls setObject:call forKey:callUUID];
                } else {
                    if (self->_startCallRetried) {
                        NSLog(@"%@", error.localizedDescription);
                        self->_startCallRetried = NO;
                        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:token forKey:@"roomToken"];
                        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidFailRequestingCallTransaction
                                                                            object:self
                                                                          userInfo:userInfo];
                    } else {
                        self->_startCallRetried = YES;
                        [self startCall:token withVideoEnabled:videoEnabled andDisplayName:displayName silently:silently withAccountId:accountId];
                    }
                }
            }];
        });
    // Send notification for video call upgrade.
    // Since we send the token in the notification, it will only ask
    // for an upgrade if there is an ongoing (audioOnly) call in that room.
    } else if (videoEnabled) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:token forKey:@"roomToken"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerWantsToUpgradeToVideoCall
                                                            object:self
                                                          userInfo:userInfo];
    }
}

- (void)endCall:(NSString *)token
{
    CallKitCall *call = [self callForToken:token];
    if (call) {
        [self endCallWithUUID:call.uuid];
    }
}

- (void)endCallWithUUID:(NSUUID *)uuid
{
    CallKitCall *call = [_calls objectForKey:uuid];
    if (call) {
        CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:call.uuid];
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:endCallAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"%@", error.localizedDescription);
            }
        }];
    }
}

- (void)changeAudioMuted:(BOOL)muted forCall:(NSString *)token
{
    CallKitCall *call = [self callForToken:token];
    if (call) {
        CXSetMutedCallAction *muteAction = [[CXSetMutedCallAction alloc] initWithCallUUID:call.uuid muted:muted];
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:muteAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"%@", error.localizedDescription);
            }
        }];
    }
}

- (void)switchCallFrom:(NSString *)from toCall:(NSString *)to
{
    CallKitCall *call = [self callForToken:from];
    if (call) {
        call.token = to;
    }
}

#pragma mark - CXProviderDelegate

- (void)providerDidReset:(CXProvider *)provider
{
    NSLog(@"Provider:didReset");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(nonnull CXStartCallAction *)action
{
    CallKitCall *call = [_calls objectForKey:action.callUUID];
    if (call) {
        // Seems to be needed to display the call name correctly
        [_provider reportCallWithUUID:call.uuid updated:call.update];
        
        // Report outgoing call
        [provider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate new]];
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:action.handle.value forKey:@"roomToken"];
        [userInfo setValue:@(action.isVideo) forKey:@"isVideoEnabled"];
        [userInfo setValue:@(call.silentCall) forKey:@"silentCall"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidStartCallNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    CallKitCall *call = [_calls objectForKey:action.callUUID];
    if (call) {
        call.isRinging = NO;
        [self stopCallStateTimerForCallUUID:call.uuid];
        
        [self stopHangUpTimerForCallUUID:call.uuid];
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
        [userInfo setValue:@(call.update.hasVideo) forKey:@"hasVideo"];
        [userInfo setValue:@(call.reportedWhileInCall) forKey:@"waitForCallEnd"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidAnswerCallNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    [action fulfill];
    
    CallKitCall *call = [_calls objectForKey:action.callUUID];
    if (call) {
        call.isRinging = NO;
        [self stopCallStateTimerForCallUUID:call.uuid];
        
        [self stopHangUpTimerForCallUUID:call.uuid];
        NSString *leaveCallToken = [call.token copy];
        [_calls removeObjectForKey:action.callUUID];

        if (leaveCallToken) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:leaveCallToken forKey:@"roomToken"];
            [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidEndCallNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    }
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
    CallKitCall *call = [_calls objectForKey:action.callUUID];
    if (call) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
        [userInfo setValue:@(action.isMuted) forKey:@"isMuted"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidChangeAudioMuteNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession
{
    NSLog(@"Provider:didActivateAudioSession - %@", audioSession);

    [[WebRTCCommon shared] dispatch:^{
        [[NCAudioController sharedInstance] providerDidActivateAudioSession:audioSession];
    }];
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(nonnull AVAudioSession *)audioSession
{
    NSLog(@"Provider:didDeactivateAudioSession - %@", audioSession);

    [[WebRTCCommon shared] dispatch:^{
        [[NCAudioController sharedInstance] providerDidDeactivateAudioSession:audioSession];
    }];
}


@end
