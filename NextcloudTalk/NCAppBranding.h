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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCAppBranding : NSObject

// App configuration
extern NSString * const talkAppName;
extern NSString * const filesAppName;
extern NSString * const copyright;
extern NSString * const bundleIdentifier;
extern NSString * const groupIdentifier;
extern NSString * const appsGroupIdentifier;
extern NSString * const pushNotificationServer;
extern BOOL const multiAccountEnabled;
extern BOOL const useAppsGroup;
extern BOOL const forceDomain;
extern NSString * const domain;
extern BOOL const customNavigationLogo;

+ (NSString *)getAppVersionString;

// Theming
+ (UIColor *)brandColor;
+ (UIColor *)brandTextColor;
+ (UIColor *)themeColor;
+ (UIColor *)themeTextColor;
+ (UIColor *)elementColor;
+ (NSString *)navigationLogoImageName;
+ (UIColor *)placeholderColor;
+ (UIColor *)backgroundColor;
+ (UIColor *)avatarPlaceholderColor;
+ (UIColor *)chatForegroundColor;
+ (UIStatusBarStyle)statusBarStyleForBrandColor;
+ (UIStatusBarStyle)statusBarStyleForThemeColor;

@end

NS_ASSUME_NONNULL_END
