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
        if (serverCapabilities && ![serverCapabilities.color isEqualToString:@""]) {
            color = [NCUtils colorFromHexString:serverCapabilities.color];
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
        if (serverCapabilities && ![serverCapabilities.colorText isEqualToString:@""]) {
            textColor = [NCUtils colorFromHexString:serverCapabilities.colorText];
        }
    }
    return textColor;
}

+ (NSString *)navigationLogoImageName
{
    NSString *imageName = @"navigationLogo";
    if (!customNavigationLogo && [NCUtils calculateLumaFromColor:[self themeColor]] > 0.6) {
        imageName = @"navigationLogoDark";
    }
    return imageName;
}

+ (UIColor *)placeholderColor
{
    return [UIColor colorWithRed: 0.84 green: 0.84 blue: 0.84 alpha: 1.00]; // #d5d5d5
}

@end
