/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "NCNotificationController.h"
#import "NCNavigationController.h"
#import "NCPushNotification.h"
#import "RoomsTableViewController.h"
#import "NCRoom.h"

@class NCSplitViewController;
@class ChatViewController;
@class CallViewController;

typedef void (^PresentCallControllerCompletionBlock)(void);

@interface NCUserInterfaceController : NSObject

@property (nonatomic, strong) NCSplitViewController *mainViewController;
@property (nonatomic, strong) RoomsTableViewController *roomsTableViewController;

+ (instancetype)sharedInstance;
- (void)presentConversationsList;
- (void)popToConversationsList;
- (void)presentLoginViewController;
- (void)presentOfflineWarningAlert;
- (void)presentLoggedOutInvalidCredentialsAlert;
- (void)presentChatForLocalNotification:(NSDictionary *)userInfo;
- (void)presentChatForPushNotification:(NCPushNotification *)pushNotification;
- (void)presentAlertForPushNotification:(NCPushNotification *)pushNotification;
- (void)presentAlertViewController:(UIAlertController *)alertViewController;
- (void)presentAlertIfNotPresentedAlready:(UIAlertController *)alertViewController;
- (void)presentAlertWithTitle:(NSString *)title withMessage:(NSString *)message;
- (void)presentChatViewController:(ChatViewController *)chatViewController;
- (void)presentCallViewController:(CallViewController *)callViewController withCompletionBlock:(PresentCallControllerCompletionBlock)block;
- (void)presentCallKitCallInRoom:(NSString *)token withVideoEnabled:(BOOL)video;
- (void)presentChatForURL:(NSURLComponents *)urlComponents;
- (void)presentLoginViewControllerForServerURL:(NSString *)serverURL withUser:(NSString *)user;
- (void)presentSettingsViewController;
- (void)presentShareLinkDialogForRoom:(NCRoom *)room inViewContoller:(UITableViewController *)viewController forIndexPath:(NSIndexPath *)indexPath;
- (void)logOutAccountWithAccountId:(NSString *)accountId;

@end
