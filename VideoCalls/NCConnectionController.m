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

NSString * const NCNetworkReachabilityHasChangedNotification    = @"NCNetworkingReachabilityHasChangedNotification";
NSString * const kNCNetworkReachabilityKey                      = @"NetworkReachability";

@implementation NCConnectionController

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
        NSString *storedServer = [NCSettingsController sharedInstance].ncServer;
        NSString *storedUser = [NCSettingsController sharedInstance].ncUser;
        NSString *storedToken = [NCSettingsController sharedInstance].ncToken;
        
        if (storedServer) {
            [[NCAPIController sharedInstance] setNCServer:storedServer];
        }
        if (storedUser && storedToken) {
            [[NCAPIController sharedInstance] setAuthHeaderWithUser:storedUser andToken:storedToken];
        }
        
        [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            NSLog(@"Reachability: %@", AFStringFromNetworkReachabilityStatus(status));
            [[NSNotificationCenter defaultCenter] postNotificationName:NCNetworkReachabilityHasChangedNotification
                                                                object:self
                                                              userInfo:@{kNCNetworkReachabilityKey:@(status)}];
        }];
    }
    return self;
}

- (BOOL)connected {
    return [AFNetworkReachabilityManager sharedManager].reachable;
}

- (ConnectionState)connectionState
{
    if ([self connected]) {
        if (![NCSettingsController sharedInstance].ncServer) {
            return kConnectionStateNotServerProvided;
        } else if (![NCSettingsController sharedInstance].ncUser) {
            return kConnectionStateAuthenticationNeeded;
        } else {
            return kConnectionStateConnecting;
        }
    } else {
        return kConnectionStateNetworkDisconnected;
    }
}


@end
