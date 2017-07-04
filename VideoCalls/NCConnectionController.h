//
//  NCConnectionController.h
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum ConnectionState {
    kConnectionStateNotServerProvided = 0,
    kConnectionStateAuthenticationNeeded,
    kConnectionStateNetworkDisconnected,
    kConnectionStateConnecting,
    kConnectionStateConnected
} ConnectionState;

extern NSString * const NCNetworkReachabilityHasChangedNotification;
extern NSString * const kNCNetworkReachabilityKey;

@interface NCConnectionController : NSObject

+ (instancetype)sharedInstance;
- (ConnectionState)connectionState;

@end
