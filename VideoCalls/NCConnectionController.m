//
//  NCConnectionController.m
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCConnectionController.h"

#import "AFNetworking.h"
#import "NCAPIController.h"
#import "NCSettingsController.h"
#import "NCExternalSignalingController.h"
#import "NCUserInterfaceController.h"

NSString * const NCAppStateHasChangedNotification           = @"NCAppStateHasChangedNotification";
NSString * const NCConnectionStateHasChangedNotification    = @"NCConnectionStateHasChangedNotification";

@implementation NCConnectionController

@synthesize appState        = _appState;
@synthesize connectionState = _connectionState;

+ (NCConnectionController *)sharedInstance
{
    static dispatch_once_t once;
    static NCConnectionController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        
        self.appState = kAppStateUnknown;
        self.connectionState = kConnectionStateUnknown;
        
        NSString *storedServer = [NCSettingsController sharedInstance].ncServer;
        NSString *storedUser = [NCSettingsController sharedInstance].ncUser;
        NSString *storedToken = [NCSettingsController sharedInstance].ncToken;
        
        if (storedServer) {
            [[NCAPIController sharedInstance] setNCServer:storedServer];
        }
        if (storedUser && storedToken) {
            [[NCAPIController sharedInstance] setAuthHeaderWithUser:storedUser andToken:storedToken];
        }
        
        [self checkAppState];
        
        [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            NSLog(@"Reachability: %@", AFStringFromNetworkReachabilityStatus(status));
            [self checkConnectionState];
        }];
    }
    return self;
}

- (void)notifyAppState
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@(self.appState) forKey:@"appState"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCAppStateHasChangedNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)notifyConnectionState
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@(self.connectionState) forKey:@"connectionState"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCConnectionStateHasChangedNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (BOOL)isNetworkAvailable {
    return [AFNetworkReachabilityManager sharedManager].reachable;
}

- (void)checkConnectionState
{
    if (![self isNetworkAvailable]) {
        [self setConnectionState:kConnectionStateDisconnected];
        [self notifyConnectionState];
    } else {
        ConnectionState previousState = self.connectionState;
        [self setConnectionState:kConnectionStateConnected];
        [self checkAppState];
        if (previousState == kConnectionStateDisconnected) {
            [self notifyConnectionState];
        }
    }
}

- (void)checkAppState
{
    NSString *ncServer                  = [NCSettingsController sharedInstance].ncServer;
    NSString *ncUser                    = [NCSettingsController sharedInstance].ncUser;
    NSString *ncUserId                  = [NCSettingsController sharedInstance].ncUserId;
    NSString *ncUserDisplayName         = [NCSettingsController sharedInstance].ncUserDisplayName;
    NSDictionary *ncTalkCapabilities    = [NCSettingsController sharedInstance].ncTalkCapabilities;
    NSDictionary *ncSignalingConfig     = [NCSettingsController sharedInstance].ncSignalingConfiguration;
    
    if (!ncServer) {
        if (self.appState != kAppStateNotServerProvided) {
            [self setAppState:kAppStateNotServerProvided];
            [[NCUserInterfaceController sharedInstance] presentLoginViewController];
        }
    } else if (!ncUser) {
        if (self.appState != kAppStateAuthenticationNeeded) {
            [self setAppState:kAppStateAuthenticationNeeded];
            [[NCUserInterfaceController sharedInstance] presentAuthenticationViewController];
        }
    } else if (!ncUserId || !ncUserDisplayName) {
        if (self.appState != kAppStateMissingUserProfile) {
            [self setAppState:kAppStateMissingUserProfile];
            [[NCSettingsController sharedInstance] getUserProfileWithCompletionBlock:^(NSError *error) {
                if (error) {
                    [self setAppState:kAppStateUnknown];
                } else {
                    [self checkAppState];
                }
            }];
        }
    } else if (!ncTalkCapabilities) {
        if (self.appState != kAppStateMissingServerCapabilities) {
            [self setAppState:kAppStateMissingServerCapabilities];
            [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:^(NSError *error) {
                if (error) {
                    [self setAppState:kAppStateUnknown];
                } else {
                    [self checkAppState];
                }
            }];
        }
    } else if (!ncSignalingConfig) {
        if (self.appState != kAppStateMissingSignalingConfiguration) {
            [self setAppState:kAppStateMissingSignalingConfiguration];
            [[NCSettingsController sharedInstance] getSignalingConfigurationWithCompletionBlock:^(NSError *error) {
                if (error) {
                    [self setAppState:kAppStateUnknown];
                } else {
                    // SetSignalingConfiguration should be called just once
                    [[NCSettingsController sharedInstance] setSignalingConfiguration];
                    [self checkAppState];
                }
            }];
        }
    } else {
        [self setAppState:kAppStateReady];
    }
    
    [self notifyAppState];
}


@end
