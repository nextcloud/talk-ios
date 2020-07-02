//
//  NotificationService.m
//  NotificationServiceExtension
//
//  Created by Ivan Sein on 23.06.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import "NotificationService.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCNotification.h"
#import "NCPushNotification.h"
#import "NCSettingsController.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    self.bestAttemptContent.title = @"";
    self.bestAttemptContent.body = @"You received a new notification";
    
    // Configure database
    NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.nextcloud.Talk"] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];
    configuration.fileURL = databaseURL;
    configuration.schemaVersion= kTalkDatabaseSchemaVersion;
    configuration.objectClasses = @[TalkAccount.class];
    NSError *error = nil;
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:&error];
    
    // Decrypt message
    NSString *message = [self.bestAttemptContent.userInfo objectForKey:@"subject"];
    for (TalkAccount *talkAccount in [TalkAccount allObjectsInRealm:realm]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        NSData *pushNotificationPrivateKey = [[NCSettingsController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];
        if (message && pushNotificationPrivateKey) {
            @try {
                NSString *decryptedMessage = [[NCSettingsController sharedInstance] decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];
                if (decryptedMessage) {
                    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];
                    self.bestAttemptContent.body = pushNotification.bodyForRemoteAlerts;
                    self.bestAttemptContent.threadIdentifier = pushNotification.roomToken;
                    self.bestAttemptContent.sound = [UNNotificationSound defaultSound];
                    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                    [userInfo setObject:pushNotification.jsonString forKey:@"pushNotification"];
                    [userInfo setObject:pushNotification.accountId forKey:@"accountId"];
                    self.bestAttemptContent.userInfo = userInfo;
                    // Create title and body structure if there is a new line in the subject
                    NSArray* components = [pushNotification.subject componentsSeparatedByString:@"\n"];
                    if (components.count > 1) {
                        NSString *title = [components objectAtIndex:0];
                        NSMutableArray *mutableComponents = [[NSMutableArray alloc] initWithArray:components];
                        [mutableComponents removeObjectAtIndex:0];
                        NSString *body = [mutableComponents componentsJoinedByString:@"\n"];
                        self.bestAttemptContent.title = title;
                        self.bestAttemptContent.body = body;
                    }
                    // Try to get the notification from the server
                    [[NCAPIController sharedInstance] getServerNotification:pushNotification.notificationId forAccount:account withCompletionBlock:^(NSDictionary *notification, NSError *error, NSInteger statusCode) {
                        if (!error) {
                            NCNotification *serverNotification = [NCNotification notificationWithDictionary:notification];
                            if (serverNotification && serverNotification.notificationType == kNCNotificationTypeChat) {
                                self.bestAttemptContent.title = serverNotification.chatMessageTitle;
                                self.bestAttemptContent.body = serverNotification.message;
                                if (@available(iOS 12.0, *)) {
                                    self.bestAttemptContent.summaryArgument = serverNotification.chatMessageAuthor;
                                }
                            }
                        }
                        self.contentHandler(self.bestAttemptContent);
                    }];
                }
            } @catch (NSException *exception) {
                continue;
                NSLog(@"An error ocurred decrypting the message. %@", exception);
            }
        }
    }
}

- (void)serviceExtensionTimeWillExpire {
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.bestAttemptContent.title = @"";
    self.bestAttemptContent.body = @"You received a new notification";
    
    self.contentHandler(self.bestAttemptContent);
}

@end
