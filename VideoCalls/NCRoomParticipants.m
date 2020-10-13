//
//  NCRoomParticipant.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCRoomParticipant.h"

@implementation NCRoomParticipant

+ (instancetype)participantWithDictionary:(NSDictionary *)participantDict
{
    if (!participantDict) {
        return nil;
    }
    
    NCRoomParticipant *participant = [[NCRoomParticipant alloc] init];
    participant.displayName = [participantDict objectForKey:@"displayName"];
    participant.inCall = [[participantDict objectForKey:@"inCall"] boolValue];
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
