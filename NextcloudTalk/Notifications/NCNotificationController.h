/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCPushNotification.h"
#import "NCTypes.h"

extern NSString * const NCNotificationControllerWillPresentNotification;
extern NSString * const NCLocalNotificationJoinChatNotification;

extern NSString * const NCNotificationActionShareRecording;
extern NSString * const NCNotificationActionDismissRecordingNotification;
extern NSString * const NCNotificationActionReplyToChat;
extern NSString * const NCNotificationActionFederationInvitationAccept;
extern NSString * const NCNotificationActionFederationInvitationReject;

typedef void (^CheckForNewNotificationsCompletionBlock)(NSError *error);
typedef void (^CheckNotificationExistanceCompletionBlock)(NSError *error);

@interface NCNotificationController : NSObject

+ (instancetype)sharedInstance;
- (void)requestAuthorization;
- (void)processBackgroundPushNotification:(NCPushNotification *)pushNotification;
- (void)showLocalNotification:(NCLocalNotificationType)type withUserInfo:(NSDictionary *)userInfo;
- (void)showLocalNotificationForIncomingCallWithPushNotificaion:(NCPushNotification *)pushNotification;
- (void)showIncomingCallForPushNotification:(NCPushNotification *)pushNotification;
- (void)showIncomingCallForOldAccount;
- (void)removeAllNotificationsForAccountId:(NSString *)accountId;
- (void)checkForNewNotificationsWithCompletionBlock:(CheckForNewNotificationsCompletionBlock)block;
- (void)checkNotificationExistanceWithCompletionBlock:(CheckNotificationExistanceCompletionBlock)block;

@end
