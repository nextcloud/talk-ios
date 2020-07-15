//
//  NCNotificationController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCPushNotification.h"

extern NSString * const NCNotificationControllerWillPresentNotification;
extern NSString * const NCLocalNotificationJoinChatNotification;

typedef enum {
    kNCLocalNotificationTypeMissedCall = 1,
    kNCLocalNotificationTypeCancelledCall
} NCLocalNotificationType;

@interface NCNotificationController : NSObject

+ (instancetype)sharedInstance;
- (void)requestAuthorization;
- (void)processBackgroundPushNotification:(NCPushNotification *)pushNotification;
- (void)showLocalNotification:(NCLocalNotificationType)type withUserInfo:(NSDictionary *)userInfo;
- (void)showLocalNotificationForIncomingCallWithPushNotificaion:(NCPushNotification *)pushNotification;
- (void)showIncomingCallForPushNotification:(NCPushNotification *)pushNotification;
- (void)removeAllNotificationsForAccountId:(NSString *)accountId;

@end
