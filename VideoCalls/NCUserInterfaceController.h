//
//  NCUserInterfaceController.h
//  VideoCalls
//
//  Created by Ivan Sein on 28.02.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CallViewController.h"
#import "NCChatViewController.h"
#import "NCNotificationController.h"
#import "NCPushNotification.h"

@interface NCUserInterfaceController : NSObject

@property (nonatomic, strong) UINavigationController *mainNavigationController;

+ (instancetype)sharedInstance;
- (void)presentConversationsList;
- (void)presentLoginViewController;
- (void)presentOfflineWarningAlert;
- (void)presentChatForLocalNotification:(NSDictionary *)userInfo;
- (void)presentChatForPushNotification:(NCPushNotification *)pushNotification;
- (void)presentAlertForPushNotification:(NCPushNotification *)pushNotification;
- (void)presentAlertViewController:(UIAlertController *)alertViewController;
- (void)presentChatViewController:(NCChatViewController *)chatViewController;
- (void)presentCallViewController:(CallViewController *)callViewController;
- (void)presentCallKitCallInRoom:(NSString *)token withVideoEnabled:(BOOL)video;

@end
