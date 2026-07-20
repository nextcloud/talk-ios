/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCConversationTag.h"

NSString * const NCConversationTagTypeCustom    = @"custom";
NSString * const NCConversationTagTypeFavorites = @"favorites";
NSString * const NCConversationTagTypeOther     = @"other";

@implementation NCConversationTag

+ (instancetype)conversationTagWithDictionary:(NSDictionary *)tagDict andAccountId:(NSString *)accountId
{
    if (![tagDict isKindOfClass:[NSDictionary class]] || !accountId) {
        return nil;
    }

    id tagId = [tagDict objectForKey:@"id"];
    if (![tagId isKindOfClass:[NSString class]] || [tagId length] == 0) {
        return nil;
    }

    NCConversationTag *tag = [[self alloc] init];
    tag.accountId = accountId;
    tag.tagId = tagId;
    tag.internalId = [NSString stringWithFormat:@"%@@%@", accountId, tag.tagId];
    tag.sortOrder = [[tagDict objectForKey:@"sortOrder"] integerValue];
    tag.collapsed = [[tagDict objectForKey:@"collapsed"] boolValue];

    id name = [tagDict objectForKey:@"name"];
    tag.name = [name isKindOfClass:[NSString class]] ? name : @"";

    id type = [tagDict objectForKey:@"type"];
    tag.type = [type isKindOfClass:[NSString class]] ? type : NCConversationTagTypeCustom;

    return tag;
}

+ (NSString *)primaryKey {
    return @"internalId";
}

@end
