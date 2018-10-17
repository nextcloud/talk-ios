//
//  AppDelegate.m
//  VideoCalls
//
//  Created by Ivan Sein on 30.05.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "AppDelegate.h"

#import "AFNetworkReachabilityManager.h"
#import "AFNetworkActivityIndicatorManager.h"

#import "Firebase.h"

#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

#import "OpenInFirefoxControllerObjC.h"
#import "NCConnectionController.h"
#import "NCPushNotification.h"
#import "NCRoomsManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"

@interface AppDelegate () <UNUserNotificationCenterDelegate, FIRMessagingDelegate>

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if DEBUG
    [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
#endif
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    
    @try {
        // Use Firebase library to configure APIs
        [FIRApp configure];
    } @catch (NSException *exception) {
        NSLog(@"Firebase could not be configured.");
    }
    
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        UIUserNotificationType allNotificationTypes = (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:allNotificationTypes categories:nil];
        [application registerUserNotificationSettings:settings];
    } else {
        // iOS 10 or later
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
        // For iOS 10 display notification (sent via APNS)
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
        UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
        [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
        }];
#endif
    }
    
    [application registerForRemoteNotifications];
    
    pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
    [FIRMessaging messaging].delegate = self;
    
    RTCAudioSessionConfiguration *configuration = [RTCAudioSessionConfiguration webRTCConfiguration];
    configuration.category = AVAudioSessionCategoryPlayAndRecord;
    configuration.mode = AVAudioSessionModeVideoChat;
    [RTCAudioSessionConfiguration setWebRTCConfiguration:configuration];
    
    // Check supported browsers
    NSMutableArray *supportedBrowsers = [[NSMutableArray alloc] initWithObjects:@"Safari", nil];
    if ([[OpenInFirefoxControllerObjC sharedInstance] isFirefoxInstalled]) {
        [supportedBrowsers addObject:@"Firefox"];
    }
    [NCSettingsController sharedInstance].supportedBrowsers = supportedBrowsers;
    // Set default browser
    NSString *defaultBrowser = [NCSettingsController sharedInstance].defaultBrowser;
    if (!defaultBrowser || ![supportedBrowsers containsObject:defaultBrowser]) {
        [NCSettingsController sharedInstance].defaultBrowser = @"Safari";
    }
    
    [NCUserInterfaceController sharedInstance].mainNavigationController = (UINavigationController *) self.window.rootViewController;
    
    //Init rooms manager to start receiving NSNotificationCenter notifications
    [NCRoomsManager sharedInstance];
    
    return YES;
}

// Handle remote notification registration.
- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)devToken
{
    // Forward the token to your provider, using a custom method.
//    [self enableRemoteNotificationFeatures];
//    [self forwardTokenToServer:devTokenBytes];
    NSLog(@"didRegisterForRemoteNotificationsWithDeviceToken: %@", [self stringWithDeviceToken:devToken]);
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err
{
    // The token is not currently available.
    NSLog(@"Remote notification support is unavailable due to error: %@", err);
//    [self disableRemoteNotificationFeatures];
}


-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    //Called when a notification is delivered to a foreground app.
    completionHandler(UNNotificationPresentationOptionAlert);
}

-(void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(nonnull UNNotificationResponse *)response withCompletionHandler:(nonnull void (^)(void))completionHandler
{
    //Called to let your app know which action was selected by the user for a given notification.
    NSString *message = [response.notification.request.content.userInfo objectForKey:@"subject"];
    if (message && [NCSettingsController sharedInstance].ncPNPrivateKey) {
        NSString *decryptedMessage = [[NCSettingsController sharedInstance] decryptPushNotification:message withDevicePrivateKey:[NCSettingsController sharedInstance].ncPNPrivateKey];
        if (decryptedMessage) {
            NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage];
            [[NCConnectionController sharedInstance] checkAppState];
            AppState appState = [[NCConnectionController sharedInstance] appState];
            if (pushNotification && appState > kAppStateAuthenticationNeeded) {
                switch (pushNotification.type) {
                    case NCPushNotificationTypeCall:
                    {
                        [[NCUserInterfaceController sharedInstance] presentAlertForPushNotification:pushNotification];
                    }
                        break;
                    case NCPushNotificationTypeRoom:
                    case NCPushNotificationTypeChat:
                    {
                        [[NCUserInterfaceController sharedInstance] presentChatForPushNotification:pushNotification];
                    }
                        break;
                    default:
                        break;
                }
            }
        }
    }
    completionHandler();
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
}


- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark - PushKit Delegate Methods

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type
{
    if([credentials.token length] == 0) {
        NSLog(@"Failed to create PushKit token.");
        return;
    }
    NSLog(@"PushCredentials: %@", [self stringWithDeviceToken:credentials.token]);
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    // Dummy local notification
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:1];
    localNotification.alertBody =  @"PushKit notification";
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
    
    NSLog(@"didReceiveIncomingPushWithPayload");
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

#pragma mark - Firebase

- (void)messaging:(FIRMessaging *)messaging didRefreshRegistrationToken:(NSString *)fcmToken
{
    NSLog(@"FCM registration token: %@", fcmToken);
    [NCSettingsController sharedInstance].ncPushToken = fcmToken;
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                                accessGroup:@"group.com.nextcloud.Talk"];
    [keychain setString:fcmToken forKey:kNCPushTokenKey];
}


@end
