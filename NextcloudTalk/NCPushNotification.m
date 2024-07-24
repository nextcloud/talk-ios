/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCPushNotification.h"

@implementation NCPushNotification

NSString * const kNCPNAppKey                    = @"app";
NSString * const kNCPNAppIdKey                  = @"spreed";
NSString * const kNCPNTypeKey                   = @"type";
NSString * const kNCPNSubjectKey                = @"subject";
NSString * const kNCPNIdKey                     = @"id";
NSString * const kNCPNNotifIdKey                = @"nid";
NSString * const kNCPNNotifIdsKey               = @"nids";
NSString * const kNCPNTypeCallKey               = @"call";
NSString * const kNCPNTypeRoomKey               = @"room";
NSString * const kNCPNTypeChatKey               = @"chat";
NSString * const kNCPNTypeDeleteKey             = @"delete";
NSString * const kNCPNTypeDeleteAllKey          = @"delete-all";
NSString * const kNCPNTypeDeleteMultipleKey     = @"delete-multiple";
NSString * const kNCPNTypeRecording             = @"recording";
NSString * const kNCPNTypeFederation            = @"remote_talk_share";
NSString * const kNCPNTypeReminder              = @"reminder";
NSString * const kNCPNAppIdAdminNotificationKey = @"admin_notification_talk";

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
        return [self nonTalkPushNotification:jsonDict withAccountId:accountId];
    }
    
    NCPushNotification *pushNotification = [[NCPushNotification alloc] init];
    pushNotification.app = app;
    pushNotification.subject = [jsonDict objectForKey:kNCPNSubjectKey];
    pushNotification.roomToken = [jsonDict objectForKey:kNCPNIdKey];
    pushNotification.notificationId = [[jsonDict objectForKey:kNCPNNotifIdKey] integerValue];
    
    NSString *type = [jsonDict objectForKey:kNCPNTypeKey];
    pushNotification.type = NCPushNotificationTypeUnknown;
    if ([type isEqualToString:kNCPNTypeCallKey]) {
        pushNotification.type = NCPushNotificationTypeCall;
    } else if ([type isEqualToString:kNCPNTypeRoomKey]) {
        pushNotification.type = NCPushNotificationTypeRoom;
    } else if ([type isEqualToString:kNCPNTypeChatKey]) {
        pushNotification.type = NCPushNotificationTypeChat;
    } else if ([type isEqualToString:kNCPNTypeRecording]) {
        pushNotification.type = NCPushNotificationTypeRecording;
    } else if ([type isEqualToString:kNCPNTypeFederation]) {
        pushNotification.type = NCPUshNotificationTypeFederation;
    } else if ([type isEqualToString:kNCPNTypeReminder]) {
        pushNotification.type = NCPushNotificationTypeReminder;
    }
    
    pushNotification.accountId = accountId;
    pushNotification.jsonString = decryptedString;
    
    return pushNotification;
}

+ (instancetype)nonTalkPushNotification:(id)jsonNotification withAccountId:(NSString *)accountId
{
    NCPushNotification *pushNotification = [[NCPushNotification alloc] init];
    if ([jsonNotification objectForKey:kNCPNTypeDeleteKey]) {
        pushNotification.notificationId = [[jsonNotification objectForKey:kNCPNNotifIdKey] integerValue];
        pushNotification.type = NCPushNotificationTypeDelete;
    } else if ([jsonNotification objectForKey:kNCPNTypeDeleteAllKey]) {
        pushNotification.type = NCPushNotificationTypeDeleteAll;
    } else if ([jsonNotification objectForKey:kNCPNTypeDeleteMultipleKey]) {
        pushNotification.notificationIds = [jsonNotification objectForKey:kNCPNNotifIdsKey];
        pushNotification.type = NCPushNotificationTypeDeleteMultiple;
    } else {
        NSString *app = [jsonNotification objectForKey:kNCPNAppKey];
        
        if (![app isEqualToString:kNCPNAppIdAdminNotificationKey]) {
            return nil;
        }
    
        pushNotification.subject = [jsonNotification objectForKey:kNCPNSubjectKey];
        pushNotification.notificationId = [[jsonNotification objectForKey:kNCPNNotifIdKey] integerValue];
        pushNotification.type = NCPushNotificationTypeAdminNotification;
    }
    
    pushNotification.accountId = accountId;
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
