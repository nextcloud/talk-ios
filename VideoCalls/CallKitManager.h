//
//  CallKitManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 09.01.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const CallKitManagerDidAnswerCallNotification;

@interface CallKitManager : NSObject

@property (nonatomic, strong) NSUUID *currentCallUUID;
@property (nonatomic, strong) NSString *currentCallToken;

+ (instancetype)sharedInstance;
- (void)reportIncomingCallForRoom:(NSString *)token withDisplayName:(NSString *)displayName;
- (void)endCurrentCall;


@end
