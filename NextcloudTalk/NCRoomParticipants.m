/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCRoomParticipant.h"

#import "CallConstants.h"
#import "NCDatabaseManager.h"

NSString * const NCAttendeeTypeUser     = @"users";
NSString * const NCAttendeeTypeGroup    = @"groups";
NSString * const NCAttendeeTypeCircle   = @"circles";
NSString * const NCAttendeeTypeTeams    = @"teams";
NSString * const NCAttendeeTypeGuest    = @"guests";
NSString * const NCAttendeeTypeEmail    = @"emails";
NSString * const NCAttendeeTypeFederated = @"federated_users";
NSString * const NCAttendeeTypeBots     = @"bots";

NSString * const NCAttendeeBotPrefix    = @"bot-";

NSString * const NCAttendeeBridgeBotId  = @"bridge-bot";

@implementation NCRoomParticipant

+ (instancetype)participantWithDictionary:(NSDictionary *)participantDict
{
    if (!participantDict) {
        return nil;
    }
    
    NCRoomParticipant *participant = [[NCRoomParticipant alloc] init];
    participant.attendeeId = [[participantDict objectForKey:@"attendeeId"] integerValue];
    participant.actorType = [participantDict objectForKey:@"actorType"];
    participant.actorId = [participantDict objectForKey:@"actorId"];
    participant.displayName = [participantDict objectForKey:@"displayName"];
    participant.inCall = [[participantDict objectForKey:@"inCall"] integerValue];
    participant.lastPing = [[participantDict objectForKey:@"lastPing"] integerValue];
    participant.participantType = (NCParticipantType)[[participantDict objectForKey:@"participantType"] integerValue];
    participant.sessionId = [participantDict objectForKey:@"sessionId"];
    participant.sessionIds = [participantDict objectForKey:@"sessionIds"];
    participant.userId = [participantDict objectForKey:@"userId"];
    
    id displayName = [participantDict objectForKey:@"displayName"];
    if ([displayName isKindOfClass:[NSString class]]) {
        participant.displayName = displayName;
    } else {
        participant.displayName = [displayName stringValue];
    }
    
    // Optional attribute
    id status = [participantDict objectForKey:@"status"];
    if ([status isKindOfClass:[NSString class]]) {
        participant.status = status;
    }
    
    // Optional attribute
    id statusIcon = [participantDict objectForKey:@"statusIcon"];
    if ([statusIcon isKindOfClass:[NSString class]]) {
        participant.statusIcon = statusIcon;
    }
    
    // Optional attribute
    id statusMessage = [participantDict objectForKey:@"statusMessage"];
    if ([statusMessage isKindOfClass:[NSString class]]) {
        participant.statusMessage = statusMessage;
    }

    // Optional attributed for email guests
    id invitedActorId = [participantDict objectForKey:@"invitedActorId"];
    if ([invitedActorId isKindOfClass:[NSString class]]) {
        participant.invitedActorId = invitedActorId;
    }

    return participant;
}

- (BOOL)canModerate
{
    return _participantType == kNCParticipantTypeOwner || _participantType == kNCParticipantTypeModerator || _participantType == kNCParticipantTypeGuestModerator;
}

- (BOOL)canBePromoted
{
    // In Talk 5 guest moderators were introduced
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityInviteGroupsAndMails]) {
        BOOL allowedActorType = [_actorType isEqualToString:NCAttendeeTypeUser] || [_actorType isEqualToString:NCAttendeeTypeGuest] || [_actorType isEqualToString:NCAttendeeTypeEmail];
        return !self.canModerate && allowedActorType;
    }
    return _participantType == kNCParticipantTypeUser;
}

- (BOOL)canBeDemoted
{
    return _participantType == kNCParticipantTypeModerator || _participantType == kNCParticipantTypeGuestModerator;
}

- (BOOL)canBeModerated
{
    return _participantType != kNCParticipantTypeOwner && ![self isAppUser];
}

- (BOOL)canBeBanned
{
    return [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityBanV1] && !self.isGroup && !self.isTeam && !self.isFederated && !self.canModerate;
}

- (BOOL)canBeNotifiedAboutCall
{
    return ![self isAppUser] &&
            self.inCall == CallFlagDisconnected &&
            [self.actorType isEqualToString:NCAttendeeTypeUser] &&
            [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySendCallNotification];
}

- (BOOL)isAppUser
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([self.participantId isEqualToString:activeAccount.userId]) {
        return YES;
    }
    return NO;
}

- (BOOL)isBridgeBotUser
{
    return [_actorType isEqualToString:NCAttendeeTypeUser] && [_actorId isEqualToString:NCAttendeeBridgeBotId];
}

- (BOOL)isGuest
{
    return _participantType == kNCParticipantTypeGuest || _participantType == kNCParticipantTypeGuestModerator;
}

- (BOOL)isGroup
{
    return [_actorType isEqualToString:NCAttendeeTypeGroup];
}

- (BOOL)isTeam
{
    return [_actorType isEqualToString:NCAttendeeTypeCircle] || [_actorType isEqualToString:NCAttendeeTypeTeams];
}

- (BOOL)isFederated
{
    return [_actorType isEqualToString:NCAttendeeTypeFederated];
}

- (BOOL)isOffline
{
    return ([_sessionId isEqualToString:@"0"] || [_sessionId isEqualToString:@""] || !_sessionId) && _sessionIds.count == 0;
}

- (NSString *)participantId
{
    // Conversation API v3
    if (_actorId) {
        return _actorId;
    }
    return (self.isGuest) ? _sessionId : _userId;
}

- (NSString *)detailedName
{
    NSString *detailedNameString = _displayName;

    BOOL defaultGuestNameUsed = false;
    if ([_displayName isEqualToString:@""]) {
        if (self.isGuest) {
            defaultGuestNameUsed = true;
            detailedNameString = NSLocalizedString(@"Guest", nil);
        } else {
            detailedNameString = NSLocalizedString(@"[Unknown username]", nil);
        }
    }
    // Moderator label
    if (self.canModerate) {
        NSString *moderatorString = NSLocalizedString(@"moderator", nil);
        detailedNameString = [NSString stringWithFormat:@"%@ (%@)", detailedNameString, moderatorString];
    }
    // Bridge bot label
    if (self.isBridgeBotUser) {
        NSString *botString = NSLocalizedString(@"bot", nil);
        detailedNameString = [NSString stringWithFormat:@"%@ (%@)", detailedNameString, botString];
    }
    // Guest label
    if (self.isGuest && !defaultGuestNameUsed) {
        NSString *guestString = NSLocalizedString(@"guest", nil);
        detailedNameString = [NSString stringWithFormat:@"%@ (%@)", detailedNameString, guestString];
    }
    return detailedNameString;
}

- (NSString *)callIconImageName
{
    if (self.inCall == CallFlagDisconnected) {
        return nil;
    }
    
    if ((self.inCall & CallFlagWithVideo) != 0) {
        return @"video";
    }
    
    if ((self.inCall & CallFlagWithPhone) != 0) {
        return @"phone";
    }
    
    return @"mic";
}

@end
