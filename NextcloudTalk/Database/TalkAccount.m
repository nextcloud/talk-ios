/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "TalkAccount.h"

@implementation TalkAccount

+ (NSString *)primaryKey
{
    return @"accountId";
}

@end
