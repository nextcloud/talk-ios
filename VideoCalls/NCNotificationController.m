//
//  NCNotificationController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.10.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCNotificationController.h"
#import <UserNotifications/UserNotifications.h>

#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCNotification.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "CallKitManager.h"

NSString * const NCNotificationControllerWillPresentNotification    = @"NCNotificationControllerWillPresentNotification";
NSString * const NCLocalNotificationJoinChatNotification            = @"NCLocalNotificationJoinChatNotification";

@interface NCNotificationController () <UNUserNotificationCenterDelegate>

@property (nonatomic, strong) UNUserNotificationCenter *notificationCenter;
@property (nonatomic, strong) NSMutableDictionary *serverNotificationsAttempts; // notificationId -> get attempts

@end

@implementation NCNotificationController

+ (NCNotificationController *)sharedInstance
{
    static dispatch_once_t once;
    static NCNotificationController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
        _notificationCenter.delegate = self;
        _serverNotificationsAttempts = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)requestAuthorization
{
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    [_notificationCenter requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (granted) {
            NSLog(@"User notifications permission granted.");
        } else {
            NSLog(@"User notifications permission denied.");
        }
    }];
}

- (void)processIncomingPushNotification:(NCPushNotification *)pushNotification
{
    if (pushNotification) {
        NSInteger notificationId = pushNotification.notificationId;
        if (pushNotification.type == NCPushNotificationTypeDelete) {
            [self removeNotificationWithNotificationId:notificationId];
        } else if (pushNotification.type == NCPushNotificationTypeDeleteAll) {
            [self cleanAllNotifications];
        } else {
            [self handlePushNotification:pushNotification];
        }
    }
}

- (void)showLocalNotificationForPushNotification:(NCPushNotification *)pushNotification withServerNotification:(NCNotification *)serverNotification
{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.body = pushNotification.bodyForRemoteAlerts;
    content.threadIdentifier = pushNotification.roomToken;
    content.sound = [UNNotificationSound defaultSound];
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:pushNotification.jsonString forKey:@"pushNotification"];
    [userInfo setObject:pushNotification.accountId forKey:@"accountId"];
    content.userInfo = userInfo;
    
    if (serverNotification) {
        content.threadIdentifier = serverNotification.objectId;
        if (serverNotification.notificationType == kNCNotificationTypeChat) {
            content.title = serverNotification.chatMessageTitle;
            content.body = serverNotification.message;
            if (@available(iOS 12.0, *)) {
                content.summaryArgument = serverNotification.chatMessageAuthor;
            }
        }
    }
    
    NSString *identifier = [NSString stringWithFormat:@"Notification-%ld", (long)pushNotification.notificationId];
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    [_notificationCenter addNotificationRequest:request withCompletionHandler:nil];
    
    [self updateAppIconBadgeNumber:1];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:NCNotificationControllerWillPresentNotification object:self userInfo:nil];
}

- (void)handlePushNotification:(NCPushNotification *)pushNotification
{
    NSInteger notificationId = pushNotification.notificationId;
    NSInteger retryAttempts = [[_serverNotificationsAttempts objectForKey:@(notificationId)] integerValue];
    if (retryAttempts < 3 && notificationId) {
        retryAttempts += 1;
        [_serverNotificationsAttempts setObject:@(retryAttempts) forKey:@(notificationId)];
        TalkAccount *talkAccount = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:pushNotification.accountId];
        [[NCAPIController sharedInstance] getServerNotification:notificationId forAccount:talkAccount withCompletionBlock:^(NSDictionary *notification, NSError *error, NSInteger statusCode) {
            if (statusCode == 404) {
                // Notification has been treated/deleted in another device
                return;
            }
            if (!error) {
                NCNotification *serverNotification = [NCNotification notificationWithDictionary:notification];
                if (serverNotification) {
                    if (serverNotification.notificationType == kNCNotificationTypeChat) {
                        [self showLocalNotificationForPushNotification:pushNotification withServerNotification:serverNotification];
                    } else if (serverNotification.notificationType == kNCNotificationTypeCall) {
                        NSString *callType = [[serverNotification.subjectRichParameters objectForKey:@"call"] objectForKey:@"call-type"];
                        if ([CallKitManager isCallKitAvailable] && ![[CallKitManager sharedInstance] currentCallUUID] && [callType isEqualToString:@"one2one"]) {
                            [self showIncomingCallForPushNotification:pushNotification withServerNotification:serverNotification];
                        } else {
                            [self showLocalNotificationForPushNotification:pushNotification withServerNotification:serverNotification];
                        }
                    } else if (serverNotification.notificationType == kNCNotificationTypeRoom) {
                        NSString *callType = [[serverNotification.subjectRichParameters objectForKey:@"call"] objectForKey:@"call-type"];
                        // Only present invitation notifications for group conversations
                        if (![callType isEqualToString:@"one2one"]) {
                            [self showLocalNotificationForPushNotification:pushNotification withServerNotification:serverNotification];
                        }
                    }
                }
            } else {
                NSLog(@"Could not retrieve server notification. Attempt:%ld", (long)retryAttempts);
                [self handlePushNotification:pushNotification];
            }
        }];
    } else {
        [self showLocalNotificationForPushNotification:pushNotification withServerNotification:nil];
    }
}

- (void)showLocalNotification:(NCLocalNotificationType)type withUserInfo:(NSDictionary *)userInfo
{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    
    switch (type) {
        case kNCLocalNotificationTypeMissedCall:
            {
                content.body = [NSString stringWithFormat:@"☎️ Missed call from %@", [userInfo objectForKey:@"displayName"]];
                content.userInfo = userInfo;
            }
            break;
            
        default:
            break;
    }
    
    NSString *identifier = [NSString stringWithFormat:@"Notification-%f", [[NSDate date] timeIntervalSince1970]];
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    [_notificationCenter addNotificationRequest:request withCompletionHandler:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCNotificationControllerWillPresentNotification object:self userInfo:nil];
    
    [self updateAppIconBadgeNumber:1];
}

- (void)showIncomingCallForPushNotification:(NCPushNotification *)pushNotification withServerNotification:(NCNotification *)serverNotification
{
    NSString *roomToken = serverNotification.objectId;
    NSString *displayName = serverNotification.callDisplayName;
    // Set active account
    [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:pushNotification.accountId];
    // Present call
    [[CallKitManager sharedInstance] reportIncomingCallForRoom:roomToken withDisplayName:displayName];
}

- (void)updateAppIconBadgeNumber:(NSInteger)update
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            [UIApplication sharedApplication].applicationIconBadgeNumber += update;
        }
    });
}

- (void)cleanAllNotifications
{
    [_notificationCenter removeAllDeliveredNotifications];
    [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
}

- (void)removeNotificationWithNotificationId:(NSInteger)notificationId
{
    NSString *identifier = [NSString stringWithFormat:@"Notification-%ld", (long)notificationId];
    // Check in pending notifications
    [_notificationCenter getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
        for (UNNotificationRequest *notificationRequest in requests) {
            if ([notificationRequest.identifier isEqualToString:identifier]) {
                [_notificationCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];
                [self updateAppIconBadgeNumber:-1];
            }
        }
    }];
    // Check in delivered notifications
    [_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        for (UNNotification *notification in notifications) {
            if ([notification.request.identifier isEqualToString:identifier]) {
                [_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];
                [self updateAppIconBadgeNumber:-1];
            }
        }
    }];
}

#pragma mark - UNUserNotificationCenter delegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    //Called when a notification is delivered to a foreground app.
    completionHandler(UNNotificationPresentationOptionAlert);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler
{
    if ([NCRoomsManager sharedInstance].callViewController) {
        completionHandler();
        return;
    }
    
    UNNotificationRequest *notificationRequest = response.notification.request;
    NCLocalNotificationType localNotificationType = (NCLocalNotificationType)[[notificationRequest.content.userInfo objectForKey:@"localNotificationType"] integerValue];
    NSString *notificationString = [notificationRequest.content.userInfo objectForKey:@"pushNotification"];
    NSString *notificationAccountId = [notificationRequest.content.userInfo objectForKey:@"accountId"];
    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:notificationString withAccountId:notificationAccountId];
    
    // Change account if notification is from another account
    if (![[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:notificationAccountId]) {
        // Leave chat before changing accounts
        if ([[NCRoomsManager sharedInstance] chatViewController]) {
            [[[NCRoomsManager sharedInstance] chatViewController] leaveChat];
        }
        // Set notification account active
        [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:notificationAccountId];
    }
    
    // Handle notification response
    if (pushNotification) {
        [self handlePushNotificationResponse:pushNotification withCompletionHandler:completionHandler];
    } else if (localNotificationType > 0) {
        [self handleLocalNotificationResponse:notificationRequest.content.userInfo withCompletionHandler:completionHandler];
    }
}

- (void)handlePushNotificationResponse:(NCPushNotification *)pushNotification withCompletionHandler:(void (^)(void))completionHandler
{
    if (pushNotification) {
        switch (pushNotification.type) {
            case NCPushNotificationTypeCall:
            {
                [[NCUserInterfaceController sharedInstance] presentAlertForPushNotification:pushNotification];
            }
                break;
            case NCPushNotificationTypeRoom:
            case NCPushNotificationTypeChat:
            {
                [[NCUserInterfaceController sharedInstance] presentChatForPushNotification:pushNotification];
            }
                break;
            default:
                break;
        }
    }
    
    completionHandler();
}

- (void)handleLocalNotificationResponse:(NSDictionary *)notificationUserInfo withCompletionHandler:(void (^)(void))completionHandler
{
    NCLocalNotificationType localNotificationType = (NCLocalNotificationType)[[notificationUserInfo objectForKey:@"localNotificationType"] integerValue];
    if (localNotificationType > 0) {
        switch (localNotificationType) {
            case kNCLocalNotificationTypeMissedCall:
            {
                [[NCUserInterfaceController sharedInstance] presentChatForLocalNotification:notificationUserInfo];
            }
                break;
            default:
                break;
        }
    }
    
    completionHandler();
}

@end
