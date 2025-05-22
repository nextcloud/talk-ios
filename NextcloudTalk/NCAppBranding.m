/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCAppBranding.h"

#import "NCDatabaseManager.h"

#import "NextcloudTalk-Swift.h"

typedef enum NCTextColorStyle {
    NCTextColorStyleLight = 0,
    NCTextColorStyleDark
} NCTextColorStyle;

@implementation NCAppBranding

#pragma mark - App configuration

NSString * const talkAppName = @"Nextcloud Talk";
NSString * const filesAppName = @"Nextcloud";
NSString * const copyright = @"© 2025 Nextcloud GmbH";
NSString * const bundleIdentifier = @"com.nextcloud.Talk";
NSString * const groupIdentifier = @"group.com.nextcloud.Talk";
NSString * const appsGroupIdentifier = @"group.com.nextcloud.apps";
NSString * const pushNotificationServer = @"https://push-notifications.nextcloud.com";
NSString * const privacyURL = @"https://nextcloud.com/privacy";
BOOL const isBrandedApp = NO;
BOOL const multiAccountEnabled = YES;
BOOL const useAppsGroup = YES;
BOOL const forceDomain = NO;
NSString * const domain = nil;
NSString * const appAlternateVersion = @"21.1.0 RC 2";

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
    UIColor *light = [NCUtils colorFromHexString:@"#dbdbdb"];
    UIColor *dark = [NCUtils colorFromHexString:@"#3b3b3b"];

    return [self getDynamicColor:light withDarkMode:dark];
}

+ (UIColor *)chatForegroundColor
{
    static UIColor *color;

    if (!color) {
        color = [self getDynamicColor:[UIColor darkGrayColor] withDarkMode:[UIColor labelColor]];
    }

    return color;
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

+ (void)styleViewController:(UIViewController *)controller {
    [controller.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    controller.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    controller.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    controller.navigationController.navigationBar.translucent = NO;
    controller.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    controller.navigationItem.standardAppearance = appearance;
    controller.navigationItem.compactAppearance = appearance;
    controller.navigationItem.scrollEdgeAppearance = appearance;

    // Fix uisearchcontroller animation
    controller.extendedLayoutIncludesOpaqueBars = YES;
}

@end
