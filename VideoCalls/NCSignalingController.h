//
//  NCSignalingController.h
//  VideoCalls
//
//  Created by Ivan Sein on 01.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCSignalingMessage.h"

@class NCSignalingController;

@protocol NCSignalingControllerObserver <NSObject>

- (void)signalingController:(NCSignalingController *)signalingController didReceiveSignalingMessage:(NSDictionary *)message;

@end

@interface NCSignalingController : NSObject

@property (nonatomic, weak) id<NCSignalingControllerObserver> observer;

- (void)startPullingSignalingMessages;
- (void)stopPullingSignalingMessages;
- (void)sendSignalingMessage:(NCSignalingMessage *)message;

@end
