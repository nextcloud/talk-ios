/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


#import "FederatedCapabilities.h"

@implementation FederatedCapabilities

+ (NSString *)primaryKey
{
    return @"internalId";
}

+ (BOOL)shouldIncludeInDefaultSchema {
    return YES;
}

@end
