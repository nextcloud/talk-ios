/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCAudioController.h"

#import "CallKitManager.h"

#import "NextcloudTalk-Swift.h"

NSString * const AudioSessionDidChangeRouteNotification             = @"AudioSessionDidChangeRouteNotification";
NSString * const AudioSessionWasActivatedByProviderNotification     = @"AudioSessionWasActivatedByProviderNotification";
NSString * const AudioSessionDidChangeRoutingInformationNotification   = @"AudioSessionDidChangeRoutingInformationNotification";

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
        configuration.mode = AVAudioSessionModeVoiceChat;
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

        [self updateRouteInformation];
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
    [[WebRTCCommon shared] assertQueue];

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

    [self updateRouteInformation];
}

- (void)disableAudioSession
{
    [[WebRTCCommon shared] assertQueue];

    [_rtcAudioSession lockForConfiguration];

    NSError *error = nil;
    BOOL hasSucceeded = [_rtcAudioSession setActive:NO error:&error];

    if (!hasSucceeded) {
        NSLog(@"Error setting configuration: %@", error.localizedDescription);
    }

    [_rtcAudioSession unlockForConfiguration];
}

- (void)updateRouteInformation
{
    AVAudioSession *audioSession = self.rtcAudioSession.session;
    AVAudioSessionPortDescription *currentOutput = [audioSession.currentRoute.outputs firstObject];

    self.numberOfAvailableInputs = audioSession.availableInputs.count;

    if ([_rtcAudioSession mode] == AVAudioSessionModeVideoChat || [currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
        self.isSpeakerActive = YES;
    } else {
        self.isSpeakerActive = NO;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:AudioSessionDidChangeRoutingInformationNotification
                                                        object:self
                                                      userInfo:nil];
}

- (BOOL)isAudioRouteChangeable
{
    if (self.numberOfAvailableInputs > 1) {
        return YES;
    }

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        // A phone always supports a speaker and earpiece output
        return YES;
    }

    return NO;
}

- (void)providerDidActivateAudioSession:(AVAudioSession *)audioSession
{
    [[WebRTCCommon shared] assertQueue];

    [_rtcAudioSession audioSessionDidActivate:audioSession];
    _rtcAudioSession.isAudioEnabled = YES;

    [[NSNotificationCenter defaultCenter] postNotificationName:AudioSessionWasActivatedByProviderNotification
                                                        object:self
                                                      userInfo:nil];
}

- (void)providerDidDeactivateAudioSession:(AVAudioSession *)audioSession
{
    [[WebRTCCommon shared] assertQueue];

    [_rtcAudioSession audioSessionDidDeactivate:audioSession];
    _rtcAudioSession.isAudioEnabled = NO;
}

#pragma mark - RTCAudioSessionDelegate

- (void)audioSessionDidChangeRoute:(RTCAudioSession *)session reason:(AVAudioSessionRouteChangeReason)reason previousRoute:(AVAudioSessionRouteDescription *)previousRoute
{
    [self updateRouteInformation];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AudioSessionDidChangeRouteNotification
                                                        object:self
                                                      userInfo:nil];
}

@end
