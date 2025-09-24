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

        NSString *mimetype = [parameterDict objectForKey:@"mimetype"];

        if ([mimetype isKindOfClass:[NSString class]]) {
            self.mimetype = mimetype;
        }

        self.size = [[parameterDict objectForKey:@"size"] integerValue];
        self.previewAvailable = [[parameterDict objectForKey:@"preview-available"] boolValue];
        self.previewImageHeight = [[parameterDict objectForKey:@"preview-image-height"] intValue];
        self.previewImageWidth = [[parameterDict objectForKey:@"preview-image-width"] intValue];
        self.width = [[parameterDict objectForKey:@"width"] intValue];
        self.height = [[parameterDict objectForKey:@"height"] intValue];
        
        // NCChatFileStatus parameters
        NSString *fileId = [parameterDict objectForKey:@"fileId"];
        NSString *fileName = [parameterDict objectForKey:@"fileName"];
        NSString *filePath = [parameterDict objectForKey:@"filePath"];
        NSString *fileLocalPath = [parameterDict objectForKey:@"fileLocalPath"];

        if (fileId && fileName && filePath && fileLocalPath) {
            self.fileStatus = [[NCChatFileStatus alloc] initWithFileId:fileId fileName:fileName filePath:filePath fileLocalPath:fileLocalPath];
        } else {
            self.fileStatus = nil;
        }

        self.blurhash = [parameterDict objectForKey:@"blurhash"];
    }
    
    return self;
}

@end
