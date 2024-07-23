/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NCNotificationType) {
    kNCNotificationTypeRoom = 0,
    kNCNotificationTypeChat,
    kNCNotificationTypeCall,
    kNCNotificationTypeRecording,
    kNCNotificationTypeFederation
};

@interface NCNotification : NSObject

@property (nonatomic, assign) NSInteger notificationId;
@property (nonatomic, strong) NSString *app;
@property (nonatomic, strong) NSString *objectId;
@property (nonatomic, strong) NSString *objectType;
@property (nonatomic, strong) NSString *subject;
@property (nonatomic, strong) NSString *subjectRich;
@property (nonatomic, strong) NSDictionary *subjectRichParameters;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *messageRich;
@property (nonatomic, strong) NSDictionary *messageRichParameters;
@property (nonatomic, strong) NSArray *actions;
@property (nonatomic, strong) NSDate *datetime;

+ (instancetype)notificationWithDictionary:(NSDictionary *)notificationDict;
- (NCNotificationType)notificationType;
- (NSString *)chatMessageAuthor;
- (NSString *)chatMessageTitle;
- (NSString *)roomToken;
- (NSArray *)notificationActions;

@end
