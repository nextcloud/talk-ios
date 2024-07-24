/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

extern NSString * const NCAppStateHasChangedNotification;
extern NSString * const NCConnectionStateHasChangedNotification;

typedef NS_ENUM(NSInteger, AppState) {
    kAppStateUnknown = 0,
    kAppStateNotServerProvided,
    kAppStateAuthenticationNeeded,
    kAppStateMissingUserProfile,
    kAppStateMissingServerCapabilities,
    kAppStateMissingSignalingConfiguration,
    kAppStateReady
};

typedef NS_ENUM(NSInteger, ConnectionState) {
    kConnectionStateUnknown = 0,
    kConnectionStateDisconnected,
    kConnectionStateConnected
};

@interface NCConnectionController : NSObject

@property(nonatomic, assign) AppState appState;
@property(nonatomic, assign) ConnectionState connectionState;

+ (instancetype)sharedInstance;
- (void)checkAppState;
- (void)checkConnectionState;

@end
