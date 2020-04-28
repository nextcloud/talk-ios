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

+ (BOOL)isNextcloudAppInstalled;
+ (void)openFileInNextcloudApp:(NSString *)path withFileLink:(NSString *)link;

// https://www.php.net/manual/en/class.datetimeinterface.php#datetime.constants.atom
+ (NSDate *)dateFromDateAtomFormat:(NSString *)dateAtomFormatString;
+ (NSString *)dateAtomFormatFromDate:(NSDate *)date;
+ (NSString *)readableDateFromDate:(NSDate *)date;

+ (NSString *)sha1FromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
