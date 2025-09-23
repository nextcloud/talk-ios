/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "NCMessageParameter.h"

@class NCChatFileStatus;

NS_ASSUME_NONNULL_BEGIN

@interface NCMessageFileParameter : NCMessageParameter

@property (nonatomic, strong) NSString * _Nullable path;
@property (nonatomic, strong) NSString * _Nullable mimetype;
@property (nonatomic, assign) NSInteger size;
@property (nonatomic, assign) BOOL previewAvailable;
@property (nonatomic, strong, nullable) NCChatFileStatus *fileStatus;
@property (nonatomic, assign) int previewImageHeight;
@property (nonatomic, assign) int previewImageWidth;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, strong, nullable) NSString *blurhash;

@end

NS_ASSUME_NONNULL_END
