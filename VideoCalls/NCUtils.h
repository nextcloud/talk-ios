//
//  NCUtils.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCUtils : NSObject

+ (NSString *)previewImageForFileExtension:(NSString *)fileExtension;
+ (NSString *)previewImageForFileMIMEType:(NSString *)fileMIMEType;

@end

NS_ASSUME_NONNULL_END
