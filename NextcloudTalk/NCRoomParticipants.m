/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "NCRoomParticipant.h"

#import "CallConstants.h"
#import "NCDatabaseManager.h"

NSString * const NCAttendeeTypeUser     = @"users";
NSString * const NCAttendeeTypeGroup    = @"groups";
NSString * const NCAttendeeTypeCircle   = @"circles";
NSString * const NCAttendeeTypeGuest    = @"guests";
NSString * const NCAttendeeTypeEmail    = @"emails";

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
        return !self.canModerate && !self.isGroup && !self.isCircle && !self.isBridgeBotUser;
    }
    return _participantType == kNCParticipantTypeUser;
}

- (BOOL)canBeDemoted
{
    return _participantType == kNCParticipantTypeModerator || _participantType == kNCParticipantTypeGuestModerator;
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

- (BOOL)isCircle
{
    return [_actorType isEqualToString:NCAttendeeTypeCircle];
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
    if ([_displayName isEqualToString:@""]) {
        if (self.isGuest) {
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
    if (self.isGuest) {
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
    
    return @"audio";
}

@end
