/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "AppDelegate.h"

#import "AFNetworkReachabilityManager.h"
#import "AFNetworkActivityIndicatorManager.h"

#import <Intents/Intents.h>
#import <UserNotifications/UserNotifications.h>

#import <BackgroundTasks/BGTaskScheduler.h>
#import <BackgroundTasks/BGTaskRequest.h>
#import <BackgroundTasks/BGTask.h>

#import <SDWebImage/SDImageCache.h>

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

#import "NextcloudTalk-Swift.h"

@import UICKeyChainStore;

@interface AppDelegate ()

@property (nonatomic, strong) NSTimer *keepAliveTimer;
@property (nonatomic, strong) BGTaskHelper *keepAliveBGTask;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) NSTimer *debugLabelTimer;
@property (nonatomic, strong) NSTimer *fileDescriptorTimer;

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

    [[WebRTCCommon shared] dispatch:^{
        NSLog(@"Configure Audio Session");
        [NCAudioController sharedInstance];
    }];
    
    NSLog(@"Configure App Settings");
    [NCSettingsController sharedInstance];

    // Perform cleanup only once in app lifecycle
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void){
        @autoreleasepool {
            [NCUtils removeOldLogfiles];
            [[SDImageCache sharedImageCache].diskCache removeExpiredData];
            [[NCSettingsController sharedInstance] createAccountsFile];
        }
    });

    UIDevice *currentDevice = [UIDevice currentDevice];
    [NCUtils log:[NSString stringWithFormat:@"Starting %@, version %@, %@ %@, model %@", NSBundle.mainBundle.bundleIdentifier, [NCAppBranding getAppVersionString], currentDevice.systemName, currentDevice.systemVersion, currentDevice.model]];

    // Init rooms manager to start receiving NSNotificationCenter notifications
    [NCRoomsManager sharedInstance];
    
    [self registerBackgroundFetchTask];

    [NCUserInterfaceController sharedInstance].mainViewController = (NCSplitViewController *) self.window.rootViewController;
    [NCUserInterfaceController sharedInstance].roomsTableViewController = [NCUserInterfaceController sharedInstance].mainViewController.viewControllers.firstObject.childViewControllers.firstObject;
    [NCUserInterfaceController sharedInstance].mainViewController.displayModeButtonVisibility = UISplitViewControllerDisplayModeButtonVisibilityNever;

    NSArray *arguments = [[NSProcessInfo processInfo] arguments];

    if ([arguments containsObject:@"-TestEnvironment"]) {
        UIView *mainView = [NCUserInterfaceController sharedInstance].mainViewController.view;

        self.debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 30, 200, 20)];
        self.debugLabel.font = [UIFont systemFontOfSize:[UIFont smallSystemFontSize]];
        self.debugLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [mainView addSubview:self.debugLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.debugLabel.topAnchor constraintEqualToAnchor:mainView.safeAreaLayoutGuide.topAnchor constant:-15],
            [self.debugLabel.leadingAnchor constraintEqualToAnchor:mainView.safeAreaLayoutGuide.leadingAnchor constant:5],
            [self.debugLabel.trailingAnchor constraintEqualToAnchor:mainView.safeAreaLayoutGuide.trailingAnchor]
        ]];

        __weak typeof(self) weakSelf = self;
        self.debugLabelTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf.debugLabel setText:[AllocationTracker shared].description];
        }];
    }

    // Comment out the following code to log the number of open socket file descriptors
    /*
     self.fileDescriptorTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [[WebRTCCommon shared] printNumberOfOpenSocketDescriptors];
    }];
     */

    // When we include VLCKit we need to manually call this because otherwise, device rotation might not work
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
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

    // A INSendMessageIntent is usually a Siri/Shortcut suggestion and automatically created when we donate a INSendMessageIntent
    if ([userActivity.interaction.intent isKindOfClass:[INSendMessageIntent class]]) {
        // For a INSendMessageIntent we don't receive a conversationIdentifier, see NCIntentController
        INSendMessageIntent *intent = (INSendMessageIntent *)userActivity.interaction.intent;
        INPerson *recipient = intent.recipients.firstObject;

        if (recipient && recipient.customIdentifier && recipient.customIdentifier.length > 0) {
            NCRoom *room = [[NCDatabaseManager sharedInstance] roomWithInternalId:recipient.customIdentifier];

            if (room) {
                [[NCRoomsManager sharedInstance] startChatInRoom:room];
            }
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

    [self keepExternalSignalingConnectionAliveTemporarily];
    [self scheduleAppRefresh];
}


- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

    [self checkForDisconnectedExternalSignalingConnection];

    [[NCNotificationController sharedInstance] removeAllNotificationsForAccountId:[[NCDatabaseManager sharedInstance] activeAccount].accountId];
}

- (void)applicationProtectedDataDidBecomeAvailable:(UIApplication *)application
{
    if ([[CallKitManager sharedInstance].calls count] > 0) {
        [NCUtils log:@"Protected data did become available"];
    }
}

- (void)applicationProtectedDataWillBecomeUnavailable:(UIApplication *)application
{
    if ([[CallKitManager sharedInstance].calls count] > 0) {
        [NCUtils log:@"Protected data did become unavailable"];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];

    // Invalidate a potentially existing label timer
    [self.debugLabelTimer invalidate];

    [self.fileDescriptorTimer invalidate];
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
    // Reply directly to a chat notification action/category
    UNTextInputNotificationAction *replyAction = [UNTextInputNotificationAction actionWithIdentifier:NCNotificationActionReplyToChat
                                                                                          title:NSLocalizedString(@"Reply", nil)
                                                                                        options:UNNotificationActionOptionAuthenticationRequired];
    
    UNNotificationCategory *chatCategory = [UNNotificationCategory categoryWithIdentifier:@"CATEGORY_CHAT"
                                                                              actions:@[replyAction]
                                                                    intentIdentifiers:@[]
                                                                              options:UNNotificationCategoryOptionNone];

    // Recording actions/category
    UNNotificationAction *recordingShareAction = [UNNotificationAction actionWithIdentifier:NCNotificationActionShareRecording
                                                                                      title:NSLocalizedString(@"Share to chat", nil)
                                                                                    options:UNNotificationActionOptionAuthenticationRequired];

    UNNotificationAction *recordingDismissAction = [UNNotificationAction actionWithIdentifier:NCNotificationActionDismissRecordingNotification
                                                                                      title:NSLocalizedString(@"Dismiss notification", nil)
                                                                                    options:UNNotificationActionOptionAuthenticationRequired | UNNotificationActionOptionDestructive];

    UNNotificationCategory *recordingCategory = [UNNotificationCategory categoryWithIdentifier:@"CATEGORY_RECORDING"
                                                                                       actions:@[recordingShareAction, recordingDismissAction]
                                                                             intentIdentifiers:@[]
                                                                                       options:UNNotificationCategoryOptionNone];

    // Federation invitation
    UNNotificationAction *federationAccept = [UNNotificationAction actionWithIdentifier:NCNotificationActionFederationInvitationAccept
                                                                                  title:NSLocalizedString(@"Accept", nil)
                                                                                options:UNNotificationActionOptionAuthenticationRequired];

    UNNotificationAction *federationReject = [UNNotificationAction actionWithIdentifier:NCNotificationActionFederationInvitationReject
                                                                                  title:NSLocalizedString(@"Reject", nil)
                                                                                options:UNNotificationActionOptionAuthenticationRequired | UNNotificationActionOptionDestructive];

    UNNotificationCategory *federationCategory = [UNNotificationCategory categoryWithIdentifier:@"CATEGORY_FEDERATION"
                                                                                       actions:@[federationAccept, federationReject]
                                                                             intentIdentifiers:@[]
                                                                                       options:UNNotificationCategoryOptionNone];

    NSSet *categories = [NSSet setWithObjects:chatCategory, recordingCategory, federationCategory, nil];
    [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:categories];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    // Called when a background notification is delivered.
    NSString *message = [userInfo objectForKey:@"subject"];
    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        NSData *pushNotificationPrivateKey = [[NCKeyChainController sharedInstance] pushNotificationPrivateKeyForAccountId:account.accountId];
        if (message && pushNotificationPrivateKey) {
            NSString *decryptedMessage = [NCPushNotificationsUtils decryptPushNotification:message withDevicePrivateKey:pushNotificationPrivateKey];
            if (decryptedMessage) {
                NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage withAccountId:account.accountId];
                [[NCNotificationController sharedInstance] processBackgroundPushNotification:pushNotification];

                break;
            }
        }
    }

    // Check if the other notifications are still current and try to remove them otherwise
    [[NCNotificationController sharedInstance] checkNotificationExistanceWithCompletionBlock:^(NSError *error) {
        completionHandler(UIBackgroundFetchResultNewData);
    }];
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
    [NCUtils log:@"Received PushKit notification"];

    NSString *message = [payload.dictionaryPayload objectForKey:@"subject"];
    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
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
    [[NCRoomsManager sharedInstance] resendOfflineMessagesWithCompletionBlock:^{
        [NCUtils log:@"CompletionHandler resendOfflineMessagesWithCompletionBlock"];

        dispatch_group_leave(backgroundRefreshGroup);
    }];

    // Check if the shown notifications are still available on the server
    dispatch_group_enter(backgroundRefreshGroup);
    [[NCNotificationController sharedInstance] checkNotificationExistanceWithCompletionBlock:^(NSError *error) {
        [NCUtils log:@"CompletionHandler checkNotificationExistance"];

        if (error) {
            errorOccurred = YES;
        }

        dispatch_group_leave(backgroundRefreshGroup);
    }];

    /* Disable checking for new messages for now, until we can prevent them from showing twice
    dispatch_group_enter(backgroundRefreshGroup);
    [[NCNotificationController sharedInstance] checkForNewNotificationsWithCompletionBlock:^(NSError *error) {
        [NCUtils log:@"CompletionHandler checkForNewNotificationsWithCompletionBlock"];

        if (error) {
            errorOccurred = YES;
        }

        dispatch_group_leave(backgroundRefreshGroup);
    }];
     */

    dispatch_group_enter(backgroundRefreshGroup);
    [[NCRoomsManager sharedInstance] updateRoomsAndChatsUpdatingUserStatus:NO onlyLastModified:YES withCompletionBlock:^(NSError *error) {
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

- (void)keepExternalSignalingConnectionAliveTemporarily
{
    [_keepAliveTimer invalidate];

    _keepAliveBGTask = [BGTaskHelper startBackgroundTaskWithName:@"NCWebSocketKeepAlive" expirationHandler:nil];
    _keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:20 repeats:NO block:^(NSTimer * _Nonnull timer) {
        // Stop the external signaling connections only if the app keeps in the background and not in a call
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground &&
            ![NCRoomsManager sharedInstance].callViewController) {
            [[NCSettingsController sharedInstance] disconnectAllExternalSignalingControllers];
        }

        // Disconnect is dispatched to the main queue, so in theory it can happen that we stop the background task
        // before the disconnect is run/completed. So we dispatch the stopBackgroundTask to main as well
        // to be sure it's called after everything else is run.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_keepAliveBGTask stopBackgroundTask];
        });
    }];

    [[NSRunLoop mainRunLoop] addTimer:_keepAliveTimer forMode:NSRunLoopCommonModes];
}

- (void)checkForDisconnectedExternalSignalingConnection
{
    [_keepAliveTimer invalidate];
    [_keepAliveBGTask stopBackgroundTask];

    [[NCSettingsController sharedInstance] connectDisconnectedExternalSignalingControllers];
}


@end
