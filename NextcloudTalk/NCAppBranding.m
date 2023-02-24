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
NSString * const copyright = @"© 2023 Nextcloud GmbH";
NSString * const bundleIdentifier = @"com.nextcloud.Talk";
NSString * const groupIdentifier = @"group.com.nextcloud.Talk";
NSString * const appsGroupIdentifier = @"group.com.nextcloud.apps";
NSString * const pushNotificationServer = @"https://push-notifications.nextcloud.com";
BOOL const multiAccountEnabled = YES;
BOOL const useAppsGroup = YES;
BOOL const forceDomain = NO;
NSString * const domain = nil;
NSString * const appAlternateVersion = @"16.0.0 (beta 4)";

+ (NSString *)getAppVersionString
{
    if ([appAlternateVersion length] > 0) {
        return appAlternateVersion;
    }

    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return appVersion;
}

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
        if (serverCapabilities && serverCapabilities.color) {
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
        if (serverCapabilities && serverCapabilities.colorText) {
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
    // Do not check if using server theming or not for now
    // We could check it once we calculate color element locally
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        UIColor *elementColorBright = [NCUtils colorFromHexString:serverCapabilities.colorElementBright];
        UIColor *elementColorDark = [NCUtils colorFromHexString:serverCapabilities.colorElementDark];

        if (elementColorBright && elementColorDark) {
            return [self getDynamicColor:elementColorBright withDarkMode:elementColorDark];
        }

        UIColor *color = [NCUtils colorFromHexString:serverCapabilities.colorElement];
        if (color) {
            return color;
        }
    }
    
    UIColor *elementColor = [NCUtils colorFromHexString:brandColorHex];
    return elementColor;
}

+ (UIColor *)getDynamicColor:(UIColor *)lightModeColor withDarkMode:(UIColor *)darkModeColor
{
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return darkModeColor;
        }
        
        return lightModeColor;
    }];
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
    return [UIColor placeholderTextColor];
}

+ (UIColor *)backgroundColor
{
    return [UIColor systemBackgroundColor];
}

+ (UIColor *)avatarPlaceholderColor
{
    // We will only use avatarPlaceholderColor for avatars that are on top theme/custom color.
    // For avatars that are on top of default background color (light or dark), we will use placeholderColor.
    UIColor *light = [UIColor colorWithRed: 0.7 green: 0.7 blue: 0.7 alpha: 1.00];
    UIColor *dark = [UIColor colorWithRed: 0.35 green: 0.35 blue: 0.35 alpha: 1.00];
    return [self getDynamicColor:light withDarkMode:dark];
}

+ (UIColor *)chatForegroundColor
{
    return [self getDynamicColor:[UIColor darkGrayColor] withDarkMode:[UIColor labelColor]];
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
    if (style == NCTextColorStyleDark) {
        return UIStatusBarStyleDarkContent;
    }

    return UIStatusBarStyleLightContent;
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
