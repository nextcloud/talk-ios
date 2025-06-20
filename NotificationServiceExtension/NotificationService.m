/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NotificationService.h"

#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCIntentController.h"
#import "NCRoom.h"
#import "NCKeyChainController.h"
#import "NCNotification.h"
#import "NCPushNotification.h"
#import "NCPushNotificationsUtils.h"

#import "NextcloudTalk-Swift.h"

#import <SDWebImage/SDWebImage.h>

typedef void (^CreateConversationNotificationCompletionBlock)(void);

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;
@property (nonatomic, strong) INSendMessageIntent *sendMessageIntent;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    self.sendMessageIntent = nil;

    self.bestAttemptContent.title = @"";
    self.bestAttemptContent.body = NSLocalizedString(@"You received a new notification", nil);

    // Configure database
    NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
    NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];

    if ([[NSFileManager defaultManager] fileExistsAtPath:databaseURL.path]) {
        @try {
            NSError *error = nil;

            // schemaVersionAtURL throws an exception when file is not readable
            uint64_t currentSchemaVersion = [RLMRealm schemaVersionAtURL:databaseURL encryptionKey:nil error:&error];

            if (error || currentSchemaVersion != kTalkDatabaseSchemaVersion) {
                NSLog(@"Current schemaVersion is %llu app schemaVersion is %llu", currentSchemaVersion, kTalkDatabaseSchemaVersion);
                NSLog(@"Database needs migration -> don't open database from extension");

                self.contentHandler(self.bestAttemptContent);
                return;
            } else {
                NSLog(@"Current schemaVersion is %llu app schemaVersion is %llu", currentSchemaVersion, kTalkDatabaseSchemaVersion);
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Reading schemaVersion failed: %@", exception.reason);
            self.contentHandler(self.bestAttemptContent);
            return;
        }
    } else {
        NSLog(@"Database does not exist -> main app needs to run before extension.");
        self.contentHandler(self.bestAttemptContent);
        return;
    }

    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = databaseURL;
    configuration.schemaVersion= kTalkDatabaseSchemaVersion;
    configuration.objectClasses = @[TalkAccount.class, NCRoom.class, ServerCapabilities.class, FederatedCapabilities.class];
    configuration.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
        // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
    };
    [RLMRealmConfiguration setDefaultConfiguration:configuration];

    // We don't want to use a memory cache in NSE, because we only have a total of 24MB before we get killed by the OS
    SDImageCache.sharedImageCache.config.shouldCacheImagesInMemory = NO;

    BOOL foundDecryptableMessage = NO;

    // Decrypt message
    NSString *message = [self.bestAttemptContent.userInfo objectForKey:@"subject"];
    for (TalkAccount *talkAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];
        if (message && pushNotificationPrivateKey) {
            @try {
                NSString *decryptedMessage = [NCPushNotificationsUtils decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];
                if (decryptedMessage) {
                    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];

                    if (pushNotification.type == NCPushNotificationTypeAdminNotification) {
                        // Test notification send through "occ notification:test-push --talk <userid>"
                        // No need to increase the badge or query the server about it

                        self.bestAttemptContent.body = pushNotification.subject;
                        self.contentHandler(self.bestAttemptContent);
                        return;
                    }

                    foundDecryptableMessage = YES;

                    [[RLMRealm defaultRealm] transactionWithBlock:^{
                        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                        TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;

                        // Update unread notifications counter for push notification account
                        managedAccount.unreadBadgeNumber += 1;
                        managedAccount.unreadNotification = (managedAccount.active) ? NO : YES;

                        // Make sure we don't accidentally show a notification again, when we check for notifications in the background
                        if (managedAccount.lastNotificationId < pushNotification.notificationId) {
                            managedAccount.lastNotificationId = pushNotification.notificationId;
                        }
                    }];

                    // Get the total number of unread notifications
                    NSInteger unreadNotifications = 0;
                    for (TalkAccount *user in [TalkAccount allObjects]) {
                        unreadNotifications += user.unreadBadgeNumber;
                    }

                    self.bestAttemptContent.body = pushNotification.bodyForRemoteAlerts;
                    self.bestAttemptContent.threadIdentifier = pushNotification.roomToken;
                    self.bestAttemptContent.sound = [UNNotificationSound defaultSound];
                    self.bestAttemptContent.badge = @(unreadNotifications);

                    if (pushNotification.type == NCPushNotificationTypeChat) {
                        // Set category for chat messages to allow interactive notifications
                        self.bestAttemptContent.categoryIdentifier = @"CATEGORY_CHAT";
                    }

                    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                    [userInfo setObject:pushNotification.jsonString forKey:@"pushNotification"];
                    [userInfo setObject:pushNotification.accountId forKey:@"accountId"];
                    [userInfo setObject:@(pushNotification.notificationId) forKey:@"notificationId"];
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
                    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/notifications/%ld", account.server, (long)pushNotification.notificationId];
                    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
                    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:account.accountId];
                    configuration.HTTPCookieStorage = cookieStorage;
                    NCAPISessionManager *apiSessionManager = [[NCAPISessionManager alloc] initWithConfiguration:configuration];

                    NSString *userTokenString = [NSString stringWithFormat:@"%@:%@", account.user, [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId]];
                    NSData *data = [userTokenString dataUsingEncoding:NSUTF8StringEncoding];
                    NSString *base64Encoded = [data base64EncodedStringWithOptions:0];
                    NSString *authorizationHeader = [[NSString alloc] initWithFormat:@"Basic %@", base64Encoded];
                    [apiSessionManager.requestSerializer setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
                    [apiSessionManager.requestSerializer setTimeoutInterval:25];

                    [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
                        NSDictionary *notification = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
                        NCNotification *serverNotification = [NCNotification notificationWithDictionary:notification];

                        if (!serverNotification) {
                            self.contentHandler(self.bestAttemptContent);
                            return;
                        }

                        // Add the serverNotification as userInfo as well -> this can later be used to access the actions directly
                        [userInfo setObject:notification forKey:@"serverNotification"];
                        self.bestAttemptContent.userInfo = userInfo;

                        if (serverNotification.notificationType == kNCNotificationTypeChat) {
                            // Only try to adjust the title/body if there are rich parameters
                            // E.g. for sensitive conversations, there are none, so we use the server provided title/body
                            if ([serverNotification.subjectRichParameters count] > 0) {
                                NSAttributedString *attributedMessage = [[NSAttributedString alloc] initWithString:serverNotification.message];
                                NSAttributedString *markdownMessage = [SwiftMarkdownObjCBridge parseMarkdownWithMarkdownString:attributedMessage];

                                self.bestAttemptContent.title = serverNotification.chatMessageTitle;
                                self.bestAttemptContent.body = markdownMessage.string;
                            }

                            NSDictionary *fileDict = [serverNotification.messageRichParameters objectForKey:@"file"];
                            if (fileDict && [[fileDict objectForKey:@"preview-available"] boolValue]) {
                                // First try to create the conversation notification, and only afterwards try to retrieve the image preview
                                [self createConversationNotificationWithPushNotification:pushNotification withCompletionBlock:^{
                                    NSString *fileId = [fileDict objectForKey:@"id"];
                                    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=-1&y=%ld&a=1&forceIcon=1", account.server, fileId, 512L];

                                    NSURL *url = [NSURL URLWithString:urlString];

                                    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@",
                                                           [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];

                                    [[SDWebImageDownloader sharedDownloader] setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                                    [SDWebImageDownloader sharedDownloader].config.downloadTimeout = 25.0;

                                    SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageRefreshCached;

                                    NSDictionary *headerDictionary = @{@"Authorization" : authorizationHeader};
                                    SDWebImageDownloaderRequestModifier *requestModifier = [[SDWebImageDownloaderRequestModifier alloc] initWithHeaders:headerDictionary];

                                    [[SDWebImageManager sharedManager] loadImageWithURL:url options:options context:@{SDWebImageContextDownloadRequestModifier : requestModifier} progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
                                        if (error == nil && image) {
                                            UNNotificationAttachment *attachment = [self getNotificationAttachmentFromImage:image forAccountId:account.accountId];

                                            if (attachment) {
                                                self.bestAttemptContent.attachments = @[attachment];
                                            }
                                        }

                                        [self showBestAttemptNotification];
                                    }];
                                }];

                                // Stop here because the downloader completion blocks will take care of creating the conversation notification
                                return;
                            }

                        } else if (serverNotification.notificationType == kNCNotificationTypeRecording) {
                            self.bestAttemptContent.categoryIdentifier = @"CATEGORY_RECORDING";
                            self.bestAttemptContent.title = serverNotification.subject;
                            self.bestAttemptContent.body = serverNotification.message;
                        } else if (serverNotification.notificationType == kNCNotificationTypeFederation) {
                            self.bestAttemptContent.categoryIdentifier = @"CATEGORY_FEDERATION";
                            self.bestAttemptContent.title = serverNotification.subject;
                            self.bestAttemptContent.body = serverNotification.message;

                            [[NCDatabaseManager sharedInstance] increasePendingFederationInvitationForAccountId:account.accountId];
                        }

                        [self createConversationNotificationWithPushNotificationAndShow:pushNotification];
                    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
                        // Even if the server request fails, we should try to create a conversation notifications
                        [self createConversationNotificationWithPushNotificationAndShow:pushNotification];
                    }];
                }
            } @catch (NSException *exception) {
                NSLog(@"An error ocurred decrypting the message. %@", exception);
                continue;
            }
        }
    }

    if (!foundDecryptableMessage) {
        // At this point we tried everything to decrypt the received message
        // No need to wait for the extension timeout, nothing is happening anymore
        self.contentHandler(self.bestAttemptContent);
    }
}

- (void)createConversationNotificationWithPushNotification:(NCPushNotification *)pushNotification withCompletionBlock:(CreateConversationNotificationCompletionBlock)block {
    // There's no reason to create a conversation notification, if we can't ever do something with it
    if (!block) {
        return;
    }

    NCRoom *room = [[NCDatabaseManager sharedInstance] roomWithToken:pushNotification.roomToken forAccountId:pushNotification.accountId];

    if (room) {
        [[NCIntentController sharedInstance] getInteractionForRoom:room withTitle:self.bestAttemptContent.title withCompletionBlock:^(INSendMessageIntent *sendMessageIntent) {
            self.sendMessageIntent = sendMessageIntent;
            block();
        }];

        return;
    }

    block();
}

- (void)createConversationNotificationWithPushNotificationAndShow:(NCPushNotification *)pushNotification
{
    [self createConversationNotificationWithPushNotification:pushNotification withCompletionBlock:^{
        [self showBestAttemptNotification];
    }];
}

- (void)showBestAttemptNotification
{
    // When we have a send message intent, we use it, otherwise we fall back to the non-conversation-notification one
    if (self.sendMessageIntent) {
        __block NSError *error;
        self.contentHandler([self.bestAttemptContent contentByUpdatingWithProvider:self.sendMessageIntent error:&error]);
    } else {
        self.contentHandler(self.bestAttemptContent);
    }
}

- (UNNotificationAttachment *)getNotificationAttachmentFromImage:(UIImage *)image forAccountId:(NSString *)accountId
{
    NSString *encodedAccountId = [accountId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLHostAllowedCharacterSet];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *tempDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"/download/"];
    tempDirectoryPath = [tempDirectoryPath stringByAppendingPathComponent:encodedAccountId];

    if (![fileManager fileExistsAtPath:tempDirectoryPath]) {
        // Make sure our download directory exists
        [fileManager createDirectoryAtPath:tempDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *fileName = [NSString stringWithFormat:@"NotificationPreview_%@.jpg", [[NSUUID UUID] UUIDString]];
    NSString *filePath = [tempDirectoryPath stringByAppendingPathComponent:fileName];

    // Write the received image to the temporary directory and create the corresponding attachment object
    if ([UIImageJPEGRepresentation(image, 1.0) writeToFile:filePath atomically:YES]) {
        UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:fileName URL:[NSURL fileURLWithPath:filePath] options:nil error:nil];
        return attachment;
    }

    return nil;
}

- (void)serviceExtensionTimeWillExpire {
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    [self showBestAttemptNotification];
}

@end
