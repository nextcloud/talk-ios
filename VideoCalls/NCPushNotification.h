//
//  NCPushNotification.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.11.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NCPushNotificationType) {
    NCPushNotificationTypeUnknown,
    NCPushNotificationTypeCall,
    NCPushNotificationTypeRoom,
    NCPushNotificationTypeChat
};

extern NSString * const kNCPNAppKey;
extern NSString * const kNCPNTypeKey;
extern NSString * const kNCPNSubjectKey;
extern NSString * const kNCPNIdKey;
extern NSString * const kNCPNNotifIdKey;
extern NSString * const kNCPNTypeCallKey;
extern NSString * const kNCPNTypeRoomKey;
extern NSString * const kNCPNTypeChatKey;

extern NSString * const NCPushNotificationJoinChatNotification;
extern NSString * const NCPushNotificationJoinAudioCallAcceptedNotification;
extern NSString * const NCPushNotificationJoinVideoCallAcceptedNotification;

@interface NCPushNotification : NSObject

@property (nonatomic, copy) NSString *app;
@property (nonatomic, assign) NCPushNotificationType type;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *roomToken;
@property (nonatomic, assign) NSInteger roomId;
@property (nonatomic, assign) NSInteger notificationId;
@property (nonatomic, copy) NSString *jsonString;

+ (instancetype)pushNotificationFromDecryptedString:(NSString *)decryptedString;
- (NSString *)bodyForRemoteAlerts;

@end
