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
#import "NCUtils.h"

#import "NextcloudTalk-Swift.h"

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

    //Init rooms manager to start receiving NSNotificationCenter notifications
    [NCRoomsManager sharedInstance];
    
    [self registerBackgroundFetchTask];

    if (@available(iOS 14.0, *)) {
        [NCUserInterfaceController sharedInstance].mainSplitViewController = (NCSplitViewController *) self.window.rootViewController;
        [NCUserInterfaceController sharedInstance].mainViewController = (NCSplitViewController *) self.window.rootViewController;
        [NCUserInterfaceController sharedInstance].roomsTableViewController = [NCUserInterfaceController sharedInstance].mainSplitViewController.viewControllers.firstObject.childViewControllers.firstObject;
        
        if (@available(iOS 14.5, *)) {
            [NCUserInterfaceController sharedInstance].mainSplitViewController.displayModeButtonVisibility = UISplitViewControllerDisplayModeButtonVisibilityNever;
        }
    } else {
        // We're using iOS 14 specific APIs for splitView, so fall back in case they're not supported
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"iOS13Main" bundle:[NSBundle mainBundle]];
        UIViewController *vc = [storyboard instantiateInitialViewController];

        self.window.rootViewController = vc;

        [NCUserInterfaceController sharedInstance].mainViewController = (NCNavigationController *) self.window.rootViewController;
    }
    
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

    [self scheduleAppRefresh];
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

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *scheme = urlComponents.scheme;
    if ([scheme isEqualToString:@"nextcloudtalk"]) {
        NSString *action = urlComponents.host;
        if ([action isEqualToString:@"open-conversation"]) {
            [[NCUserInterfaceController sharedInstance] presentChatForURL:urlComponents];
            return YES;
        } else if ([action isEqualToString:@"login"] && multiAccountEnabled) {
            NSArray *queryItems = urlComponents.queryItems;
            NSString *server = [NCUtils valueForKey:@"server" fromQueryItems:queryItems];
            NSString *user = [NCUtils valueForKey:@"user" fromQueryItems:queryItems];
            
            if (server) {
                [[NCUserInterfaceController sharedInstance] presentLoginViewControllerForServerURL:server withUser:user];
            }
            return YES;
        }
    }
    
    return NO;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    if (_shouldLockInterfaceOrientation) {
        if (_lockedInterfaceOrientation == UIInterfaceOrientationPortrait) {
            return UIInterfaceOrientationMaskPortrait;
        } else if (_lockedInterfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
            return UIInterfaceOrientationMaskLandscapeLeft;
        } else if (_lockedInterfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            return UIInterfaceOrientationMaskLandscapeRight;
        }
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)setShouldLockInterfaceOrientation:(BOOL)shouldLockInterfaceOrientation
{
    _shouldLockInterfaceOrientation = shouldLockInterfaceOrientation;
    _lockedInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
}

#pragma mark - Push Notifications Registration

- (void)checkForPushNotificationSubscription
{
    if (!normalPushToken || !pushKitToken) {
        return;
    }

    // Store new Normal Push & PushKit tokens in Keychain
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:bundleIdentifier accessGroup:groupIdentifier];
    [keychain setString:normalPushToken forKey:kNCNormalPushTokenKey];
    [keychain setString:pushKitToken forKey:kNCPushKitTokenKey];

    BOOL isAppInBackground = [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground;
    // Subscribe only if both tokens have been generated and app is not running in the background (do not try to subscribe
    // when the app is running in background e.g. when the app is launched due to a VoIP push notification)
    if (!isAppInBackground) {
        // Try to subscribe for push notifications in all accounts
        for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
            [[NCSettingsController sharedInstance] subscribeForPushNotificationsForAccountId:account.accountId withCompletionBlock:nil];
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

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type withCompletionHandler:(void (^)(void))completion
{
    NSString *message = [payload.dictionaryPayload objectForKey:@"subject"];
    for (TalkAccount *talkAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];

        if (!message || !pushNotificationPrivateKey) {
            continue;
        }

        NSString *decryptedMessage = [NCPushNotificationsUtils decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];

        if (!decryptedMessage) {
            continue;
        }

        NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];

        if ( pushNotification && pushNotification.type == NCPushNotificationTypeCall) {
            [[NCNotificationController sharedInstance] showIncomingCallForPushNotification:pushNotification];
            completion();
            return;
        }
    }

    [[NCNotificationController sharedInstance] showIncomingCallForOldAccount];
    [[NCSettingsController sharedInstance] setDidReceiveCallsFromOldAccount:YES];
    completion();
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

#pragma mark - BackgroundFetch / AppRefresh

- (void)registerBackgroundFetchTask {
    NSString *refreshTaskIdentifier = [NSString stringWithFormat:@"%@.refresh", NSBundle.mainBundle.bundleIdentifier];

    // see: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler?language=objc
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:refreshTaskIdentifier
                                                          usingQueue:nil
                                                       launchHandler:^(__kindof BGTask * _Nonnull task) {
        [self handleAppRefresh:task];
    }];
}

- (void)scheduleAppRefresh
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

- (void)handleAppRefresh:(BGTask *)task
{
    [NCUtils log:@"Performing background fetch -> handleAppRefresh"];
    
    // With BGTasks (iOS >= 13) we need to schedule another refresh when running in background
    [self scheduleAppRefresh];

    [self performBackgroundFetchWithCompletionHandler:^(BOOL errorOccurred) {
        [task setTaskCompletedWithSuccess:!errorOccurred];
    }];
}

// This method is called when you simulate a background fetch from the debug menu in XCode
// so we keep it around, although it's deprecated on iOS 13 onwards
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    [NCUtils log:@"Performing background fetch -> performFetchWithCompletionHandler"];

    [self performBackgroundFetchWithCompletionHandler:^(BOOL errorOccurred) {
         if (errorOccurred) {
             completionHandler(UIBackgroundFetchResultFailed);
         } else {
             completionHandler(UIBackgroundFetchResultNewData);
         }
     }];
}


- (void)performBackgroundFetchWithCompletionHandler:(void (^)(BOOL errorOccurred))completionHandler
{
    dispatch_group_t backgroundRefreshGroup = dispatch_group_create();
    __block BOOL errorOccurred = NO;
    __block BOOL expired = NO;

    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCBackgroundFetch" expirationHandler:^(BGTaskHelper *task) {
        [NCUtils log:@"ExpirationHandler called"];

        /*
        expired = YES;
        completionHandler(YES);
        
        [task stopBackgroundTask];
         */
    }];

    [NCUtils log:@"Start performBackgroundFetchWithCompletionHandler"];

    dispatch_group_enter(backgroundRefreshGroup);
    [[NCNotificationController sharedInstance] checkForNewNotificationsWithCompletionBlock:^(NSError *error) {
        [NCUtils log:@"CompletionHandler checkForNewNotificationsWithCompletionBlock"];

        if (error) {
            errorOccurred = YES;
        }

        dispatch_group_leave(backgroundRefreshGroup);
    }];

    dispatch_group_enter(backgroundRefreshGroup);
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO withCompletionBlock:^(NSError *error) {
        [NCUtils log:@"CompletionHandler updateRoomsAndChatsUpdatingUserStatus"];

        if (error) {
            errorOccurred = YES;
        }

        dispatch_group_leave(backgroundRefreshGroup);
    }];

    NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
    dayComponent.day = -1;

    NSDate *thresholdDate = [[NSCalendar currentCalendar] dateByAddingComponents:dayComponent toDate:[NSDate date] options:0];
    NSInteger thresholdTimestamp = [thresholdDate timeIntervalSince1970];

    // Push proxy should be subscrided atleast every 24h
    // Check if we reached the threshold and start the subscription process
    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        if (account.lastPushSubscription < thresholdTimestamp) {
            dispatch_group_enter(backgroundRefreshGroup);

            [[NCSettingsController sharedInstance] subscribeForPushNotificationsForAccountId:account.accountId withCompletionBlock:^(BOOL success) {
                if (!success) {
                    errorOccurred = YES;
                }

                dispatch_group_leave(backgroundRefreshGroup);
            }];
        }
    }

    dispatch_group_notify(backgroundRefreshGroup, dispatch_get_main_queue(), ^{
         [NCUtils log:@"CompletionHandler performBackgroundFetchWithCompletionHandler dispatch_group_notify"];

         if (!expired) {
             completionHandler(errorOccurred);
         }

         [bgTask stopBackgroundTask];
     });
}


@end
