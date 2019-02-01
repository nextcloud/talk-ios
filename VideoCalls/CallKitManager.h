//
//  CallKitManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 09.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const CallKitManagerDidAnswerCallNotification;
extern NSString * const CallKitManagerDidEndCallNotification;
extern NSString * const CallKitManagerDidStartCallNotification;

@interface CallKitManager : NSObject

@property (nonatomic, strong) NSUUID *currentCallUUID;
@property (nonatomic, strong) NSString *currentCallToken;

+ (instancetype)sharedInstance;
- (void)reportIncomingCallForRoom:(NSString *)token withDisplayName:(NSString *)displayName;
- (void)startCall:(NSString *)token withVideoEnabled:(BOOL)videoEnabled andDisplayName:(NSString *)displayName;
- (void)endCurrentCall;


@end
