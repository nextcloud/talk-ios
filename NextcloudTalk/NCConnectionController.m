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
    } else if (!activeAccountSignalingConfig) {
        [self setAppState:kAppStateMissingServerCapabilities];
        [[NCSettingsController sharedInstance] getCapabilitiesWithCompletionBlock:^(NSError *error) {
            if (error) {
                [self notifyAppState];
            } else {
                [self setAppState:kAppStateMissingSignalingConfiguration];
                [[NCSettingsController sharedInstance] getSignalingConfigurationWithCompletionBlock:^(NSError *error) {
                    if (error) {
                        [self notifyAppState];
                    } else {
                        // SetSignalingConfiguration should be called just once
                        TalkAccount *account = [[NCDatabaseManager sharedInstance] activeAccount];
                        [[NCSettingsController sharedInstance] setSignalingConfigurationForAccountId:account.accountId];
                        [self checkAppState];
                    }
                }];
            }
        }];
    } else {
        [self setAppState:kAppStateReady];
    }
    
    [self notifyAppState];
}


@end
