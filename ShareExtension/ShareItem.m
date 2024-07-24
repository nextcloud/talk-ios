/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ShareItem.h"

@implementation ShareItem


+ (instancetype)initWithURL:(NSURL *)fileURL withName:(NSString *)fileName withPlaceholderImage:(UIImage *)placeholderImage isImage:(BOOL)isImage
{
    ShareItem* item = [[ShareItem alloc] init];
    item.fileURL = fileURL;
    item.filePath = fileURL.path;
    item.fileName = fileName;
    item.placeholderImage = placeholderImage;
    item.uploadProgress = 0;
    item.isImage = isImage;
    item.caption = @"";

    return item;
}

@end
