/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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

    if ([parameter.latitude isKindOfClass:[NSNumber class]]) {
        richObject.latitude = [(NSNumber *)parameter.latitude stringValue];
    } else {
        richObject.latitude = parameter.latitude;
    }

    if ([parameter.longitude isKindOfClass:[NSNumber class]]) {
        richObject.longitude = [(NSNumber *)parameter.longitude stringValue];
    } else {
        richObject.longitude = parameter.longitude;
    }

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
