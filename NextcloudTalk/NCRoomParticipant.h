/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NCParticipantType) {
    kNCParticipantTypeOwner = 1,
    kNCParticipantTypeModerator,
    kNCParticipantTypeUser,
    kNCParticipantTypeGuest,
    kNCParticipantTypeUserSelfJoined,
    kNCParticipantTypeGuestModerator
};

extern NSString * const NCAttendeeTypeUser;
extern NSString * const NCAttendeeTypeGroup;
extern NSString * const NCAttendeeTypeCircle;
extern NSString * const NCAttendeeTypeTeams;
extern NSString * const NCAttendeeTypeGuest;
extern NSString * const NCAttendeeTypeEmail;
extern NSString * const NCAttendeeTypeFederated;
extern NSString * const NCAttendeeTypeBots;

extern NSString * const NCAttendeeBotPrefix;

extern NSString * const NCAttendeeBridgeBotId;

@interface NCRoomParticipant : NSObject

@property (nonatomic, assign) NSInteger attendeeId;
@property (nonatomic, copy) NSString *actorType;
@property (nonatomic, copy) NSString *actorId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NSInteger inCall;
@property (nonatomic, assign) NSInteger lastPing;
@property (nonatomic, assign) NCParticipantType participantType;
@property (nonatomic, copy) NSString *sessionId; // Deprecated in Conversations APIv4
@property (nonatomic, copy) NSArray *sessionIds;
@property (nonatomic, copy) NSString *userId; // Deprecated in Conversations APIv3
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *statusIcon;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, copy) NSString *callIconImageName;
@property (nonatomic, copy) NSString *invitedActorId;

+ (instancetype)participantWithDictionary:(NSDictionary *)userDict;
- (BOOL)canModerate;
- (BOOL)canBePromoted;
- (BOOL)canBeDemoted;
- (BOOL)canBeModerated;
- (BOOL)canBeBanned;
- (BOOL)canBeNotifiedAboutCall;
- (BOOL)isAppUser;
- (BOOL)isBridgeBotUser;
- (BOOL)isGuest;
- (BOOL)isGroup;
- (BOOL)isTeam;
- (BOOL)isOffline;
- (BOOL)isFederated;
- (NSString *)detailedName;
- (NSString *)participantId;

@end
