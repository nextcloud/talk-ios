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
#import "NCUtils.h"

typedef enum NCTextColorStyle {
    NCTextColorStyleLight = 0,
    NCTextColorStyleDark
} NCTextColorStyle;

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
    return [NCUtils colorFromHexString:brandColorHex];
}

+ (UIColor *)brandTextColor
{
    return [NCUtils colorFromHexString:brandTextColorHex];
}

+ (UIColor *)themeColor
{
    UIColor *color = [NCUtils colorFromHexString:brandColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && serverCapabilities.color && ![serverCapabilities.color isKindOfClass:[NSNull class]] && ![serverCapabilities.color isEqualToString:@""]) {
            UIColor *themeColor = [NCUtils colorFromHexString:serverCapabilities.color];
            if (themeColor) {
                color = themeColor;
            }
        }
    }
    return color;
}

+ (UIColor *)themeTextColor
{
    UIColor *textColor = [NCUtils colorFromHexString:brandTextColorHex];
    if (useServerThemimg) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
        if (serverCapabilities && serverCapabilities.colorText && ![serverCapabilities.colorText isKindOfClass:[NSNull class]] && ![serverCapabilities.colorText isEqualToString:@""]) {
            UIColor *themeTextColor = [NCUtils colorFromHexString:serverCapabilities.colorText];
            if (themeTextColor) {
                textColor = themeTextColor;
            }
        }
    }
    return textColor;
}

+ (UIColor *)elementColor
{
    UIColor *elementColor = [NCUtils colorFromHexString:brandColorHex];
    // Do not check if using server theming or not for now
    // We could check it once we calculate color element locally
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities && serverCapabilities.colorElement && ![serverCapabilities.colorElement isKindOfClass:[NSNull class]] && ![serverCapabilities.colorElement isEqualToString:@""]) {
        UIColor *color = [NCUtils colorFromHexString:serverCapabilities.colorElement];
        if (color) {
            elementColor = color;
        }
    }
    return elementColor;
}

+ (NSString *)navigationLogoImageName
{
    NSString *imageName = @"navigationLogo";
    if (!customNavigationLogo) {
        if (useServerThemimg && [self textColorStyleForBackgroundColor:[self themeColor]] == NCTextColorStyleDark) {
            imageName = @"navigationLogoDark";
        } else if ([self brandTextColorStyle] == NCTextColorStyleDark) {
            imageName = @"navigationLogoDark";
        }
    }
    return imageName;
}

+ (UIColor *)placeholderColor
{
    return [UIColor colorWithRed: 0.84 green: 0.84 blue: 0.84 alpha: 1.00]; // #d5d5d5
}

+ (UIStatusBarStyle)statusBarStyleForBrandColor
{
    return [self statusBarStyleForTextColorStyle:[self brandTextColorStyle]];
}

+ (UIStatusBarStyle)statusBarStyleForThemeColor
{
    if (useServerThemimg) {
        NCTextColorStyle style = [self textColorStyleForBackgroundColor:[self themeColor]];
        return [self statusBarStyleForTextColorStyle:style];
    }
    return [self statusBarStyleForBrandColor];
}

+ (UIStatusBarStyle)statusBarStyleForTextColorStyle:(NCTextColorStyle)style
{
    switch (style) {
        case NCTextColorStyleDark:
            return UIStatusBarStyleDefault;
            break;
        case NCTextColorStyleLight:
        default:
            return UIStatusBarStyleLightContent;
            break;
    }
}

+ (NCTextColorStyle)brandTextColorStyle
{
    // Dark style when brand text color is black
    if ([brandTextColorHex isEqualToString:@"#000000"]) {
        return NCTextColorStyleDark;
    }
    
    // Light style when brand text color is white
    if ([brandTextColorHex isEqualToString:@"#FFFFFF"]) {
        return NCTextColorStyleLight;
    }
    
    // Check brand-color luma when brand-text-color is neither black nor white
    return [self textColorStyleForBackgroundColor:[self brandColor]];
}

+ (NCTextColorStyle)textColorStyleForBackgroundColor:(UIColor *)color
{
    CGFloat luma = [NCUtils calculateLumaFromColor:color];
    return (luma > 0.6) ? NCTextColorStyleDark : NCTextColorStyleLight;
}

@end
