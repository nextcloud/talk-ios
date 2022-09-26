//
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

#import "NCUserDefaults.h"

#import "NCKeyChainController.h"

@implementation NCUserDefaults

NSString * const kNCUserDefaultBrowser          = @"ncUserDefaultBrowser";
NSString * const kNCPreferredCameraFlashMode    = @"ncPreferredCameraFlashMode";

+ (void)setDefaultBrowser:(NSString *)defaultBrowser
{
    [[NSUserDefaults standardUserDefaults] setObject:defaultBrowser forKey:kNCUserDefaultBrowser];
}

+ (NSString *)defaultBrowser
{
    NSString *browser = [[NSUserDefaults standardUserDefaults] objectForKey:kNCUserDefaultBrowser];
    if (!browser) {
        browser = @"Safari";
        // Legacy
        NSString *oldDefaultBrowser = [[NCKeyChainController sharedInstance].keychain stringForKey:kNCUserDefaultBrowser];
        if (oldDefaultBrowser) {
            browser = oldDefaultBrowser;
        }
        [[NSUserDefaults standardUserDefaults] setObject:browser forKey:kNCUserDefaultBrowser];
    }
    return browser;
}

+ (void)setPreferredCameraFlashMode:(NSInteger)flashMode
{
    [[NSUserDefaults standardUserDefaults] setObject:@(flashMode) forKey:kNCPreferredCameraFlashMode];
}

+ (NSInteger)preferredCameraFlashMode
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCPreferredCameraFlashMode] integerValue];
}

@end
