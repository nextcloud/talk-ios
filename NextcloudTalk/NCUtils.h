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

@interface NCUtils : NSObject

+ (NSString *)previewImageForFileExtension:(NSString *)fileExtension;
+ (NSString *)previewImageForFileMIMEType:(NSString *)fileMIMEType;
+ (BOOL)isImageFileType:(NSString *)fileMIMEType;
+ (BOOL)isVideoFileType:(NSString *)fileMIMEType;

+ (BOOL)isNextcloudAppInstalled;
+ (void)openFileInNextcloudApp:(NSString *)path withFileLink:(NSString *)link;
+ (void)openFileInNextcloudAppOrBrowser:(NSString *)path withFileLink:(NSString *)link;
+ (void)openLinkInBrowser:(NSString *)link;

// https://www.php.net/manual/en/class.datetimeinterface.php#datetime.constants.atom
+ (NSDate *)dateFromDateAtomFormat:(NSString *)dateAtomFormatString;
+ (NSString *)dateAtomFormatFromDate:(NSDate *)date;
+ (NSString *)readableDateTimeFromDate:(NSDate *)date;
+ (NSString *)readableTimeOrDateFromDate:(NSDate *)date;
+ (NSString *)getTimeFromDate:(NSDate *)date;
+ (NSString *)relativeTimeFromDate:(NSDate *)date;

+ (NSString *)sha1FromString:(NSString *)string;

+ (UIImage *)blurImageFromImage:(UIImage *)image;

+ (UIColor *)searchbarBGColorForColor:(UIColor *)color;

+ (CGFloat)calculateLumaFromColor:(UIColor *)color;
+ (UIColor *)colorFromHexString:(NSString *)hexString;

+ (BOOL)isValidIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)tableView;

+ (NSString *)valueForKey:(NSString *)key fromQueryItems:(NSArray *)queryItems;

+ (void)log:(NSString *)message;

+ (BOOL)isiOSAppOnMac;

+ (NSString *)removeHTMLFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
