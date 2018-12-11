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

#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

#import "OpenInFirefoxControllerObjC.h"
#import "NCConnectionController.h"
#import "NCNotificationController.h"
#import "NCPushNotification.h"
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
    [[NCNotificationController sharedInstance] cleanNotifications];
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
    
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                                accessGroup:@"group.com.nextcloud.Talk"];
    NSString *pushKitToken = [self stringWithDeviceToken:credentials.token];
    NSString *savedPushKitToken = [NCSettingsController sharedInstance].ncPushKitToken;
    NSString *subscribed = [NCSettingsController sharedInstance].pushNotificationSubscribed;
    
    // Re-subscribe if new push token has been generated
    if (!subscribed || ![savedPushKitToken isEqualToString:pushKitToken]) {
        // Remove subscribed flag
        [keychain removeItemForKey:kNCPushSubscribedKey];
        // Store new PushKit token
        [NCSettingsController sharedInstance].ncPushKitToken = pushKitToken;
        [keychain setString:pushKitToken forKey:kNCPushKitTokenKey];
        
        [[NCConnectionController sharedInstance] reSubscribeForPushNotifications];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSString *message = [payload.dictionaryPayload objectForKey:@"subject"];
    if (message && [NCSettingsController sharedInstance].ncPNPrivateKey) {
        NSString *decryptedMessage = [[NCSettingsController sharedInstance] decryptPushNotification:message withDevicePrivateKey:[NCSettingsController sharedInstance].ncPNPrivateKey];
        if (decryptedMessage) {
            NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:decryptedMessage];
            [[NCNotificationController sharedInstance] processIncomingPushNotification:pushNotification];
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


@end
