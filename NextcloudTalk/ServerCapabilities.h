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
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface ServerCapabilities : RLMObject

@property NSString *accountId;
@property NSString *name;
@property NSString *slogan;
@property NSString *url;
@property NSString *logo;
@property NSString *color;
@property NSString *colorElement;
@property NSString *colorElementBright;
@property NSString *colorElementDark;
@property NSString *colorText;
@property NSString *background;
@property BOOL backgroundDefault;
@property BOOL backgroundPlain;
@property NSString *version;
@property NSInteger versionMajor;
@property NSInteger versionMinor;
@property NSInteger versionMicro;
@property NSString *edition;
@property BOOL userStatus;
@property BOOL extendedSupport;
@property RLMArray<RLMString> *talkCapabilities;
@property NSInteger chatMaxLength;
@property BOOL canCreate;
@property BOOL attachmentsAllowed;
@property NSString *attachmentsFolder;
@property BOOL readStatusPrivacy;
@property BOOL accountPropertyScopesVersion2;
@property BOOL accountPropertyScopesFederationEnabled;
@property BOOL callEnabled;
@property NSString *talkVersion;
@property NSString *externalSignalingServerVersion;
@property BOOL guestsAppEnabled;
@property BOOL referenceApiSupported;
@property BOOL notificationsAppEnabled;

@end

NS_ASSUME_NONNULL_END
