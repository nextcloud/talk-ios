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

#import "NCPushNotification.h"

extern NSString * const NCNotificationControllerWillPresentNotification;
extern NSString * const NCLocalNotificationJoinChatNotification;

extern NSString * const NCNotificationActionShareRecording;
extern NSString * const NCNotificationActionDismissRecordingNotification;
extern NSString * const NCNotificationActionReplyToChat;

typedef void (^CheckForNewNotificationsCompletionBlock)(NSError *error);

typedef enum {
    kNCLocalNotificationTypeMissedCall = 1,
    kNCLocalNotificationTypeCancelledCall,
    kNCLocalNotificationTypeFailedSendChat,
    kNCLocalNotificationTypeCallFromOldAccount,
    kNCLocalNotificationTypeChatNotification,
    kNCLocalNotificationTypeFailedToShareRecording
} NCLocalNotificationType;

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

@end
