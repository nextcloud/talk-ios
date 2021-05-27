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

#import "AppDelegate.h"

#import "AFNetworkReachabilityManager.h"
#import "AFNetworkActivityIndicatorManager.h"

#import <Intents/Intents.h>

#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

#import <UserNotifications/UserNotifications.h>

#import <BackgroundTasks/BGTaskScheduler.h>
#import <BackgroundTasks/BGTaskRequest.h>
#import <BackgroundTasks/BGTask.h>

#import "UICKeyChainStore.h"

#import "NCAudioController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCKeyChainController.h"
#import "NCNavigationController.h"
#import "NCNotificationController.h"
#import "NCPushNotification.h"
#import "NCPushNotificationsUtils.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if DEBUG
    [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
#endif
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    
    [[NCNotificationController sharedInstance] requestAuthorization];
    
    [application registerForRemoteNotifications];
    
    pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
    NSLog(@"Configure Audio Session");
    [NCAudioController sharedInstance];
    
    NSLog(@"Configure App Settings");
    [NCSettingsController sharedInstance];
    
    [NCUserInterfaceController sharedInstance].mainNavigationController = (UINavigationController *) self.window.rootViewController;
    
    //Init rooms manager to start receiving NSNotificationCenter notifications
    [NCRoomsManager sharedInstance];

    [[BKPasscodeLockScreenManager sharedManager] setDelegate:self];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BKPasscodeLockScreenManager sharedManager] showLockScreen:NO];
    });
    
    [self registerBackgroundFetchTask];
    
    return YES;
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler
{
    BOOL audioCallIntent = [userActivity.interaction.intent isKindOfClass:[INStartAudioCallIntent class]];
    BOOL videoCallIntent = [userActivity.interaction.intent isKindOfClass:[INStartVideoCallIntent class]];
    if (audioCallIntent || videoCallIntent) {
        INPerson *person = [[(INStartAudioCallIntent*)userActivity.interaction.intent contacts] firstObject];
        NSString *roomToken = person.personHandle.value;
        if (roomToken) {
            [[NCUserInterfaceController sharedInstance] presentCallKitCallInRoom:roomToken withVideoEnabled:videoCallIntent];
        }
    }
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    // show passcode view controller when enter background. Screen will be obscured from here.
    [[BKPasscodeLockScreenManager sharedManager] showLockScreen:NO];
    
    if (@available(iOS 13.0, *)) {
        [self scheduleAppRefresh];
    }
}


- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [[NCNotificationController sharedInstance] removeAllNotificationsForAccountId:[[NCDatabaseManager sharedInstance] activeAccount].accountId];
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark - Push Notifications Registration

- (void)checkForPushNotificationSubscription
{
    if (normalPushToken && pushKitToken) {
        UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:bundleIdentifier accessGroup:groupIdentifier];
        NSString *deviceNormalPushToken = [NCSettingsController sharedInstance].ncNormalPushToken;
        NSString *devicePushKitToken = [NCSettingsController sharedInstance].ncPushKitToken;
        BOOL tokenChanged = ![deviceNormalPushToken isEqualToString:normalPushToken] || ![devicePushKitToken isEqualToString:devicePushKitToken];
        
        // Store new Normal Push & PushKit tokens in Keychain
        [NCSettingsController sharedInstance].ncNormalPushToken = normalPushToken;
        [keychain setString:normalPushToken forKey:kNCNormalPushTokenKey];
        [NCSettingsController sharedInstance].ncPushKitToken = pushKitToken;
        [keychain setString:pushKitToken forKey:kNCPushKitTokenKey];
        
        if (tokenChanged) {
            // Remove subscribed flag if token has changed
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm beginWriteTransaction];
            for (TalkAccount *account in [TalkAccount allObjects]) {
                account.pushNotificationSubscribed = NO;
            }
            [realm commitWriteTransaction];
        }
        
        // Check if any account needs to subscribe for push notifications
        for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
            if (tokenChanged || !account.pushNotificationSubscribed) {
                [[NCSettingsController sharedInstance] subscribeForPushNotificationsForAccountId:account.accountId];
            }
        }
    }
}

#pragma mark - Normal Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    if([deviceToken length] == 0) {
        NSLog(@"Failed to create Normal Push token.");
        return;
    }
    
    normalPushToken = [self stringWithDeviceToken:deviceToken];
    [self checkForPushNotificationSubscription];
    [self registerInteractivePushNotification];
}

- (void)registerInteractivePushNotification
{
    UNTextInputNotificationAction *replyAction = [UNTextInputNotificationAction actionWithIdentifier:@"REPLY_CHAT"
                                                                                          title:NSLocalizedString(@"Reply", nil)
                                                                                        options:UNNotificationActionOptionAuthenticationRequired];
    
    UNNotificationCategory *chatCategory = [UNNotificationCategory categoryWithIdentifier:@"CATEGORY_CHAT"
                                                                              actions:@[replyAction]
                                                                    intentIdentifiers:@[]
                                                                              options:UNNotificationCategoryOptionNone];
    
    NSSet *categories = [NSSet setWithObject:chatCategory];
    [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:categories];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    // Called when a background notification is delivered.
    NSString *message = [userInfo objectForKey:@"subject"];
    for (TalkAccount *talkAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];
        if (message && pushNotificationPrivateKey) {
            NSString *decryptedMessage = [NCPushNotificationsUtils decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];
            if (decryptedMessage) {
                NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];
                [[NCNotificationController sharedInstance] processBackgroundPushNotification:pushNotification];
            }
        }
    }
    completionHandler(UIBackgroundFetchResultNewData);
}


#pragma mark - PushKit Delegate Methods

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type
{
    if([credentials.token length] == 0) {
        NSLog(@"Failed to create PushKit token.");
        return;
    }
    
    pushKitToken = [self stringWithDeviceToken:credentials.token];
    [self checkForPushNotificationSubscription];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSString *message = [payload.dictionaryPayload objectForKey:@"subject"];
    for (TalkAccount *talkAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];
        if (message && pushNotificationPrivateKey) {
            NSString *decryptedMessage = [NCPushNotificationsUtils decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];
            if (decryptedMessage) {
                NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];
                if (pushNotification && pushNotification.type == NCPushNotificationTypeCall) {
                    [[NCNotificationController sharedInstance] showIncomingCallForPushNotification:pushNotification];
                }
            }
        }
    }
}

- (NSString *)stringWithDeviceToken:(NSData *)deviceToken
{
    const char *data = [deviceToken bytes];
    NSMutableString *token = [NSMutableString string];
    
    for (NSUInteger i = 0; i < [deviceToken length]; i++) {
        [token appendFormat:@"%02.2hhX", data[i]];
    }
    
    return [token copy];
}


#pragma mark - Lock screen

- (void)passcodeViewController:(CCBKPasscode *)aViewController didFinishWithPasscode:(NSString *)aPasscode
{
    [aViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController authenticatePasscode:(NSString *)aPasscode resultHandler:(void (^)(BOOL))aResultHandler
{
    if ([aPasscode isEqualToString:[NCSettingsController sharedInstance].lockScreenPasscode]) {
        aResultHandler(YES);
    } else {
        aResultHandler(NO);
    }
}

- (BOOL)lockScreenManagerShouldShowLockScreen:(BKPasscodeLockScreenManager *)aManager
{
    BOOL shouldShowLockScreen = [[NCSettingsController sharedInstance].lockScreenPasscode length] != 0;
    // Do not show lock screen if there are no accounts configured
    if ([[NCDatabaseManager sharedInstance] numberOfAccounts] == 0) {
        shouldShowLockScreen = NO;
    }
    
    return shouldShowLockScreen;
}

- (UIViewController *)lockScreenManagerPasscodeViewController:(BKPasscodeLockScreenManager *)aManager
{
    CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
    viewController.type = BKPasscodeViewControllerCheckPasscodeType;
    viewController.delegate = self;
    viewController.title = talkAppName;
    viewController.fromType = CCBKPasscodeFromLockScreen;

    if ([NCSettingsController sharedInstance].lockScreenPasscodeType == NCPasscodeTypeSimple) {
        viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
        viewController.passcodeInputView.maximumLength = 6;
    } else {
        viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
        viewController.passcodeInputView.maximumLength = 64;
    }
    
    viewController.touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:bundleIdentifier];
    viewController.touchIDManager.promptText = @"Scan fingerprint to authenticate";

    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:viewController];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    return navigationController;
}

#pragma mark - BackgroundFetch / AppRefresh

- (void)registerBackgroundFetchTask {
    NSString *refreshTaskIdentifier = [NSString stringWithFormat:@"%@.refresh", NSBundle.mainBundle.bundleIdentifier];

    if (@available(iOS 13.0, *)) {
        // see: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler?language=objc
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:refreshTaskIdentifier
                                                              usingQueue:nil
                                                           launchHandler:^(__kindof BGTask * _Nonnull task) {
            [self handleAppRefresh:task];
        }];
    } else {
        [UIApplication.sharedApplication setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    }
}

- (void)scheduleAppRefresh API_AVAILABLE(ios(13.0))
{
    NSString *refreshTaskIdentifier = [NSString stringWithFormat:@"%@.refresh", NSBundle.mainBundle.bundleIdentifier];
    
    BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:refreshTaskIdentifier];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:UIApplicationBackgroundFetchIntervalMinimum];
    
    NSError *error = nil;
    [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    
    if (error) {
        NSLog(@"Failed to submit apprefresh request: %@", error);
    }
}

- (void)handleAppRefresh:(BGTask *)task API_AVAILABLE(ios(13.0))
{
    NSLog(@"Performing background fetch -> handleAppRefresh");
    
    // With BGTasks (iOS >= 13) we need to schedule another refresh when running in background
    [self scheduleAppRefresh];

    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO withCompletionBlock:^(NSError *error) {
        if (error) {
            [task setTaskCompletedWithSuccess:NO];
        } else {
            [task setTaskCompletedWithSuccess:YES];
        }
    }];
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    NSLog(@"Performing background fetch -> performFetchWithCompletionHandler");
    
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO withCompletionBlock:^(NSError *error) {
        if (error) {
            completionHandler(UIBackgroundFetchResultFailed);
        } else {
            completionHandler(UIBackgroundFetchResultNewData);
        }
    }];
}


@end
