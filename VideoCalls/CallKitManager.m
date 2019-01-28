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
#import "NCRoomsManager.h"

NSString * const CallKitManagerDidAnswerCallNotification  = @"CallKitManagerDidAnswerCallNotification";

@interface CallKitManager () <CXProviderDelegate>

@property (nonatomic, strong) CXProvider *provider;
@property (nonatomic, strong) CXCallController *callController;

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
    update.hasVideo = YES;
    
    _currentCallUUID = [NSUUID new];
    _currentCallToken = token;
    
    __weak CallKitManager *weakSelf = self;
    [self.provider reportNewIncomingCallWithUUID:_currentCallUUID update:update completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Provider could not present incoming call view.");
            weakSelf.currentCallUUID = nil;
            weakSelf.currentCallToken = nil;
        }
    }];
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

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:_currentCallToken forKey:@"roomToken"];
    [[NSNotificationCenter defaultCenter] postNotificationName:CallKitManagerDidAnswerCallNotification
                                                        object:self
                                                      userInfo:userInfo];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    self.currentCallUUID = nil;
    self.currentCallToken = nil;
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

- (void)provider:(CXProvider *)provider performStartCallAction:(nonnull CXStartCallAction *)action
{
    NSLog(@"Provider:performStartCallAction");
}


@end
