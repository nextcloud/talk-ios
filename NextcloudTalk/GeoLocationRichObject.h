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

#import "NCMessageLocationParameter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const GeoLocationRichObjectType;

@interface GeoLocationRichObject : NSObject

@property (nonatomic, copy) NSString *objectType;
@property (nonatomic, copy) NSString *objectId;
@property (nonatomic, copy) NSString *latitude;
@property (nonatomic, copy) NSString *longitude;
@property (nonatomic, copy) NSString *name;

+ (instancetype)geoLocationRichObjectWithLatitude:(double)latitude longitude:(double)longitude name:(NSString *)name;
+ (instancetype)geoLocationRichObjectFromMessageLocationParameter:(NCMessageLocationParameter *)parameter;
- (NSDictionary *)richObjectDictionary;

@end

NS_ASSUME_NONNULL_END
