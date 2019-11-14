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
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
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
    TalkAccount *activeAccount                  = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities      = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    NSDictionary *activeAccountSignalingConfig  = [[[NCSettingsController sharedInstance] signalingConfigutations] objectForKey:activeAccount.accountId];
    
    if (!activeAccount.server || !activeAccount.user) {
        [self setAppState:kAppStateNotServerProvided];
        [[NCUserInterfaceController sharedInstance] presentLoginViewController];
    } else if (!activeAccount.userId || !activeAccount.userDisplayName) {
        [self setAppState:kAppStateMissingUserProfile];
        [[NCSettingsController sharedInstance] getUserProfileWithCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
            } else {
                [self checkAppState];
            }
        }];
    } else if (!serverCapabilities) {
        [self setAppState:kAppStateMissingServerCapabilities];
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
            } else {
                [self checkAppState];
            }
        }];
    } else if (!activeAccountSignalingConfig) {
        [self setAppState:kAppStateMissingSignalingConfiguration];
        [[NCSettingsController sharedInstance] getSignalingConfigurationWithCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
            } else {
                // SetSignalingConfiguration should be called just once
                [[NCSettingsController sharedInstance] setSignalingConfigurationForAccount:activeAccount.accountId];
                [self checkAppState];
            }
        }];
    } else {
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:nil];
        [self setAppState:kAppStateReady];
    }
    
    [self notifyAppState];
}


@end
