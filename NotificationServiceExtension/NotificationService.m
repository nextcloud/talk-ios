//
//  NotificationService.m
//  NotificationServiceExtension
//
//  Created by Ivan Sein on 14.11.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NotificationService.h"

#import "UICKeyChainStore.h"
#import "NCSettingsController.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    self.bestAttemptContent.title = @"Nextcloud notification 🔔";
    self.bestAttemptContent.body = @"";
    
    NSString *message = [self.bestAttemptContent.userInfo objectForKey:@"subject"];
    NSString *decryptedMessage = nil;
    
    @try {
        UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                                    accessGroup:@"group.com.nextcloud.Talk"];
        decryptedMessage = [[NCSettingsController sharedInstance] decryptPushNotification:message
                                                                     withDevicePrivateKey:[keychain dataForKey:kNCPNPrivateKey]];
    } @catch (NSException *exception) {
        NSLog(@"An error ocurred decrypting the message. %@", exception);
    }
    
    if (decryptedMessage) {
        NSData *data = [decryptedMessage dataUsingEncoding:NSUTF8StringEncoding];
        id messageJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *app = [messageJSON objectForKey:@"app"];
        NSString *type = [messageJSON objectForKey:@"type"];
        NSString *subject = [messageJSON objectForKey:@"subject"];
        
        if ([app isEqualToString:@"spreed"]) {
            self.bestAttemptContent.title = @"";
            if ([type isEqualToString:@"call"]) {
                self.bestAttemptContent.body = [NSString stringWithFormat:@"📞 %@", subject];
            } else if ([type isEqualToString:@"room"]) {
                self.bestAttemptContent.body = [NSString stringWithFormat:@"🔔 %@", subject];
            } else if ([type isEqualToString:@"chat"]) {
                self.bestAttemptContent.body = [NSString stringWithFormat:@"💬 %@", subject];
            } else {
                self.bestAttemptContent.body = subject;
            }
        }
    }
    
    self.contentHandler(self.bestAttemptContent);
}

- (void)serviceExtensionTimeWillExpire {
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.bestAttemptContent.title = @"Nextcloud notification 🔔";
    self.bestAttemptContent.body = @"";
    
    self.contentHandler(self.bestAttemptContent);
}

@end
