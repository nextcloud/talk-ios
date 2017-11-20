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
        
        decryptedMessage = [messageJSON objectForKey:@"subject"];
        self.bestAttemptContent.body = decryptedMessage;
        
        NSString *appId = [messageJSON objectForKey:@"app"];
        if ([appId isEqualToString:@"spreed"]) {
            self.bestAttemptContent.title = @"Talk notification 📞";
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
