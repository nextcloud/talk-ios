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

#import "NCDatabaseManager.h"

@implementation NCAppBranding

#pragma mark - App configuration

NSString * const talkAppName = @"Nextcloud Talk";
NSString * const filesAppName = @"Nextcloud";
NSString * const copyright = @"© 2020 Nextcloud GmbH";
NSString * const bundleIdentifier = @"com.nextcloud.Talk";
NSString * const groupIdentifier = @"group.com.nextcloud.Talk";
NSString * const pushNotificationServer = @"https://push-notifications.nextcloud.com";
BOOL const multiAccountEnabled = YES;
BOOL const forceDomain = NO;
NSString * const domain = nil;

#pragma mark - Theming

NSString * const brandColorHex = @"#0082C9";
NSString * const brandTextColorHex = @"#FFFFFF";
BOOL const customNavigationLogo = NO;
BOOL const useServerThemimg = YES;

+ (UIColor *)brandColor
{
    return [self colorFromHexString:brandColorHex];
}

+ (UIColor *)brandTextColor
{
    return [self colorFromHexString:brandTextColorHex];
}

+ (UIColor *)themeColor
{
    UIColor *color = [self colorFromHexString:brandColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && ![serverCapabilities.color isEqualToString:@""]) {
            color = [self colorFromHexString:serverCapabilities.color];
        }
    }
    return color;
}

+ (UIColor *)themeTextColor
{
    UIColor *textColor = [self colorFromHexString:brandTextColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && ![serverCapabilities.colorText isEqualToString:@""]) {
            textColor = [self colorFromHexString:serverCapabilities.colorText];
        }
    }
    return textColor;
}

+ (CGFloat)calculateLuma
{
    CGFloat red, green, blue, alpha;
    [[self themeColor] getRed: &red green: &green blue: &blue alpha: &alpha];
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
