/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import "NCTypes.h"

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
