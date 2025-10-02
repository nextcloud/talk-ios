/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCPoll.h"

@implementation NCPoll

+ (instancetype)initWithPollDictionary:(NSDictionary *)pollDict
{
    if (!pollDict || ![pollDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NCPoll *poll = [[NCPoll alloc] init];
    poll.pollId = [[pollDict objectForKey:@"id"] integerValue];
    poll.question = [pollDict objectForKey:@"question"];
    poll.options = [pollDict objectForKey:@"options"];
    poll.votes = [pollDict objectForKey:@"votes"];
    poll.actorType = [pollDict objectForKey:@"actorType"];
    poll.actorId = [pollDict objectForKey:@"actorId"];
    poll.actorDisplayName = [pollDict objectForKey:@"actorDisplayName"];
    poll.status = (NCPollStatus)[[pollDict objectForKey:@"status"] integerValue];
    poll.resultMode = (NCPollResultMode)[[pollDict objectForKey:@"resultMode"] integerValue];
    poll.maxVotes = [[pollDict objectForKey:@"maxVotes"] integerValue];
    poll.votedSelf = [pollDict objectForKey:@"votedSelf"];
    poll.numVoters = [[pollDict objectForKey:@"numVoters"] integerValue];
    poll.details = [pollDict objectForKey:@"details"];
    
    if (![poll.votes isKindOfClass:[NSDictionary class]]) {
        poll.votes = @{};
    }
    
    if (![poll.options isKindOfClass:[NSArray class]]) {
        poll.options = @[];
    }
    
    if (![poll.votedSelf isKindOfClass:[NSArray class]]) {
        poll.votedSelf = @[];
    }
    
    if (![poll.details isKindOfClass:[NSArray class]]) {
        poll.details = @[];
    }
    
    return poll;
}

@end
