/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCNotificationController.h"

#import <UserNotifications/UserNotifications.h>

#import "CallKitManager.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCIntentController.h"
#import "NCNotification.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUserStatus.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCNotificationControllerWillPresentNotification    = @"NCNotificationControllerWillPresentNotification";
NSString * const NCLocalNotificationJoinChatNotification            = @"NCLocalNotificationJoinChatNotification";

NSString * const NCNotificationActionShareRecording                 = @"SHARE_RECORDING";
NSString * const NCNotificationActionDismissRecordingNotification   = @"DISMISS_RECORDING_NOTIFICATION";
NSString * const NCNotificationActionReplyToChat                    = @"REPLY_CHAT";
NSString * const NCNotificationActionFederationInvitationAccept     = @"ACCEPT_FEDERATION_INVITATION";
NSString * const NCNotificationActionFederationInvitationReject     = @"REJECT_FEDERATION_INVITATION";

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
    if (!pushNotification) {
        return;
    }

    if (pushNotification.type == NCPushNotificationTypeDelete) {
        NSNumber *notificationId = @(pushNotification.notificationId);
        [self removeNotificationWithNotificationIds:@[notificationId] forAccountId:pushNotification.accountId];
    } else if (pushNotification.type == NCPushNotificationTypeDeleteAll) {
        [self removeAllNotificationsForAccountId:pushNotification.accountId];
    } else if (pushNotification.type == NCPushNotificationTypeDeleteMultiple) {
        [self removeNotificationWithNotificationIds:pushNotification.notificationIds forAccountId:pushNotification.accountId];
    } else {
        NSLog(@"Push Notification of an unknown type received");
    }
}

- (void)showLocalNotification:(NCLocalNotificationType)type withUserInfo:(NSDictionary *)userInfo
{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    
    switch (type) {
        case kNCLocalNotificationTypeMissedCall:
        {
            NSString *missedCallString = NSLocalizedString(@"Missed call from", nil);
            content.body = [NSString stringWithFormat:@"☎️ %@ %@", missedCallString, [userInfo objectForKey:@"displayName"]];
            content.userInfo = userInfo;
        }
            break;
            
        case kNCLocalNotificationTypeCancelledCall:
        {
            NSString *cancelledCallString = NSLocalizedString(@"Cancelled call from another account", nil);
            content.body = [NSString stringWithFormat:@"☎️ %@", cancelledCallString];
            content.userInfo = userInfo;
        }
            break;
            
        case kNCLocalNotificationTypeFailedSendChat:
        {
            NSString *failedSendChatString = NSLocalizedString(@"Failed to send message", nil);
            content.body = [NSString stringWithFormat:@"%@", failedSendChatString];
            content.userInfo = userInfo;
        }
            break;

        case kNCLocalNotificationTypeCallFromOldAccount:
        {
            NSString *receivedCallFromOldAccountString = NSLocalizedString(@"Received call from an old account", nil);
            content.body = [NSString stringWithFormat:@"%@", receivedCallFromOldAccountString];
            content.userInfo = userInfo;
        }
            break;

        case kNCLocalNotificationTypeFailedToShareRecording:
        {
            NSString *failedToShareRecordingString = NSLocalizedString(@"Failed to share recording", nil);
            content.body = [NSString stringWithFormat:@"%@", failedToShareRecordingString];
            content.userInfo = userInfo;
        }
            break;

        case kNCLocalNotificationTypeFailedToAcceptInvitation:
        {
            NSString *failedToAcceptInvitationString = NSLocalizedString(@"Failed to accept invitation", nil);
            content.body = [NSString stringWithFormat:@"%@", failedToAcceptInvitationString];
            content.userInfo = userInfo;
        }
            break;

        case kNCLocalNotificationTypeRecordingConsentRequired:
        {
            NSString *consentRequiredString = NSLocalizedString(@"Recording consent required for joining the call", nil);
            content.body = [NSString stringWithFormat:@"⚠️ %@ %@", consentRequiredString, [userInfo objectForKey:@"displayName"]];
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
    
    NSString *accountId = [userInfo objectForKey:@"accountId"];
    [[NCDatabaseManager sharedInstance] increaseUnreadBadgeNumberForAccountId:accountId];
    [self updateAppIconBadgeNumber];
}

- (void)showLocalNotificationForIncomingCallWithPushNotificaion:(NCPushNotification *)pushNotification
{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.body = pushNotification.bodyForRemoteAlerts;
    content.threadIdentifier = pushNotification.roomToken;
    content.sound = [UNNotificationSound defaultSound];
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:pushNotification.jsonString forKey:@"pushNotification"];
    [userInfo setObject:pushNotification.accountId forKey:@"accountId"];
    [userInfo setObject:@(pushNotification.notificationId) forKey:@"notificationId"];
    content.userInfo = userInfo;
    
    NSString *identifier = [NSString stringWithFormat:@"Notification-%f", [[NSDate date] timeIntervalSince1970]];
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    [_notificationCenter addNotificationRequest:request withCompletionHandler:nil];
    
    [[NCDatabaseManager sharedInstance] increaseUnreadBadgeNumberForAccountId:pushNotification.accountId];
    [self updateAppIconBadgeNumber];
}

- (void)showIncomingCallForPushNotification:(NCPushNotification *)pushNotification
{
    if ([CallKitManager isCallKitAvailable]) {
        [[CallKitManager sharedInstance] reportIncomingCall:pushNotification.roomToken withDisplayName:@"Incoming call" forAccountId:pushNotification.accountId];
    } else {
        [[CallKitManager sharedInstance] reportIncomingCallForNonCallKitDevicesWithPushNotification:pushNotification];
    }
}

- (void)showIncomingCallForOldAccount
{
    [[CallKitManager sharedInstance] reportIncomingCallForOldAccount];
}

- (void)showLocalNotificationForChatNotification:(NCNotification *)notification forAccountId:(NSString *)accountId
{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = notification.chatMessageTitle;
    content.body = notification.message;
    content.summaryArgument = notification.chatMessageAuthor;
    content.threadIdentifier = notification.roomToken;
    content.sound = [UNNotificationSound defaultSound];
    
    // Currently not supported for local notifications
    //content.categoryIdentifier = @"CATEGORY_CHAT";
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:notification.roomToken forKey:@"roomToken"];
    [userInfo setObject:accountId forKey:@"accountId"];
    [userInfo setObject:@(notification.notificationId) forKey:@"notificationId"];
    [userInfo setValue:@(kNCLocalNotificationTypeChatNotification) forKey:@"localNotificationType"];
    content.userInfo = userInfo;

    NSString *identifier = [NSString stringWithFormat:@"ChatNotification-%ld", notification.notificationId];
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
    [_notificationCenter addNotificationRequest:request withCompletionHandler:nil];

    [[NCDatabaseManager sharedInstance] increaseUnreadBadgeNumberForAccountId:accountId];
    [self updateAppIconBadgeNumber];
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
                [self->_notificationCenter removePendingNotificationRequestsWithIdentifiers:@[notificationRequest.identifier]];
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

- (void)removeNotificationWithNotificationIds:(NSArray *)notificationIds forAccountId:(NSString *)accountId
{
    if (!notificationIds) {
        return;
    }
    
    void(^removeNotification)(UNNotificationRequest *, BOOL) = ^(UNNotificationRequest *notificationRequest, BOOL isPending) {
        NSString *notificationAccountId = [notificationRequest.content.userInfo objectForKey:@"accountId"];
        NSInteger notificationId = [[notificationRequest.content.userInfo objectForKey:@"notificationId"] integerValue];

        if (![notificationAccountId isEqualToString:accountId]) {
            return;
        }

        if ([notificationIds containsObject:@(notificationId)]) {
            if (isPending) {
                [self->_notificationCenter removePendingNotificationRequestsWithIdentifiers:@[notificationRequest.identifier]];
            } else {
                [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notificationRequest.identifier]];
            }

            [[NCDatabaseManager sharedInstance] decreaseUnreadBadgeNumberForAccountId:accountId];
        }
    };

    __block BOOL expired = NO;
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"decreaseUnreadBadgeNumberForAccountId" expirationHandler:^(BGTaskHelper *task) {
        expired = YES;
    }];

    dispatch_group_t notificationsGroup = dispatch_group_create();

    dispatch_group_enter(notificationsGroup);
    // Check in pending notifications
    [_notificationCenter getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
        for (UNNotificationRequest *notificationRequest in requests) {
            if (expired) {
                dispatch_group_leave(notificationsGroup);
                return;
            }
            removeNotification(notificationRequest, YES);
        }

        [self updateAppIconBadgeNumber];
        dispatch_group_leave(notificationsGroup);
    }];

    dispatch_group_enter(notificationsGroup);
    // Check in delivered notifications
    [_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        for (UNNotification *notification in notifications) {
            if (expired) {
                dispatch_group_leave(notificationsGroup);
                return;
            }
            removeNotification(notification.request, NO);
        }

        [self updateAppIconBadgeNumber];
        dispatch_group_leave(notificationsGroup);
    }];

    dispatch_group_notify(notificationsGroup, dispatch_get_main_queue(), ^{
        [bgTask stopBackgroundTask];
    });
}

- (void)checkForNewNotificationsWithCompletionBlock:(CheckForNewNotificationsCompletionBlock)block
{
    dispatch_group_t notificationsGroup = dispatch_group_create();

    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];

        if (!serverCapabilities || [serverCapabilities.notificationsCapabilities count] == 0) {
            continue;
        }

        dispatch_group_enter(notificationsGroup);

        [[NCAPIController sharedInstance] getServerNotificationsForAccount:account withLastETag:account.lastNotificationETag withCompletionBlock:^(NSArray *notifications, NSString* ETag, NSString *userStatus, NSError *error) {
            if (error) {
                dispatch_group_leave(notificationsGroup);
                return;
            }

            // Don't show notifications if the user has status "do not disturb"
            BOOL suppressNotifications = (serverCapabilities.userStatus && [userStatus isEqualToString:kUserStatusDND]);

            NSInteger lastNotificationId = 0;
            NSMutableArray *activeServerNotificationsIds = [NSMutableArray new];

            for (NSDictionary *notification in notifications) {
                NCNotification *serverNotification = [NCNotification notificationWithDictionary:notification];

                // Only process Talk notifications
                if (!serverNotification || ![serverNotification.app isEqualToString:kNCPNAppIdKey]) {
                    continue;
                }

                [activeServerNotificationsIds addObject:@(serverNotification.notificationId)];

                if (lastNotificationId < serverNotification.notificationId) {
                    lastNotificationId = serverNotification.notificationId;
                }

                if (suppressNotifications || serverNotification.notificationType != kNCNotificationTypeChat) {
                    continue;
                }

                if (account.lastNotificationId != 0 && serverNotification.notificationId > account.lastNotificationId) {
                    // Don't show notifications if this is the first time we retrieve notifications for this account
                    // Otherwise after adding a new account all unread notifications from the server would be shown

                    [self showLocalNotificationForChatNotification:serverNotification forAccountId:account.accountId];
                }
            }

            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
                managedAccount.lastNotificationETag = ETag;

                if (managedAccount.lastNotificationId < lastNotificationId) {
                    managedAccount.lastNotificationId = lastNotificationId;
                }
            }];

            // Remove notifications that have been treated for the server
            [self->_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
                for (UNNotification *notification in notifications) {
                    NSString *notificationAccountId = [notification.request.content.userInfo objectForKey:@"accountId"];
                    NSInteger notificationIdentifier = [[notification.request.content.userInfo objectForKey:@"notificationId"]
                                                        integerValue];
                    NCLocalNotificationType localNotificationType = (NCLocalNotificationType)[[notification.request.content.userInfo objectForKey:@"localNotificationType"] integerValue];

                    if ([notificationAccountId isEqualToString:account.accountId] && ![activeServerNotificationsIds containsObject:@(notificationIdentifier)] && (localNotificationType == 0 || localNotificationType == kNCLocalNotificationTypeChatNotification)) {
                        [self->_notificationCenter removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
                        [[NCDatabaseManager sharedInstance] decreaseUnreadBadgeNumberForAccountId:account.accountId];
                    }
                }
                [self updateAppIconBadgeNumber];
                dispatch_group_leave(notificationsGroup);
            }];
        }];
    }

    dispatch_group_notify(notificationsGroup, dispatch_get_main_queue(), ^{
        // Notify backgroundFetch that we're finished
        if (block) {
            block(nil);
        }
    });
}

- (void)checkNotificationExistanceWithCompletionBlock:(CheckNotificationExistanceCompletionBlock)block
{
    dispatch_group_t notificationsGroup = dispatch_group_create();

    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        if (![[NCDatabaseManager sharedInstance] serverHasNotificationsCapability:kNotificationsCapabilityExists forAccountId:account.accountId]) {
            continue;
        }

        dispatch_group_enter(notificationsGroup);

        [_notificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
            NSMutableArray *notificationIdsOnDevice = [[NSMutableArray alloc] init];

            for (UNNotification *notification in notifications) {
                UNNotificationRequest *notificationRequest = notification.request;
                NSString *notificationAccountId = [notificationRequest.content.userInfo objectForKey:@"accountId"];
                NSInteger notificationId = [[notificationRequest.content.userInfo objectForKey:@"notificationId"] integerValue];

                if (![notificationAccountId isEqualToString:account.accountId]) {
                    continue;
                }

                [notificationIdsOnDevice addObject:@(notificationId)];
            }

            if ([notificationIdsOnDevice count] == 0) {
                // No notifications for this account are currently shown on the system -> no need to check anything

                dispatch_group_leave(notificationsGroup);
                return;
            }

            [[NCAPIController sharedInstance] checkNotificationExistance:notificationIdsOnDevice forAccount:account withCompletionBlock:^(NSArray *notificationIds, NSError *error) {
                if (error) {
                    dispatch_group_leave(notificationsGroup);
                    return;
                }

                // Remove all notificationIds which are still on the server
                for (id notificationId in notificationIds) {
                    [notificationIdsOnDevice removeObject:notificationId];
                }

                // In case there are still notifications on the device (that are not on the server anymore) remove them
                if ([notificationIdsOnDevice count] > 0) {
                    [self removeNotificationWithNotificationIds:notificationIdsOnDevice forAccountId:account.accountId];
                }

                dispatch_group_leave(notificationsGroup);
            }];
        }];
    }

    dispatch_group_notify(notificationsGroup, dispatch_get_main_queue(), ^{
        // Notify backgroundFetch that we're finished
        if (block) {
            block(nil);
        }
    });
}

#pragma mark - UNUserNotificationCenter delegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    // Called when a notification is delivered to a foreground app.
    [[NSNotificationCenter defaultCenter] postNotificationName:NCNotificationControllerWillPresentNotification object:self userInfo:nil];
    completionHandler(UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
    
    // Remove the notification from Notification Center if it is from the active account
    NSString *notificationAccountId = [notification.request.content.userInfo objectForKey:@"accountId"];
    if (notificationAccountId && [[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:notificationAccountId]) {
        [self removeAllNotificationsForAccountId:notificationAccountId];
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler
{    
    UNNotificationRequest *notificationRequest = response.notification.request;
    NSDictionary *userInfo = notificationRequest.content.userInfo;

    NCLocalNotificationType localNotificationType = (NCLocalNotificationType)[[userInfo objectForKey:@"localNotificationType"] integerValue];
    NSString *notificationString = [userInfo objectForKey:@"pushNotification"];
    NSString *notificationAccountId = [userInfo objectForKey:@"accountId"];
    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:notificationString withAccountId:notificationAccountId];

    // Handle notification response
    if (pushNotification) {
        if ([response isKindOfClass:[UNTextInputNotificationResponse class]]) {
            UNTextInputNotificationResponse *textInputResponse = (UNTextInputNotificationResponse *)response;
            pushNotification.responseUserText = textInputResponse.userText;
            
            [self handlePushNotificationResponseWithUserText:pushNotification];
        } else if (pushNotification.type == NCPushNotificationTypeRecording) {
            [self handlePushNotificationResponseForRecording:response];
        } else if (pushNotification.type == NCPUshNotificationTypeFederation) {
            [self handlePushNotificationResponseForFederation:response];
        } else if (pushNotification.type == NCPushNotificationTypeReminder) {
            [self handlePushNotificationResponseForReminder:response];
        } else {
            [self handlePushNotificationResponse:pushNotification];
        }
    } else if (localNotificationType > 0) {
        [self handleLocalNotificationResponse:notificationRequest.content.userInfo];
    }

    completionHandler();
}

- (void)handlePushNotificationResponseWithUserText:(NCPushNotification *)pushNotification
{
    NSLog(@"Recevied push-notification with user input -> sending chat message");
    
    TalkAccount *pushAccount = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:pushNotification.accountId];
    
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier sendTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:sendTask];
        sendTask = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NCAPIController sharedInstance] sendChatMessage:pushNotification.responseUserText toRoom:pushNotification.roomToken threadTitle:nil replyTo:-1 referenceId:nil silently:NO forAccount:pushAccount withCompletionBlock:^(NSError *error) {

            if (error) {
                NSLog(@"Could not send chat message. Error: %@", error.description);
                
                // Display local push-notification to inform user
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:pushNotification.roomToken forKey:@"roomToken"];
                [userInfo setValue:@(kNCLocalNotificationTypeFailedSendChat) forKey:@"localNotificationType"];
                [userInfo setObject:pushNotification.accountId forKey:@"accountId"];
                [userInfo setObject:pushNotification.responseUserText forKey:@"responseUserText"];
                
                [[NCNotificationController sharedInstance] showLocalNotification:kNCLocalNotificationTypeFailedSendChat withUserInfo:userInfo];
            } else {
                // We replied to the message, so we can assume, we read it as well
                [[NCDatabaseManager sharedInstance] decreaseUnreadBadgeNumberForAccountId:pushNotification.accountId];
                [self updateAppIconBadgeNumber];
                NCRoom *room = [[NCDatabaseManager sharedInstance] roomWithToken:pushNotification.roomToken forAccountId:pushNotification.accountId];
                if (room) {
                    [[NCIntentController sharedInstance] donateSendMessageIntentForRoom:room];
                }
            }
            
            [application endBackgroundTask:sendTask];
            sendTask = UIBackgroundTaskInvalid;
        }];
    });
}

- (void)handlePushNotificationResponseForFederation:(UNNotificationResponse *)response
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"handlePushNotificationResponseForFederation" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called - handlePushNotificationResponseForFederation"];
    }];

    UNNotificationRequest *notificationRequest = response.notification.request;
    NSDictionary *userInfo = notificationRequest.content.userInfo;

    NSString *notificationAccountId = [userInfo objectForKey:@"accountId"];
    NSDictionary *serverNotificationDict = [userInfo objectForKey:@"serverNotification"];

    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:notificationAccountId];
    NCNotification *serverNotification = [NCNotification notificationWithDictionary:serverNotificationDict];

    if (!account || !serverNotification) {
        [bgTask stopBackgroundTask];
        return;
    }

    if ([response.actionIdentifier isEqualToString:NCNotificationActionFederationInvitationAccept]) {
        FederationInvitation *invitation = [[FederationInvitation alloc] initWithNotification:serverNotification for:account.accountId];

        [[NCAPIController sharedInstance] acceptFederationInvitationFor:account.accountId with:invitation.invitationId completionBlock:^(BOOL success) {
            if (!success) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:serverNotification.roomToken forKey:@"roomToken"];
                [userInfo setValue:@(kNCLocalNotificationTypeFailedToAcceptInvitation) forKey:@"localNotificationType"];
                [userInfo setObject:notificationAccountId forKey:@"accountId"];

                [self showLocalNotification:kNCLocalNotificationTypeFailedToAcceptInvitation withUserInfo:userInfo];
            }

            [[NCDatabaseManager sharedInstance] decreasePendingFederationInvitationForAccountId:account.accountId];

            [bgTask stopBackgroundTask];
        }];

    } else if ([response.actionIdentifier isEqualToString:NCNotificationActionFederationInvitationReject]) {
        FederationInvitation *invitation = [[FederationInvitation alloc] initWithNotification:serverNotification for:account.accountId];

        [[NCAPIController sharedInstance] rejectFederationInvitationFor:account.accountId with:invitation.invitationId completionBlock:^(BOOL success) {
            [[NCDatabaseManager sharedInstance] decreasePendingFederationInvitationForAccountId:account.accountId];
            [bgTask stopBackgroundTask];
        }];
    } else {
        [bgTask stopBackgroundTask];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:serverNotification.subject
                                                                       message:serverNotification.message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        for (NCNotificationAction *notificationAction in [serverNotification notificationActions]) {
            UIAlertAction* tempButton = [UIAlertAction actionWithTitle:notificationAction.actionLabel
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                [[NCDatabaseManager sharedInstance] decreasePendingFederationInvitationForAccountId:account.accountId];
                [[NCAPIController sharedInstance] executeNotificationAction:notificationAction forAccount:account withCompletionBlock:nil];
            }];

            [alert addAction:tempButton];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        });
    }
}

- (void)handlePushNotificationResponseForRecording:(UNNotificationResponse *)response
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"handlePushNotificationResponseForRecording" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called - handlePushNotificationResponseForRecording"];
    }];

    UNNotificationRequest *notificationRequest = response.notification.request;
    NSDictionary *userInfo = notificationRequest.content.userInfo;

    NSString *notificationAccountId = [userInfo objectForKey:@"accountId"];
    NSDictionary *serverNotificationDict = [userInfo objectForKey:@"serverNotification"];

    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:notificationAccountId];
    NCNotification *serverNotification = [NCNotification notificationWithDictionary:serverNotificationDict];

    if (!account || !serverNotification) {
        [bgTask stopBackgroundTask];
        return;
    }

    NSTimeInterval notificationTimeInterval = [serverNotification.datetime timeIntervalSince1970];
    NSString *notificationTimestamp = [NSString stringWithFormat:@"%.0f", notificationTimeInterval];

    if ([response.actionIdentifier isEqualToString:NCNotificationActionShareRecording]) {
        NSDictionary *fileParameters = [serverNotification.messageRichParameters objectForKey:@"file"];

        if (!fileParameters || ![fileParameters objectForKey:@"id"]) {
            [bgTask stopBackgroundTask];
            return;
        }

        NSString *fileId = [fileParameters objectForKey:@"id"];

        [[NCAPIController sharedInstance] shareStoredRecordingWithTimestamp:notificationTimestamp
                                                                 withFileId:fileId
                                                                    forRoom:serverNotification.roomToken
                                                                 forAccount:account
                                                        withCompletionBlock:^(NSError *error) {
            if (error) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:serverNotification.roomToken forKey:@"roomToken"];
                [userInfo setValue:@(kNCLocalNotificationTypeFailedToShareRecording) forKey:@"localNotificationType"];
                [userInfo setObject:notificationAccountId forKey:@"accountId"];

                [self showLocalNotification:kNCLocalNotificationTypeFailedToShareRecording withUserInfo:userInfo];
            }

            [bgTask stopBackgroundTask];
        }];

    } else if ([response.actionIdentifier isEqualToString:NCNotificationActionDismissRecordingNotification]) {
        [[NCAPIController sharedInstance] dismissStoredRecordingNotificationWithTimestamp:notificationTimestamp
                                                                                  forRoom:serverNotification.roomToken
                                                                               forAccount:account
                                                                      withCompletionBlock:^(NSError *error) {
            [bgTask stopBackgroundTask];
        }];
    } else {
        [bgTask stopBackgroundTask];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:serverNotification.subject
                                                                       message:serverNotification.message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        NSArray *notificationActions = [serverNotification notificationActions];
        for (NCNotificationAction *notificationAction in notificationActions) {
            UIAlertAction* tempButton = [UIAlertAction actionWithTitle:notificationAction.actionLabel
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                [[NCAPIController sharedInstance] executeNotificationAction:notificationAction forAccount:account withCompletionBlock:nil];
            }];

            [alert addAction:tempButton];
        }

        if ([notificationActions count] == 0) {
            // Make sure that we have at least a way to dismiss the notification, if there are no actions
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:nil];

            [alert addAction:okButton];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        });
    }
}

- (void)handlePushNotificationResponseForReminder:(UNNotificationResponse *)response
{
    if ([NCRoomsManager sharedInstance].callViewController) {
        return;
    }

    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"handlePushNotificationResponseForReminder" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called - handlePushNotificationResponseForReminder"];
    }];

    UNNotificationRequest *notificationRequest = response.notification.request;
    NSDictionary *userInfo = notificationRequest.content.userInfo;

    NSString *notificationAccountId = [userInfo objectForKey:@"accountId"];
    NSDictionary *serverNotificationDict = [userInfo objectForKey:@"serverNotification"];

    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:notificationAccountId];
    NCNotification *serverNotification = [NCNotification notificationWithDictionary:serverNotificationDict];

    if (!account || !serverNotification) {
        [bgTask stopBackgroundTask];
        return;
    }

    // Open the conversation for the reminder
    [[NCRoomsManager sharedInstance] startChatWithRoomToken:serverNotification.roomToken];

    // After opening the notification, we need to execute the DELETE action
    for (NSDictionary *dict in serverNotification.actions) {
        NCNotificationAction *notificationAction = [[NCNotificationAction alloc] initWithDictionary:dict];

        if (notificationAction && notificationAction.actionType == NCNotificationActionTypeKNotificationActionTypeDelete) {
            [[NCAPIController sharedInstance] executeNotificationAction:notificationAction forAccount:account withCompletionBlock:nil];
        }
    }
}

- (void)handlePushNotificationResponse:(NCPushNotification *)pushNotification
{
    if ([NCRoomsManager sharedInstance].callViewController) {
        return;
    }

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
}

- (void)handleLocalNotificationResponse:(NSDictionary *)notificationUserInfo
{
    if ([NCRoomsManager sharedInstance].callViewController) {
        return;
    }

    NCLocalNotificationType localNotificationType = (NCLocalNotificationType)[[notificationUserInfo objectForKey:@"localNotificationType"] integerValue];
    if (localNotificationType > 0) {
        switch (localNotificationType) {
            case kNCLocalNotificationTypeMissedCall:
            case kNCLocalNotificationTypeCancelledCall:
            case kNCLocalNotificationTypeFailedSendChat:
            case kNCLocalNotificationTypeChatNotification:
            case kNCLocalNotificationTypeRecordingConsentRequired:
            {
                [[NCUserInterfaceController sharedInstance] presentChatForLocalNotification:notificationUserInfo];
            }
                break;
            case kNCLocalNotificationTypeCallFromOldAccount:
            {
                [[NCUserInterfaceController sharedInstance] presentSettingsViewController];
            }
                break;
            default:
                break;
        }
    }
}

@end
