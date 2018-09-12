//
//  NCExternalSignalingController.h
//  VideoCalls
//
//  Created by Ivan Sein on 07.09.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NCExternalSignalingController : NSObject

+ (instancetype)sharedInstance;
- (BOOL)isEnabled;
- (void)setServer:(NSString *)serverUrl andTicket:(NSString *)ticket;
- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId;

@end
