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
    AVAudioSessionPortDescription *currentOutput = nil;

    self.numberOfAvailableInputs = audioSession.availableInputs.count;

    if (audioSession.currentRoute.outputs.count > 0) {
        currentOutput = audioSession.currentRoute.outputs[0];
    }

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
