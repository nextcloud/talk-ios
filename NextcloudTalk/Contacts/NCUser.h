/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCContact.h"

typedef NS_ENUM(NSInteger, NCShareType) {
    NCShareTypeUser = 0,
    NCShareTypeGroup = 1,
    NCShareTypeEmail = 4,
    NCShareTypeRemote = 6,
    NCShareTypeCircle = 7
};

extern NSString * const kParticipantTypeUser;
extern NSString * const kParticipantTypeGroup;
extern NSString * const kParticipantTypeEmail;
extern NSString * const kParticipantTypeCircle;
extern NSString * const kParticipantTypeFederated;

@interface NCUser : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSString *source;

+ (instancetype)userWithDictionary:(NSDictionary *)userDict;
+ (instancetype)userFromNCContact:(NCContact *)contact;

+ (NSDictionary<NSString *, NSArray<NCUser *> *> *)indexedUsersFromUsersArray:(NSArray *)users;
// Duplicate users found in second array will be deleted
+ (NSArray<NCUser *> *)combineUsersArray:(NSArray *)firstArray withUsersArray:(NSArray *)secondArray;

@end
