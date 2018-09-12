//
//  NCConnectionController.h
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const NCAppStateHasChangedNotification;
extern NSString * const NCConnectionStateHasChangedNotification;

typedef enum AppState {
    kAppStateUnknown = 0,
    kAppStateNotServerProvided,
    kAppStateAuthenticationNeeded,
    kAppStateMissingUserProfile,
    kAppStateMissingServerCapabilities,
    kAppStateMissingSignalingConfiguration,
    kAppStateReady
} AppState;

typedef enum ConnectionState {
    kConnectionStateUnknown = 0,
    kConnectionStateDisconnected,
    kConnectionStateConnected
} ConnectionState;

@interface NCConnectionController : NSObject

@property(nonatomic, assign) AppState appState;
@property(nonatomic, assign) ConnectionState connectionState;

+ (instancetype)sharedInstance;
- (void)checkAppState;
- (void)checkConnectionState;

@end
