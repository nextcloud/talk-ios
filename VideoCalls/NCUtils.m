//
//  NCUtils.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "NCUtils.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <CommonCrypto/CommonDigest.h>

#import "NCDatabaseManager.h"

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
        else if (UTTypeConformsTo(fileType, kUTTypeText)) previewImage = @"file-text";
        else if ([(__bridge NSString *)fileType containsString:@"org.openxmlformats"] || [(__bridge NSString *)fileType containsString:@"org.oasis-open.opendocument"]) previewImage = @"file-document";
        else if (UTTypeConformsTo(fileType, kUTTypeZipArchive)) previewImage = @"file-zip";
    }
    return previewImage;
}

 + (BOOL)isNextcloudAppInstalled
{
    NSURL *url = [NSURL URLWithString:nextcloudScheme];
    return [[UIApplication sharedApplication] canOpenURL:url];
}

+ (void)openFileInNextcloudApp:(NSString *)path withFileLink:(NSString *)link
{
    if (![self isNextcloudAppInstalled]) {
        return;
    }
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *nextcloudURLString = [NSString stringWithFormat:@"%@//open-file?path=%@&user=%@&link=%@", nextcloudScheme, path, activeAccount.user, link];
    NSURL *nextcloudURL = [NSURL URLWithString:[nextcloudURLString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    [[UIApplication sharedApplication] openURL:nextcloudURL options:@{} completionHandler:nil];
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
    
    return [dateFormatter stringFromDate:date];
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

+ (UIColor *)darkerColorFromColor:(UIColor *)color
{
    CGFloat h, s, b, a;
    if ([color getHue:&h saturation:&s brightness:&b alpha:&a])
        return [UIColor colorWithHue:h
                          saturation:s
                          brightness:b * 0.95
                               alpha:a];
    return nil;
}

@end
