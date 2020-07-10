//
//  CallKitManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 09.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>

extern NSString * const CallKitManagerDidAnswerCallNotification;
extern NSString * const CallKitManagerDidEndCallNotification;
extern NSString * const CallKitManagerDidStartCallNotification;
extern NSString * const CallKitManagerDidChangeAudioMuteNotification;
extern NSString * const CallKitManagerWantsToUpgradeToVideoCall;

@interface CallKitCall : NSObject

@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) CXCallUpdate *update;

@end

@interface CallKitManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *calls; // uuid -> callKitCall

+ (instancetype)sharedInstance;
+ (BOOL)isCallKitAvailable;
- (void)reportIncomingCall:(NSString *)token withDisplayName:(NSString *)displayName forAccountId:(NSString *)accountId;
- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName withAccountId:(NSString *)accountId;
- (void)endCall:(NSString *)token;
- (void)reportAudioMuted:(BOOL)muted forCall:(NSString *)token;


@end
