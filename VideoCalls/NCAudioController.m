//
//  NCAudioController.m
//  VideoCalls
//
//  Created by Ivan Sein on 22.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "NCAudioController.h"

#import "CallKitManager.h"

@interface NCAudioController () <RTCAudioSessionDelegate>

@property (nonatomic, strong) RTCAudioSession *rtcAudioSession;

@end

@implementation NCAudioController

+ (NCAudioController *)sharedInstance
{
    static NCAudioController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NCAudioController alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        RTCAudioSessionConfiguration *configuration = [RTCAudioSessionConfiguration webRTCConfiguration];
        configuration.category = AVAudioSessionCategoryPlayAndRecord;
        configuration.mode = AVAudioSessionModeVideoChat;
        [RTCAudioSessionConfiguration setWebRTCConfiguration:configuration];
        
        _rtcAudioSession = [RTCAudioSession sharedInstance];
        [_rtcAudioSession lockForConfiguration];
        NSError *error = nil;
        [_rtcAudioSession setConfiguration:configuration error:&error];
        if (error) {
            NSLog(@"Error setting configuration: %@", error.localizedDescription);
        }
        [_rtcAudioSession unlockForConfiguration];
        
        if ([CallKitManager isCallKitAvailable]) {
            _rtcAudioSession.useManualAudio = YES;
        }
        
        [_rtcAudioSession addDelegate:self];
    }
    return self;
}

#pragma mark - Audio session configuration

- (void)setAudioSessionToVoiceChatMode
{
    [self changeAudioSessionConfigurationModeTo:AVAudioSessionModeVoiceChat];
}

- (void)setAudioSessionToVideoChatMode
{
    [self changeAudioSessionConfigurationModeTo:AVAudioSessionModeVideoChat];
}

- (void)changeAudioSessionConfigurationModeTo:(NSString *)mode
{
    RTCAudioSessionConfiguration *configuration = [RTCAudioSessionConfiguration webRTCConfiguration];
    configuration.category = AVAudioSessionCategoryPlayAndRecord;
    configuration.mode = mode;

    [_rtcAudioSession lockForConfiguration];
    BOOL hasSucceeded = NO;
    NSError *error = nil;
    if (_rtcAudioSession.isActive) {
        hasSucceeded = [_rtcAudioSession setConfiguration:configuration error:&error];
    } else {
        hasSucceeded = [_rtcAudioSession setConfiguration:configuration
                                          active:YES
                                           error:&error];
    }
    if (!hasSucceeded) {
        NSLog(@"Error setting configuration: %@", error.localizedDescription);
    }
    [_rtcAudioSession unlockForConfiguration];
}

- (void)disableAudioSession
{
    [_rtcAudioSession lockForConfiguration];
    NSError *error = nil;
    BOOL hasSucceeded = [_rtcAudioSession setActive:NO error:&error];
    if (!hasSucceeded) {
        NSLog(@"Error setting configuration: %@", error.localizedDescription);
    }
    [_rtcAudioSession unlockForConfiguration];
}

- (BOOL)isSpeakerActive
{
    return [_rtcAudioSession mode] == AVAudioSessionModeVideoChat;
}

- (void)providerDidActivateAudioSession:(AVAudioSession *)audioSession
{
    [_rtcAudioSession audioSessionDidActivate:audioSession];
    _rtcAudioSession.isAudioEnabled = YES;
}

- (void)providerDidDeactivateAudioSession:(AVAudioSession *)audioSession
{
    [_rtcAudioSession audioSessionDidDeactivate:audioSession];
    _rtcAudioSession.isAudioEnabled = NO;
}

@end
