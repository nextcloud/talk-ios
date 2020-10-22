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

#import "NCAppBranding.h"

@implementation NCAppBranding

#pragma mark - Domain & Accounts

BOOL const multiAccountEnabled = YES;
BOOL const forceDomain = NO;
NSString * const domain = nil;

#pragma mark - Theming

NSString * const brandColor = @"#0082C9";
NSString * const brandTextColor = @"#FFFFFF";
BOOL const customNavigationLogo = NO;

+ (UIColor *)brandPrimaryColor
{
    return [self colorFromHexString:brandColor];
}

+ (UIColor *)brandPrimaryTextColor
{
    return [self colorFromHexString:brandTextColor];
}

+ (UIColor *)primaryColor
{
    return [self colorFromHexString:brandColor];
}

+ (UIColor *)primaryTextColor
{
    UIColor *primaryTextColor = [UIColor whiteColor];
    if ([self calculateLuma] > 0.6) {
        primaryTextColor = [UIColor blackColor];
    }
    return primaryTextColor;
}

+ (CGFloat)calculateLuma
{
    CGFloat red, green, blue, alpha;
    [[self primaryColor] getRed: &red green: &green blue: &blue alpha: &alpha];
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue);
}

+ (UIColor *)colorFromHexString:(NSString *)hexString
{
    // Hex color "#00FF00" to UIColor.
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

+ (NSString *)navigationLogoImageName
{
    NSString *imageName = @"navigationLogo";
    if (!customNavigationLogo && [self calculateLuma] > 0.6) {
        imageName = @"navigationLogoDark";
    }
    return imageName;
}

@end
