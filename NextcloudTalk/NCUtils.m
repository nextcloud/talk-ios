/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "NCUtils.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <CommonCrypto/CommonDigest.h>

#import "OpenInFirefoxControllerObjC.h"

#import "NCDatabaseManager.h"
#import "NCUserDefaults.h"
#import "NSDate+DateTools.h"


static NSString *const nextcloudScheme = @"nextcloud:";

@implementation NCUtils

+ (NSString *)previewImageForFileExtension:(NSString *)fileExtension
{
    CFStringRef fileExtensionSR = (__bridge CFStringRef)fileExtension;
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtensionSR, NULL);
    NSString *result = [self previewImageForFileType:fileUTI];
    CFRelease(fileUTI);

    return result;
}

+ (NSString *)previewImageForFileMIMEType:(NSString *)fileMIMEType
{
    if (!fileMIMEType || [fileMIMEType isKindOfClass:[NSNull class]] || [fileMIMEType isEqualToString:@""]) {
        return @"file";
    }
    CFStringRef fileMIMETypeSR = (__bridge CFStringRef)fileMIMEType;
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, fileMIMETypeSR, NULL);

    NSString *resultImage = @"file";

    if ([fileMIMEType isEqualToString:@"httpd/unix-directory"]) {
        resultImage = @"folder";
    }

    if (UTTypeIsDeclared(fileUTI)) {
        resultImage = [self previewImageForFileType:fileUTI];
    }

    CFRelease(fileUTI);

    return resultImage;
}

+ (NSString *)previewImageForFileType:(CFStringRef)fileType
{
    NSString *previewImage = @"file";
    if (fileType) {
        if (UTTypeConformsTo(fileType, kUTTypeAudio)) previewImage = @"file-audio";
        else if (UTTypeConformsTo(fileType, kUTTypeMovie)) previewImage = @"file-video";
        else if (UTTypeConformsTo(fileType, kUTTypeImage)) previewImage = @"file-image";
        else if (UTTypeConformsTo(fileType, kUTTypeSpreadsheet)) previewImage = @"file-spreadsheet";
        else if (UTTypeConformsTo(fileType, kUTTypePresentation)) previewImage = @"file-presentation";
        else if (UTTypeConformsTo(fileType, kUTTypePDF)) previewImage = @"file-pdf";
        else if (UTTypeConformsTo(fileType, kUTTypeVCard)) previewImage = @"file-vcard";
        else if (UTTypeConformsTo(fileType, kUTTypeText)) previewImage = @"file-text";
        else if ([(__bridge NSString *)fileType containsString:@"org.openxmlformats"] || [(__bridge NSString *)fileType containsString:@"org.oasis-open.opendocument"]) previewImage = @"file-document";
        else if (UTTypeConformsTo(fileType, kUTTypeZipArchive)) previewImage = @"file-zip";
    }
    return previewImage;
}

+ (BOOL)isImageFileType:(NSString *)fileMIMEType
{
    return [[self previewImageForFileMIMEType:fileMIMEType] isEqual:@"file-image"];
}

+ (BOOL)isVideoFileType:(NSString *)fileMIMEType
{
    return [[self previewImageForFileMIMEType:fileMIMEType] isEqual:@"file-video"];
}

 + (BOOL)isNextcloudAppInstalled
{
    BOOL isInstalled = NO;
#ifndef APP_EXTENSION
    NSURL *url = [NSURL URLWithString:nextcloudScheme];
    isInstalled = [[UIApplication sharedApplication] canOpenURL:url];
#endif
    return isInstalled;
}

+ (void)openFileInNextcloudApp:(NSString *)path withFileLink:(NSString *)link
{
#ifndef APP_EXTENSION
    if (![self isNextcloudAppInstalled]) {
        return;
    }
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *nextcloudURLString = [NSString stringWithFormat:@"%@//open-file?path=%@&user=%@&link=%@", nextcloudScheme, path, activeAccount.user, link];
    NSURL *nextcloudURL = [NSURL URLWithString:[nextcloudURLString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[UIApplication sharedApplication] openURL:nextcloudURL options:@{} completionHandler:nil];
#endif
}

+ (void)openFileInNextcloudAppOrBrowser:(NSString *)path withFileLink:(NSString *)link
{
#ifndef APP_EXTENSION
    if (path && link) {
        if ([NCUtils isNextcloudAppInstalled]) {
            [NCUtils openFileInNextcloudApp:path withFileLink:link];
        } else {
            [self openLinkInBrowser:link];
        }
    }
#endif
}

+ (void)openLinkInBrowser:(NSString *)link
{
#ifndef APP_EXTENSION
    if (link) {
        NSURL *url = [NSURL URLWithString:link];
        if ([[NCUserDefaults defaultBrowser] isEqualToString:@"Firefox"] && [[OpenInFirefoxControllerObjC sharedInstance] isFirefoxInstalled]) {
            [[OpenInFirefoxControllerObjC sharedInstance] openInFirefox:url];
        } else {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
#endif
}

+ (NSDate *)dateFromDateAtomFormat:(NSString *)dateAtomFormatString
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    
    return [dateFormatter dateFromString:dateAtomFormatString];
}
+ (NSString *)dateAtomFormatFromDate:(NSDate *)date
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    
    return [dateFormatter stringFromDate:date];
}
+ (NSString *)readableDateTimeFromDate:(NSDate *)date
{
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    dateFormatter.doesRelativeDateFormatting = YES;
    return [dateFormatter stringFromDate:date];
}

+ (NSString *)readableTimeOrDateFromDate:(NSDate *)date
{
    if ([date isToday]) {
        return [self getTimeFromDate:date];
    } else if ([date isYesterday]) {
        return NSLocalizedString(@"Yesterday", nil);
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    [formatter setDateStyle:NSDateFormatterShortStyle];
    return [formatter stringFromDate:date];
}

+ (NSString *)getTimeFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    [formatter setDateStyle:NSDateFormatterNoStyle];
    return [formatter stringFromDate:date];
}

+ (NSString *)relativeTimeFromDate:(NSDate *)date
{
    NSDate *todayDate = [NSDate date];
    double ti = [date timeIntervalSinceDate:todayDate];
    ti = ti * -1;
    if (ti < 60) {
        // This minute
        return NSLocalizedString(@"less than a minute ago", nil);
    } else if (ti < 3600) {
        // This hour
        int diff = round(ti / 60);
        return [NSString localizedStringWithFormat:NSLocalizedString(@"%d minutes ago", nil), diff];
    } else if (ti < 86400) {
        // This day
        int diff = round(ti / 60 / 60);
        return[NSString localizedStringWithFormat:NSLocalizedString(@"%d hours ago", nil), diff];
    } else if (ti < 86400 * 30) {
        // This month
        int diff = round(ti / 60 / 60 / 24);
        return[NSString localizedStringWithFormat:NSLocalizedString(@"%d days ago", nil), diff];
    } else {
        // Older than one month
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setFormatterBehavior:NSDateFormatterBehavior10_4];
        [df setDateStyle:NSDateFormatterMediumStyle];
        return [df stringFromDate:date];
    }
}

+ (NSString *)sha1FromString:(NSString *)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    
    return output;
}

+ (UIImage *)blurImageFromImage:(UIImage *)image
{
    CGFloat inputRadius = 8.0f;
    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *inputImage = [[CIImage alloc] initWithImage:image];
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setValue:inputImage forKey:kCIInputImageKey];
    [filter setValue:[NSNumber numberWithFloat:inputRadius] forKey:@"inputRadius"];
    CIImage *result = [filter valueForKey:kCIOutputImageKey];
    CGRect imageRect = [inputImage extent];
    CGRect cropRect = CGRectMake(imageRect.origin.x + inputRadius, imageRect.origin.y + inputRadius, imageRect.size.width - inputRadius * 2, imageRect.size.height - inputRadius * 2);
    CGImageRef cgImage = [context createCGImage:result fromRect:imageRect];
    CGImageRef cgImageCroped = CGImageCreateWithImageInRect(cgImage, cropRect);

    UIImage *resultImage = [UIImage imageWithCGImage:cgImageCroped];
    CGImageRelease(cgImage);
    CGImageRelease(cgImageCroped);

    return resultImage;
}

+ (UIColor *)searchbarBGColorForColor:(UIColor *)color
{
    CGFloat luma = [self calculateLumaFromColor:color];
    return (luma > 0.6) ? [UIColor colorWithWhite:0 alpha:0.1] : [UIColor colorWithWhite:1 alpha:0.2];
}

+ (CGFloat)calculateLumaFromColor:(UIColor *)color
{
    CGFloat red, green, blue, alpha;
    [color getRed: &red green: &green blue: &blue alpha: &alpha];
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue);
}

+ (UIColor *)colorFromHexString:(NSString *)hexString
{
    BOOL isValidColorString = hexString && ![hexString isKindOfClass:[NSNull class]] && ![hexString isEqualToString:@""];
    
    if (!isValidColorString) {
        return nil;
    }
    
    // Check hex color string format (e.g."#00FF00")
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^#(?:[0-9a-fA-F]{6})$" options:NSRegularExpressionCaseInsensitive error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:hexString options:0 range:NSMakeRange(0, hexString.length)];
    if ([match numberOfRanges] != 1) {
        return nil;
    }
    
    // Convert Hex color to UIColor
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

+ (BOOL)isValidIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)tableView
{
    return indexPath.section < tableView.numberOfSections && indexPath.row < [tableView numberOfRowsInSection:indexPath.section];
}


+ (NSString *)valueForKey:(NSString *)key fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems filteredArrayUsingPredicate:predicate] firstObject];
    return queryItem.value;
}

+ (NSURL *)getLogfilePath
{
    NSURL *documentDir = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];

    if (!documentDir) {
        NSLog(@"Unable to retrieve document directory");
        return nil;
    }

    NSURL *logDir = [documentDir URLByAppendingPathComponent:@"logs"];
    NSString *logPath = [logDir path];

    // Allow writing to files while the app is in the background
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:logPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:logPath error:nil];

    return logDir;
}

+ (void)removeOldLogfiles
{
    NSURL *logPathURL = [self getLogfilePath];

    if (!logPathURL) {
        return;
    }

    NSString *logPath = [logPathURL path];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:logPath];

    NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
    dayComponent.day = -10;

    NSDate *thresholdDate = [[NSCalendar currentCalendar] dateByAddingComponents:dayComponent toDate:[NSDate date] options:0];
    NSString *file;

    while (file = [enumerator nextObject])
    {
        NSString *filePath = [logPath stringByAppendingPathComponent:file];
        NSDate *creationDate = [[fileManager attributesOfItemAtPath:filePath error:nil] fileCreationDate];

        if ([creationDate compare:thresholdDate] == NSOrderedAscending && [file hasPrefix:@"debug-"] && [file hasSuffix:@".log"]) {
            NSLog(@"Deleting old logfile %@", filePath);

            [fileManager removeItemAtPath:filePath error:nil];
        }
    }
}

+ (void)log:(NSString *)message
{
    @try {
        [self removeOldLogfiles];

        NSURL *logPath = [self getLogfilePath];

        if (!logPath) {
            return;
        }

        dispatch_queue_t currentQueue = dispatch_get_current_queue();

        int applicationState = -1;
        float backgroundTimeRemaining = -1;

    #ifndef APP_EXTENSION
        applicationState = (int)[UIApplication sharedApplication].applicationState;
        backgroundTimeRemaining = [UIApplication sharedApplication].backgroundTimeRemaining;
    #endif

        NSDate *now = [NSDate date];

        NSString *logMessage = [NSString stringWithFormat:@"%@ (%@): %@\nState: %d, Time remaining %f\n\n",
                                [now formattedDateWithFormat:@"y-MM-dd H:mm:ss.SSSS"],
                                [currentQueue description],
                                message,
                                applicationState,
                                backgroundTimeRemaining
        ];


        NSString *dateString = [now formattedDateWithFormat:@"yyyy-MM-dd"];
        NSString *logfileName = [NSString stringWithFormat:@"debug-%@.log", dateString];
        NSString *fullPath = [[logPath URLByAppendingPathComponent:logfileName] path];

        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:fullPath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        } else {
            [logMessage writeToFile:fullPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }

        NSLog(@"%@", logMessage);
    } @catch (NSException *exception) {
        NSLog(@"Exception in NCUtils.log: %@", exception.description);
        NSLog(@"Message: %@", message);
    }
}

+ (BOOL)isiOSAppOnMac
{
    return [NSProcessInfo processInfo].isiOSAppOnMac;
}

+ (NSString *)removeHTMLFromString:(NSString *)string
{
    // Preserve newlines
    string = [string stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithData:stringData
                                                                            options:@{NSDocumentTypeDocumentAttribute:NSHTMLTextDocumentType,
                                                                                      NSCharacterEncodingDocumentAttribute:@(NSUTF8StringEncoding)
                                                                                    }
                                                                 documentAttributes:nil
                                                                              error:&error];

    if (error) {
        return string;
    }

    return [attributedString string];
}

@end
