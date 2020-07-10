//
//  CallKitManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 09.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "CallKitManager.h"
#import <CallKit/CXError.h>

#import "NCAudioController.h"
#import "NCAPIController.h"
#import "NCNotificationController.h"
#import "NCRoomsManager.h"

NSString * const CallKitManagerDidAnswerCallNotification        = @"CallKitManagerDidAnswerCallNotification";
NSString * const CallKitManagerDidEndCallNotification           = @"CallKitManagerDidEndCallNotification";
NSString * const CallKitManagerDidStartCallNotification         = @"CallKitManagerDidStartCallNotification";
NSString * const CallKitManagerDidChangeAudioMuteNotification   = @"CallKitManagerDidChangeAudioMuteNotification";
NSString * const CallKitManagerWantsToUpgradeToVideoCall        = @"CallKitManagerWantsToUpgradeToVideoCall";

@interface CallKitManager () <CXProviderDelegate>

@property (nonatomic, strong) CXProvider *provider;
@property (nonatomic, strong) CXCallController *callController;
@property (nonatomic, strong) NSTimer *hangUpTimer;

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
    }
    return self;
}

+ (BOOL)isCallKitAvailable
{
    // CallKit should be deactivated in China as requested by Apple
    return ![NSLocale.currentLocale.countryCode isEqual: @"CN"];
}

#pragma mark - Getters

- (CXProvider *)provider
{
    if (!_provider) {
        CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:@"Nextcloud Talk"];
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
    
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        if (!error) {
            [weakSelf.calls setObject:call forKey:callUUID];
            weakSelf.hangUpTimer = [NSTimer scheduledTimerWithTimeInterval:45.0  target:self selector:@selector(endCallWithMissedCallNotification:) userInfo:call repeats:NO];
            [weakSelf getCallInfoForCall:call];
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
    } else {
        TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:call.accountId];
        [[NCAPIController sharedInstance] getRoomForAccount:account withToken:call.token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:call.accountId];
                [self updateCall:call withDisplayName:room.displayName];
            }
        }];
    }
}

- (void)updateCall:(CallKitCall *)call withDisplayName:(NSString *)displayName
{
    call.displayName = displayName;
    call.update.localizedCallerName = displayName;
    
    [self.provider reportCallWithUUID:call.uuid updated:call.update];
}

- (void)stopHangUpTimer
{
    [_hangUpTimer invalidate];
    _hangUpTimer = nil;
}

- (void)endCallWithMissedCallNotification:(NSTimer*)timer
{
    CallKitCall *call = [timer userInfo];
    if (call) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
        [userInfo setValue:call.displayName forKey:@"displayName"];
        [userInfo setValue:@(kNCLocalNotificationTypeMissedCall) forKey:@"localNotificationType"];
        [userInfo setObject:call.accountId forKey:@"accountId"];
        [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeMissedCall withUserInfo:userInfo];
    }
    
    [self endCallWithUUID:call.uuid];
}

- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName withAccountId:(NSString *)accountId
{
    if (![CallKitManager isCallKitAvailable]) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:token forKey:@"roomToken"];
        [userInfo setValue:@(videoEnabled) forKey:@"isVideoEnabled"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidStartCallNotification
                                                            object:self
                                                          userInfo:userInfo];
        return;
    }
    
    if (_calls.count == 0) {
        
        CXCallUpdate *update = [self defaultCallUpdate];
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:token];
        update.remoteHandle = handle;
        update.localizedCallerName = displayName;
        
        NSUUID *callUUID = [NSUUID new];
        CallKitCall *call = [[CallKitCall alloc] init];
        call.uuid = callUUID;
        call.token = token;
        call.displayName = displayName;
        call.accountId = accountId;
        call.update = update;
        
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
        startCallAction.video = videoEnabled;
        startCallAction.contactIdentifier = displayName;
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:startCallAction];
        
        __weak CallKitManager *weakSelf = self;
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (!error) {
                [weakSelf.calls setObject:call forKey:callUUID];
            } else {
                NSLog(@"%@", error.localizedDescription);
            }
        }];
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

- (void)reportAudioMuted:(BOOL)muted forCall:(NSString *)token
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

#pragma mark - CXProviderDelegate

- (void)providerDidReset:(CXProvider *)provider
{
    NSLog(@"Provider:didReset");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(nonnull CXStartCallAction *)action
{
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    [update setLocalizedCallerName:action.contactIdentifier];
    [_provider reportCallWithUUID:action.callUUID updated:update];
    
    [provider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate new]];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:action.handle.value forKey:@"roomToken"];
    [userInfo setValue:@(action.isVideo) forKey:@"isVideoEnabled"];
    [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidStartCallNotification
                                                        object:self
                                                      userInfo:userInfo];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    CallKitCall *call = [_calls objectForKey:action.callUUID];
    if (call) {
        [self stopHangUpTimer];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:call.token forKey:@"roomToken"];
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
        NSString *leaveCallToken = [call.token copy];
        [_calls removeObjectForKey:action.callUUID];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:leaveCallToken forKey:@"roomToken"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidEndCallNotification
                                                            object:self
                                                          userInfo:userInfo];
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
    [[NCAudioController sharedInstance] providerDidActivateAudioSession:audioSession];
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(nonnull AVAudioSession *)audioSession
{
    NSLog(@"Provider:didDeactivateAudioSession - %@", audioSession);
    [[NCAudioController sharedInstance] providerDidDeactivateAudioSession:audioSession];
}


@end
