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

@implementation NCRoomParticipant

+ (instancetype)participantWithDictionary:(NSDictionary *)participantDict
{
    if (!participantDict) {
        return nil;
    }
    
    NCRoomParticipant *participant = [[NCRoomParticipant alloc] init];
    participant.displayName = [participantDict objectForKey:@"displayName"];
    participant.inCall = [[participantDict objectForKey:@"inCall"] integerValue];
    participant.lastPing = [[participantDict objectForKey:@"lastPing"] integerValue];
    participant.participantType = (NCParticipantType)[[participantDict objectForKey:@"participantType"] integerValue];
    participant.sessionId = [participantDict objectForKey:@"sessionId"];
    participant.userId = [participantDict objectForKey:@"userId"];
    participant.status = [participantDict objectForKey:@"status"];
    
    id displayName = [participantDict objectForKey:@"displayName"];
    if ([displayName isKindOfClass:[NSString class]]) {
        participant.displayName = displayName;
    } else {
        participant.displayName = [displayName stringValue];
    }
    
    return participant;
}

- (BOOL)canModerate
{
    return _participantType == kNCParticipantTypeOwner || _participantType == kNCParticipantTypeModerator;
}

- (BOOL)isOffline
{
    return [_sessionId isEqualToString:@"0"] || [_sessionId isEqualToString:@""];
}

- (NSString *)participantId
{
    return (_participantType == kNCParticipantTypeGuest) ? _sessionId : _userId;
}

- (NSString *)displayName
{
    if (self.canModerate) {
        NSString *moderatorString = NSLocalizedString(@"moderator", nil);
        return [NSString stringWithFormat:@"%@ (%@)", _displayName, moderatorString];
    }
    return _displayName;
}
@end
