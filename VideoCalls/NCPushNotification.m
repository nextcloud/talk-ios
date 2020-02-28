//
//  NCPushNotification.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.11.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCPushNotification.h"

@implementation NCPushNotification

NSString * const kNCPNAppKey            = @"app";
NSString * const kNCPNAppIdKey          = @"spreed";
NSString * const kNCPNTypeKey           = @"type";
NSString * const kNCPNSubjectKey        = @"subject";
NSString * const kNCPNIdKey             = @"id";
NSString * const kNCPNNotifIdKey        = @"nid";
NSString * const kNCPNTypeCallKey       = @"call";
NSString * const kNCPNTypeRoomKey       = @"room";
NSString * const kNCPNTypeChatKey       = @"chat";
NSString * const kNCPNTypeDeleteKey     = @"delete";
NSString * const kNCPNTypeDeleteAllKey  = @"delete-all";

NSString * const NCPushNotificationJoinChatNotification                 = @"NCPushNotificationJoinChatNotification";
NSString * const NCPushNotificationJoinAudioCallAcceptedNotification    = @"NCPushNotificationJoinAudioCallAcceptedNotification";
NSString * const NCPushNotificationJoinVideoCallAcceptedNotification    = @"NCPushNotificationJoinVideoCallAcceptedNotification";


+ (instancetype)pushNotificationFromDecryptedString:(NSString *)decryptedString withAccountId:(NSString *)accountId
{
    if (!decryptedString) {
        return nil;
    }
    
    NSData *data = [decryptedString dataUsingEncoding:NSUTF8StringEncoding];
    id jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    NSString *app = [jsonDict objectForKey:kNCPNAppKey];
    if (![app isEqualToString:kNCPNAppIdKey]) {
        return [self nonTalkPushNotification:jsonDict];
    }
    
    NCPushNotification *pushNotification = [[NCPushNotification alloc] init];
    pushNotification.app = app;
    pushNotification.subject = [jsonDict objectForKey:kNCPNSubjectKey];
    pushNotification.roomToken = [jsonDict objectForKey:kNCPNIdKey];
    pushNotification.roomId = [[jsonDict objectForKey:kNCPNIdKey] integerValue];
    pushNotification.notificationId = [[jsonDict objectForKey:kNCPNNotifIdKey] integerValue];
    
    NSString *type = [jsonDict objectForKey:kNCPNTypeKey];
    pushNotification.type = NCPushNotificationTypeUnknown;
    if ([type isEqualToString:kNCPNTypeCallKey]) {
        pushNotification.type = NCPushNotificationTypeCall;
    } else if ([type isEqualToString:kNCPNTypeRoomKey]) {
        pushNotification.type = NCPushNotificationTypeRoom;
    } else if ([type isEqualToString:kNCPNTypeChatKey]) {
        pushNotification.type = NCPushNotificationTypeChat;
    }
    
    pushNotification.accountId = accountId;
    pushNotification.jsonString = decryptedString;
    
    return pushNotification;
}

+ (instancetype)nonTalkPushNotification:(id)jsonNotification
{
    NCPushNotification *pushNotification = [[NCPushNotification alloc] init];
    if ([jsonNotification objectForKey:kNCPNTypeDeleteKey]) {
        pushNotification.notificationId = [[jsonNotification objectForKey:kNCPNNotifIdKey] integerValue];
        pushNotification.type = NCPushNotificationTypeDelete;
    } else if ([jsonNotification objectForKey:kNCPNTypeDeleteAllKey]) {
        pushNotification.type = NCPushNotificationTypeDeleteAll;
    } else {
        return nil;
    }
    return pushNotification;
}

- (NSString *)bodyForRemoteAlerts
{
    switch (_type) {
        case NCPushNotificationTypeCall:
            return [NSString stringWithFormat:@"📞 %@", _subject];
            break;
        case NCPushNotificationTypeRoom:
            return [NSString stringWithFormat:@"🔔 %@", _subject];
            break;
        case NCPushNotificationTypeChat:
            return [NSString stringWithFormat:@"💬 %@", _subject];
            break;
        default:
            return _subject;
            break;
    }
}

@end
