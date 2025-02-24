/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCConnectionController.h"

#import "AFNetworking.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"

#import "NextcloudTalk-Swift.h"

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
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    SignalingSettings *activeAccountSignalingConfig = [[[NCSettingsController sharedInstance] signalingConfigurations] objectForKey:activeAccount.accountId];

    if (!activeAccount.server || !activeAccount.user) {
        [self setAppState:kAppStateNotServerProvided];
        [[NCUserInterfaceController sharedInstance] presentLoginViewController];
    } else if (!activeAccount.userId || !activeAccount.userDisplayName) {
        [self setAppState:kAppStateMissingUserProfile];
        [[NCSettingsController sharedInstance] getUserProfileForAccountId:activeAccount.accountId withCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
            } else {
                [self checkAppState];
            }
        }];
    } else if (!activeAccountSignalingConfig) {
        [self setAppState:kAppStateMissingServerCapabilities];
        [[NCSettingsController sharedInstance] getCapabilitiesForAccountId:activeAccount.accountId withCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
                return;
            }

            [self setAppState:kAppStateMissingSignalingConfiguration];
            [[NCSettingsController sharedInstance] updateSignalingConfigurationForAccountId:activeAccount.accountId withCompletionBlock:^(NCExternalSignalingController * _Nullable signalingServer, NSError *error) {
                if (error) {
                    [self notifyAppState];
                    return;
                }

                [self checkAppState];
            }];
        }];
    } else {
        // Fetch additional data asynchronously.
        // We set the app as ready, so we don’t need to wait for this to complete.
        [[NCSettingsController sharedInstance] getUserGroupsAndTeamsForAccountId:activeAccount.accountId];
        [self setAppState:kAppStateReady];
    }
    
    [self notifyAppState];
}


@end
