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

typedef NS_ENUM(NSInteger, NCPushNotificationType) {
    NCPushNotificationTypeUnknown,
    NCPushNotificationTypeCall,
    NCPushNotificationTypeRoom,
    NCPushNotificationTypeChat,
    NCPushNotificationTypeDelete,
    NCPushNotificationTypeDeleteAll,
    NCPushNotificationTypeDeleteMultiple,
    NCPushNotificationTypeAdminNotification
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
@property (nonatomic, strong) NSArray *notificationIds;
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *jsonString;
@property (nonatomic, copy) NSString *responseUserText;

+ (instancetype)pushNotificationFromDecryptedString:(NSString *)decryptedString withAccountId:(NSString *)accountId;
- (NSString *)bodyForRemoteAlerts;

@end
