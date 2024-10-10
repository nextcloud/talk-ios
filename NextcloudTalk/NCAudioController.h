/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

extern NSString * const AudioSessionDidChangeRouteNotification;
extern NSString * const AudioSessionWasActivatedByProviderNotification;
extern NSString * const AudioSessionDidChangeRoutingInformationNotification;

NS_ASSUME_NONNULL_BEGIN

@interface NCAudioController : NSObject <RTCAudioSessionDelegate>

@property (nonatomic, strong) RTCAudioSession *rtcAudioSession;
@property (nonatomic, assign) BOOL isSpeakerActive;
@property (nonatomic, assign) NSInteger numberOfAvailableInputs;

+ (instancetype)sharedInstance;

- (void)setAudioSessionToVoiceChatMode;
- (void)setAudioSessionToVideoChatMode;
- (void)disableAudioSession;
- (void)providerDidActivateAudioSession:(AVAudioSession *)audioSession;
- (void)providerDidDeactivateAudioSession:(AVAudioSession *)audioSession;
- (BOOL)isAudioRouteChangeable;

@end

NS_ASSUME_NONNULL_END
