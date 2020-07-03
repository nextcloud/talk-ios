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

- (void)processBackgroundPushNotification:(NCPushNotification *)pushNotification
{
    if (pushNotification) {
        NSInteger notificationId = pushNotification.notificationId;
        if (pushNotification.type == NCPushNotificationTypeDelete) {
            [self removeNotificationWithNotificationId:notificationId forAccountId:pushNotification.accountId];
        } else if (pushNotification.type == NCPushNotificationTypeDeleteAll) {
            [self removeAllNotificationsForAccountId:pushNotification.accountId];
        } else {
            NSLog(@"Push Notification of an unknown type received");
        }
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
}

- (void)showIncomingCallForPushNotification:(NCPushNotification *)pushNotification withServerNotification:(NCNotification *)serverNotification
{
    NSString *roomToken = serverNotification.objectId;
    NSString *displayName = serverNotification.callDisplayName;
    // Set active account
    [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:pushNotification.accountId];
    // Present call
    [[CallKitManager sharedInstance] reportIncomingCallForRoom:roomToken withDisplayName:displayName forAccountId:pushNotification.accountId];
}

- (void)updateAppIconBadgeNumber
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].applicationIconBadgeNumber = [[NCDatabaseManager sharedInstance] numberOfUnreadNotifications];
    });
}

- (void)removeAllNotificationsForAccountId:(NSString *)accountId
{
    // Check in pending notifications
    [_notificationCenter getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
        for (UNNotificationRequest *notificationRequest in requests) {
            NSString *notificationAccountId = [notificationRequest.content.userInfo objectForKey:@"accountId"];
            if (notificationAccountId && [notificationAccountId isEqualToString:accountId]) {
                [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notificationRequest.identifier]];
            }
        }
    }];
    // Check in delivered notifications
    [_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        for (UNNotification *notification in notifications) {
            NSString *notificationAccountId = [notification.request.content.userInfo objectForKey:@"accountId"];
            if (notificationAccountId && [notificationAccountId isEqualToString:accountId]) {
                [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
            }
        }
    }];
    
    [[NCDatabaseManager sharedInstance] resetUnreadBadgeNumberForAccountId:accountId];
    [self updateAppIconBadgeNumber];
}

- (void)removeNotificationWithNotificationId:(NSInteger)notificationId forAccountId:(NSString *)accountId
{
    // Check in pending notifications
    [_notificationCenter getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
        for (UNNotificationRequest *notificationRequest in requests) {
            NSString *notificationString = [notificationRequest.content.userInfo objectForKey:@"pushNotification"];
            NSString *notificationAccountId = [notificationRequest.content.userInfo objectForKey:@"accountId"];
            NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:notificationString withAccountId:notificationAccountId];
            if (pushNotification && [pushNotification.accountId isEqualToString:accountId] && pushNotification.notificationId == notificationId) {
                [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notificationRequest.identifier]];
                [[NCDatabaseManager sharedInstance] decreaseUnreadBadgeNumberForAccountId:accountId];
            }
        }
    }];
    // Check in delivered notifications
    [_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        for (UNNotification *notification in notifications) {
            NSString *notificationString = [notification.request.content.userInfo objectForKey:@"pushNotification"];
            NSString *notificationAccountId = [notification.request.content.userInfo objectForKey:@"accountId"];
            NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:notificationString withAccountId:notificationAccountId];
            if (pushNotification && [pushNotification.accountId isEqualToString:accountId] && pushNotification.notificationId == notificationId) {
                [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
                [[NCDatabaseManager sharedInstance] decreaseUnreadBadgeNumberForAccountId:accountId];
            }
        }
    }];
    
    [self updateAppIconBadgeNumber];
}

#pragma mark - UNUserNotificationCenter delegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    // Called when a notification is delivered to a foreground app.
    [[NSNotificationCenter defaultCenter] postNotificationName:NCNotificationControllerWillPresentNotification object:self userInfo:nil];
    completionHandler(UNNotificationPresentationOptionAlert);
    
    // Remove the notification from Notification Center if it is from the active account
    NSString *notificationAccountId = [notification.request.content.userInfo objectForKey:@"accountId"];
    if (notificationAccountId && [[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:notificationAccountId]) {
        [self removeAllNotificationsForAccountId:notificationAccountId];
    }
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
    if (notificationAccountId && ![[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:notificationAccountId]) {
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
