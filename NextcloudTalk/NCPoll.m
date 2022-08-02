/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
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
