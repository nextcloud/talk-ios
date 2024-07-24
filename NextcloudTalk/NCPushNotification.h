/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NCPushNotificationType) {
    NCPushNotificationTypeUnknown,
    NCPushNotificationTypeCall,
    NCPushNotificationTypeRoom,
    NCPushNotificationTypeChat,
    NCPushNotificationTypeDelete,
    NCPushNotificationTypeDeleteAll,
    NCPushNotificationTypeDeleteMultiple,
    NCPushNotificationTypeAdminNotification,
    NCPushNotificationTypeRecording,
    NCPUshNotificationTypeFederation,
    NCPushNotificationTypeReminder
};

extern NSString * const kNCPNAppKey;
extern NSString * const kNCPNAppIdKey;
extern NSString * const kNCPNTypeKey;
extern NSString * const kNCPNSubjectKey;
extern NSString * const kNCPNIdKey;
extern NSString * const kNCPNNotifIdKey;
extern NSString * const kNCPNTypeCallKey;
extern NSString * const kNCPNTypeRoomKey;
extern NSString * const kNCPNTypeChatKey;
extern NSString * const kNCPNTypeRecording;
extern NSString * const kNCPNTypeReminder;

extern NSString * const NCPushNotificationJoinChatNotification;
extern NSString * const NCPushNotificationJoinAudioCallAcceptedNotification;
extern NSString * const NCPushNotificationJoinVideoCallAcceptedNotification;

@interface NCPushNotification : NSObject

@property (nonatomic, copy) NSString *app;
@property (nonatomic, assign) NCPushNotificationType type;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *roomToken;
@property (nonatomic, assign) NSInteger notificationId;
@property (nonatomic, strong) NSArray *notificationIds;
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *jsonString;
@property (nonatomic, copy) NSString *responseUserText;

+ (instancetype)pushNotificationFromDecryptedString:(NSString *)decryptedString withAccountId:(NSString *)accountId;
- (NSString *)bodyForRemoteAlerts;

@end
