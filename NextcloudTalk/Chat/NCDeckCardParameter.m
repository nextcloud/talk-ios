/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCDeckCardParameter.h"

@implementation NCDeckCardParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super initWithDictionary:parameterDict];
    if (self) {
        self.stackName = [parameterDict objectForKey:@"stackname"];
        self.boardName = [parameterDict objectForKey:@"boardname"];
    }
    
    return self;
}

@end
