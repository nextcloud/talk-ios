//
//  NCNotification.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum NCNotificationType {
    kNCNotificationTypeRoom = 0,
    kNCNotificationTypeChat,
    kNCNotificationTypeCall
} NCNotificationType;

@interface NCNotification : NSObject

@property (nonatomic, assign) NSInteger notificationId;
@property (nonatomic, strong) NSString *objectId;
@property (nonatomic, strong) NSString *objectType;
@property (nonatomic, strong) NSString *subject;
@property (nonatomic, strong) NSString *subjectRich;
@property (nonatomic, strong) NSDictionary *subjectRichParameters;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *messageRich;
@property (nonatomic, strong) NSDictionary *messageRichParameters;

+ (instancetype)notificationWithDictionary:(NSDictionary *)notificationDict;
- (NCNotificationType)notificationType;
- (NSString *)chatMessageTitle;

@end
