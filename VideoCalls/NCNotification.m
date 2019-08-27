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

- (NSString *)chatMessageAuthor
{
    NSString *author = [[_subjectRichParameters objectForKey:@"user"] objectForKey:@"name"];
    NSString *guest = [[_subjectRichParameters objectForKey:@"guest"] objectForKey:@"name"];
    if (guest) {
        author = [NSString stringWithFormat:@"%@ (%@)", guest, @"guest"];
    }
    return author ? author : @"Guest";
}

- (NSString *)chatMessageTitle
{
    NSString *title = [self chatMessageAuthor];
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

- (NSString *)callDisplayName
{
    NSString *displayName = [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"name"];
    NSString *callType = [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"call-type"];
    if ([callType isEqualToString:@"one2one"]) {
        displayName = [[_subjectRichParameters objectForKey:@"user"] objectForKey:@"name"];
    }
    if (!displayName || [displayName isEqualToString:@"a conversation"]) {
        displayName = @"Incoming call";
    }
    return displayName;
}

- (NSArray *)getParametersFromRichText:(NSString *)text
{
    NSError *error = nil;
    NSRegularExpression *parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^}]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    return [parameterRegex matchesInString:text options:0 range:NSMakeRange(0, [text length])];
}

@end
