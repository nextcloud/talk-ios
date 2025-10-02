/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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
