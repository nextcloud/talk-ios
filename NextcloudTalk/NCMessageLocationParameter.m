/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCMessageLocationParameter.h"

@implementation NCMessageLocationParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super initWithDictionary:parameterDict];
    if (self) {
        self.latitude = [parameterDict objectForKey:@"latitude"];
        self.longitude = [parameterDict objectForKey:@"longitude"];
    }
    
    return self;
}

@end
