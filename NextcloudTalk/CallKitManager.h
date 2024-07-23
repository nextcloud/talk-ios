/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>

extern NSString * const CallKitManagerDidAnswerCallNotification;
extern NSString * const CallKitManagerDidEndCallNotification;
extern NSString * const CallKitManagerDidStartCallNotification;
extern NSString * const CallKitManagerDidChangeAudioMuteNotification;
extern NSString * const CallKitManagerWantsToUpgradeToVideoCallNotification;
extern NSString * const CallKitManagerDidFailRequestingCallTransactionNotification;

@interface CallKitCall : NSObject

@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) CXCallUpdate *update;
@property (nonatomic, assign) BOOL reportedWhileInCall;
@property (nonatomic, assign) BOOL isRinging;
@property (nonatomic, assign) BOOL initiator;
@property (nonatomic, assign) BOOL silentCall;
@property (nonatomic, assign) BOOL recordingConsent;

@end

@class NCPushNotification;

@interface CallKitManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *calls; // uuid -> callKitCall

+ (instancetype)sharedInstance;
+ (BOOL)isCallKitAvailable;
- (void)setDefaultProviderConfiguration;
- (void)reportIncomingCall:(NSString *)token withDisplayName:(NSString *)displayName forAccountId:(NSString *)accountId;
- (void)reportIncomingCallForNonCallKitDevicesWithPushNotification:(NCPushNotification *)pushNotification;
- (void)reportIncomingCallForOldAccount;
- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName asInitiator:(BOOL)initiator silently:(BOOL)silently recordingConsent:(BOOL)recordingConsent withAccountId:(NSString *)accountId;
- (void)endCall:(NSString *)token withStatusCode:(NSInteger)statusCode;
- (void)changeAudioMuted:(BOOL)muted forCall:(NSString *)token;
- (void)switchCallFrom:(NSString *)from toCall:(NSString *)to;


@end
