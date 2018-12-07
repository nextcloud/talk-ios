//
//  NCNotification.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCNotification.h"

@implementation NCNotification

+ (instancetype)notificationWithDictionary:(NSDictionary *)notificationDict
{
    if (!notificationDict || ![notificationDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NCNotification *notification = [[NCNotification alloc] init];
    notification.notificationId = [[notificationDict objectForKey:@"notification_id"] integerValue];
    notification.objectId = [notificationDict objectForKey:@"object_id"];
    notification.objectType = [notificationDict objectForKey:@"object_type"];
    notification.subject = [notificationDict objectForKey:@"subject"];
    notification.subjectRich = [notificationDict objectForKey:@"subjectRich"];
    notification.subjectRichParameters = [notificationDict objectForKey:@"subjectRichParameters"];
    notification.message = [notificationDict objectForKey:@"message"];
    notification.messageRich = [notificationDict objectForKey:@"messageRich"];
    notification.messageRichParameters = [notificationDict objectForKey:@"messageRichParameters"];
    
    if (![notification.subjectRichParameters isKindOfClass:[NSDictionary class]]) {
        notification.subjectRichParameters = @{};
    }
    
    if (![notification.messageRichParameters isKindOfClass:[NSDictionary class]]) {
        notification.messageRichParameters = @{};
    }
    
    return notification;
}

- (NCNotificationType)notificationType
{
    NCNotificationType type = kNCNotificationTypeRoom;
    if ([_objectType isEqualToString:@"chat"]) {
        type = kNCNotificationTypeChat;
    } else if ([_objectType isEqualToString:@"call"]) {
        type = kNCNotificationTypeCall;
    }
    return type;
}

- (NSString *)chatMessageTitle
{
    NSString *title = [[_subjectRichParameters objectForKey:@"user"] objectForKey:@"name"];
    // Check if the room has a name
    NSArray *parameters = [self getParametersFromRichText:_subjectRich];
    for (int i = 0; i < parameters.count; i++) {
        NSTextCheckingResult *match = [parameters objectAtIndex:i];
        NSString* parameter = [_subjectRich substringWithRange:match.range];
        NSString *parameterKey = [[parameter stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"}" withString:@""];
        if ([parameterKey isEqualToString:@"call"]) {
            title = [title stringByAppendingString:[NSString stringWithFormat:@" @ %@", [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"name"]]];
        }
    }
    return title;
}

- (NSArray *)getParametersFromRichText:(NSString *)text
{
    NSError *error = nil;
    NSRegularExpression *parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^}]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    return [parameterRegex matchesInString:text options:0 range:NSMakeRange(0, [text length])];
}

@end
