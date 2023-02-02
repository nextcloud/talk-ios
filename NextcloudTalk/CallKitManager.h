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

#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>

extern NSString * const CallKitManagerDidAnswerCallNotification;
extern NSString * const CallKitManagerDidEndCallNotification;
extern NSString * const CallKitManagerDidStartCallNotification;
extern NSString * const CallKitManagerDidChangeAudioMuteNotification;
extern NSString * const CallKitManagerWantsToUpgradeToVideoCall;
extern NSString * const CallKitManagerDidFailRequestingCallTransaction;

@interface CallKitCall : NSObject

@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) CXCallUpdate *update;
@property (nonatomic, assign) BOOL reportedWhileInCall;
@property (nonatomic, assign) BOOL isRinging;
@property (nonatomic, assign) BOOL silentCall;

@end

@class NCPushNotification;

@interface CallKitManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *calls; // uuid -> callKitCall

+ (instancetype)sharedInstance;
+ (BOOL)isCallKitAvailable;
- (void)reportIncomingCall:(NSString *)token withDisplayName:(NSString *)displayName forAccountId:(NSString *)accountId;
- (void)reportIncomingCallForNonCallKitDevicesWithPushNotification:(NCPushNotification *)pushNotification;
- (void)reportIncomingCallForOldAccount;
- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName silently:(BOOL)silently withAccountId:(NSString *)accountId;
- (void)endCall:(NSString *)token;
- (void)changeAudioMuted:(BOOL)muted forCall:(NSString *)token;
- (void)switchCallFrom:(NSString *)from toCall:(NSString *)to;


@end
