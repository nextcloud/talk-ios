/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

extern NSString * const NCConversationTagTypeCustom;
extern NSString * const NCConversationTagTypeFavorites;
extern NSString * const NCConversationTagTypeOther;

@interface NCConversationTag : RLMObject

@property (nonatomic, copy, nonnull) NSString *internalId; // accountId@tagId
@property (nonatomic, copy, nonnull) NSString *accountId;
@property (nonatomic, copy) NSString *tagId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger sortOrder;
@property (nonatomic, assign) BOOL collapsed;
@property (nonatomic, copy) NSString *type;

+ (instancetype _Nullable)conversationTagWithDictionary:(NSDictionary * _Nullable)tagDict andAccountId:(NSString * _Nullable)accountId;

@end
