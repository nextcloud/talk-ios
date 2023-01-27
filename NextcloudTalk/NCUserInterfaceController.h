/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CallViewController.h"
#import "NCChatViewController.h"
#import "NCNotificationController.h"
#import "NCNavigationController.h"
#import "NCPushNotification.h"
#import "RoomsTableViewController.h"

@class NCSplitViewController;

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
- (void)presentChatViewController:(NCChatViewController *)chatViewController;
- (void)presentCallViewController:(CallViewController *)callViewController;
- (void)presentCallKitCallInRoom:(NSString *)token withVideoEnabled:(BOOL)video;
- (void)presentChatForURL:(NSURLComponents *)urlComponents;
- (void)presentLoginViewControllerForServerURL:(NSString *)serverURL withUser:(NSString *)user;
- (void)presentSettingsViewController;

@end
