//
//  NCAudioController.h
//  VideoCalls
//
//  Created by Ivan Sein on 22.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

@interface NCAudioController : NSObject

+ (instancetype)sharedInstance;

- (void)setAudioSessionToVoiceChatMode;
- (void)setAudioSessionToVideoChatMode;
- (void)changeAudioSessionConfigurationModeTo:(NSString *)mode;
- (void)disableAudioSession;
- (BOOL)isSpeakerActive;
- (void)providerDidActivateAudioSession:(AVAudioSession *)audioSession;
- (void)providerDidDeactivateAudioSession:(AVAudioSession *)audioSession;

@end
