/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCMessageFileParameter.h"

#import "NextcloudTalk-Swift.h"

@implementation NCMessageFileParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super initWithDictionary:parameterDict];
    if (self) {      
        self.path = [parameterDict objectForKey:@"path"];
        self.mimetype = [parameterDict objectForKey:@"mimetype"];
        self.size = [[parameterDict objectForKey:@"size"] integerValue];
        self.previewAvailable = [[parameterDict objectForKey:@"preview-available"] boolValue];
        self.previewImageHeight = [[parameterDict objectForKey:@"preview-image-height"] intValue];
        self.width = [[parameterDict objectForKey:@"width"] intValue];
        self.height = [[parameterDict objectForKey:@"height"] intValue];
    }
    
    return self;
}

@end
