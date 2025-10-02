/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCChatBlock : RLMObject

@property (nonatomic, strong) NSString *internalId; // accountId@token (same as room internal id)
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, assign) NSInteger threadId;
@property (nonatomic, assign) NSInteger oldestMessageId;
@property (nonatomic, assign) NSInteger newestMessageId;
@property (nonatomic, assign) BOOL hasHistory;

@end
NS_ASSUME_NONNULL_END
