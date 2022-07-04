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

#import "GeoLocationRichObject.h"

NSString * const GeoLocationRichObjectType = @"geo-location";

@implementation GeoLocationRichObject

+ (instancetype)geoLocationRichObjectWithLatitude:(double)latitude longitude:(double)longitude name:(NSString *)name
{
    GeoLocationRichObject *object = [[self alloc] init];
    NSString *latitudeString = [[NSNumber numberWithDouble:latitude] stringValue];
    NSString *longitudeString = [[NSNumber numberWithDouble:longitude] stringValue];
    object.objectType = GeoLocationRichObjectType;
    object.objectId = [NSString stringWithFormat:@"geo:%@,%@", latitudeString, longitudeString];
    object.latitude = latitudeString;
    object.longitude = longitudeString;
    object.name = name;
    return object;
}

+ (instancetype)geoLocationRichObjectFromMessageLocationParameter:(NCMessageLocationParameter *)parameter
{
    GeoLocationRichObject *richObject = [[self alloc] init];
    richObject.objectType = parameter.type;
    richObject.objectId = parameter.parameterId;
    richObject.latitude = parameter.latitude;
    richObject.longitude = parameter.longitude;
    richObject.name = parameter.name;
    return richObject;
}

- (NSDictionary *)metaData
{
    return @{
             @"latitude": self.latitude,
             @"longitude": self.longitude,
             @"name": self.name
             };
}

- (NSDictionary *)richObjectDictionary
{
    NSError *error;
    NSString *jsonString = @"";
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self metaData]
                                                       options:0
                                                         error:&error];
    
    if (!jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    return @{
             @"objectType": self.objectType,
             @"objectId": self.objectId,
             @"metaData": jsonString
             };
}

@end
