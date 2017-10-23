//
//  NCRoom.h
//  VideoCalls
//
//  Created by Ivan Sein on 12.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum NCRoomType {
    kNCRoomTypeOneToOneCall = 1,
    kNCRoomTypeGroupCall,
    kNCRoomTypePublicCall
} NCRoomType;

typedef enum NCParticipantType {
    kNCParticipantTypeOwner = 1,
    kNCParticipantTypeModerator,
    kNCParticipantTypeUser,
    kNCParticipantTypeGuest,
    kNCParticipantTypeUserFollowingLink
} NCParticipantType;

@interface NCRoom : NSObject

@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NCRoomType type;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) NCParticipantType participantType;
@property (nonatomic, assign) NSInteger lastPing;
@property (nonatomic, assign) NSInteger numGuests;
@property (nonatomic, copy) NSString *guestList;
@property (nonatomic, copy) NSArray *participants;

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict;

- (BOOL)canModerate;
- (BOOL)isNameEditable;
- (BOOL)isDeletable;

@end
