/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCRoom.h"
#import "NCSignalingMessage.h"

@class NCSignalingController;
@class SignalingSettings;

@protocol NCSignalingControllerObserver <NSObject>

- (void)signalingController:(NCSignalingController *)signalingController didReceiveSignalingMessage:(NSDictionary *)message;

@end

typedef void (^SignalingSettingsUpdatedCompletionBlock)(SignalingSettings *signalingSettings);

@interface NCSignalingController : NSObject

@property (nonatomic, weak) id<NCSignalingControllerObserver> observer;

- (instancetype)initForRoom:(NCRoom *)room;
- (NSArray *)getIceServers;
- (void)startPullingSignalingMessages;
- (void)sendSignalingMessage:(NCSignalingMessage *)message;
- (void)stopAllRequests;
- (void)updateSignalingSettingsWithCompletionBlock:(SignalingSettingsUpdatedCompletionBlock)block;

@end
