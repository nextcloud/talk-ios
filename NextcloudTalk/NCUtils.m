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

static NSString *const nextcloudScheme = @"nextcloud:";

@implementation NCUtils

+ (NSString *)previewImageForFileExtension:(NSString *)fileExtension
{
    CFStringRef fileExtensionSR = (__bridge CFStringRef)fileExtension;
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtensionSR, NULL);
    return [self previewImageForFileType:fileUTI];
}

+ (NSString *)previewImageForFileMIMEType:(NSString *)fileMIMEType
{
    if (!fileMIMEType || [fileMIMEType isKindOfClass:[NSNull class]] || [fileMIMEType isEqualToString:@""]) {
        return @"file";
    }
    CFStringRef fileMIMETypeSR = (__bridge CFStringRef)fileMIMEType;
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, fileMIMETypeSR, NULL);
    if (!UTTypeIsDeclared(fileUTI)) {
        // Folders
        if ([fileMIMEType isEqualToString:@"httpd/unix-directory"]) {
            return @"folder";
        }
        // Default
        return @"file";
    }
    return [self previewImageForFileType:fileUTI];
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
+ (NSString *)readableDateFromDate:(NSDate *)date
{
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    dateFormatter.doesRelativeDateFormatting = YES;
    return [dateFormatter stringFromDate:date];
}

+ (NSString *)getTimeFromDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm"];
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
        return [NSString stringWithFormat:NSLocalizedString(@"%d minutes ago", nil), diff];
    } else if (ti < 86400) {
        // This day
        int diff = round(ti / 60 / 60);
        return[NSString stringWithFormat:NSLocalizedString(@"%d hours ago", nil), diff];
    } else if (ti < 86400 * 30) {
        // This month
        int diff = round(ti / 60 / 60 / 24);
        return[NSString stringWithFormat:NSLocalizedString(@"%d days ago", nil), diff];
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
    return [UIImage imageWithCGImage:CGImageCreateWithImageInRect(cgImage, cropRect)];
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

@end
