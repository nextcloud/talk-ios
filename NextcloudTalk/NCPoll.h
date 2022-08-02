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

#import <Foundation/Foundation.h>

typedef enum NCPollStatus {
    NCPollStatusOpen = 0,
    NCPollStatusClosed
} NCPollStatus;

typedef enum NCPollResultMode {
    NCPollResultModePublic = 0,
    NCPollResultModeHidden
} NCPollResultMode;

@interface NCPoll : NSObject

@property (nonatomic, assign) NSInteger pollId;
@property (nonatomic, strong) NSString *question;
@property (nonatomic, strong) NSArray *options;
@property (nonatomic, strong) NSDictionary *votes;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, assign) NCPollStatus status;
@property (nonatomic, assign) NCPollResultMode resultMode;
@property (nonatomic, assign) NSInteger maxVotes;
@property (nonatomic, strong) NSArray *votedSelf;
@property (nonatomic, assign) NSInteger numVoters;
@property (nonatomic, strong) NSArray *details;

+ (instancetype)initWithPollDictionary:(NSDictionary *)pollDict;

@end
