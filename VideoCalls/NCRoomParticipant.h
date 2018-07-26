//
//  NCRoomParticipant.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum NCParticipantType {
    kNCParticipantTypeOwner = 1,
    kNCParticipantTypeModerator,
    kNCParticipantTypeUser,
    kNCParticipantTypeGuest,
    kNCParticipantTypeUserSelfJoined
} NCParticipantType;

@interface NCRoomParticipant : NSObject

@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) NSInteger lastPing;
@property (nonatomic, assign) NCParticipantType participantType;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *userId;

+ (instancetype)participantWithDictionary:(NSDictionary *)userDict;
- (BOOL)canModerate;
- (BOOL)isOffline;
- (NSString *)participantId;

@end
