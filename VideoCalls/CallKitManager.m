//
//  CallKitManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 09.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "CallKitManager.h"
#import <CallKit/CallKit.h>
#import <CallKit/CXError.h>

#import "NCAudioController.h"
#import "NCNotificationController.h"
#import "NCRoomsManager.h"

NSString * const CallKitManagerDidAnswerCallNotification        = @"CallKitManagerDidAnswerCallNotification";
NSString * const CallKitManagerDidEndCallNotification           = @"CallKitManagerDidEndCallNotification";
NSString * const CallKitManagerDidStartCallNotification         = @"CallKitManagerDidStartCallNotification";
NSString * const CallKitManagerDidChangeAudioMuteNotification   = @"CallKitManagerDidChangeAudioMuteNotification";

@interface CallKitManager () <CXProviderDelegate>

@property (nonatomic, strong) CXProvider *provider;
@property (nonatomic, strong) CXCallController *callController;
@property (nonatomic, strong) NSTimer *hangUpTimer;

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

#pragma mark - Actions

- (void)reportIncomingCallForRoom:(NSString *)token withDisplayName:(NSString *)displayName
{
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    update.supportsHolding = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:token];
    update.localizedCallerName = displayName;
    update.hasVideo = NO;
    
    _currentCallUUID = [NSUUID new];
    _currentCallToken = token;
    _currentCallDisplayName = displayName;
    _hangUpTimer = [NSTimer scheduledTimerWithTimeInterval:45.0  target:self selector:@selector(hangUpCurrentCall) userInfo:nil repeats:NO];
    
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:_currentCallUUID update:update completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Provider could not present incoming call view.");
            weakSelf.currentCallUUID = nil;
            weakSelf.currentCallToken = nil;
            weakSelf.currentCallDisplayName = nil;
        }
    }];
}

- (void)stopHangUpTimer
{
    [_hangUpTimer invalidate];
    _hangUpTimer = nil;
}

- (void)hangUpCurrentCall
{
    if (_currentCallUUID && _currentCallToken && _currentCallDisplayName) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:_currentCallToken forKey:@"roomToken"];
        [userInfo setValue:_currentCallDisplayName forKey:@"displayName"];
        [userInfo setValue:@(kNCLocalNotificationTypeMissedCall) forKey:@"localNotificationType"];
        [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeMissedCall withUserInfo:userInfo];
    }
    
    [self endCurrentCall];
}

- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName
{
    if (!_currentCallUUID) {
        _currentCallUUID = [NSUUID new];
        _currentCallToken = token;
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:token];
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:_currentCallUUID handle:handle];
        startCallAction.video = videoEnabled;
        startCallAction.contactIdentifier = displayName;
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:startCallAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"%@", error.localizedDescription);
            }
        }];
    }
}

- (void)endCurrentCall
{
    if (_currentCallUUID) {
        CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:_currentCallUUID];
        CXTransaction *transaction = [[CXTransaction alloc] init];
        [transaction addAction:endCallAction];
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
    if (_currentCallToken) {
        [self stopHangUpTimer];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:_currentCallToken forKey:@"roomToken"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidAnswerCallNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    if (_currentCallToken) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:_currentCallToken forKey:@"roomToken"];
        [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidEndCallNotification
                                                            object:self
                                                          userInfo:userInfo];
        self.currentCallUUID = nil;
        self.currentCallToken = nil;
        self.currentCallDisplayName = nil;
    }
    
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
    if (_currentCallToken) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:_currentCallToken forKey:@"roomToken"];
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
