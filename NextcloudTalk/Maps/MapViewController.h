//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

#import "GeoLocationRichObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface MapViewController : UIViewController

@property (weak, nonatomic) IBOutlet MKMapView *mapView;

- (instancetype)initWithGeoLocationRichObject:(GeoLocationRichObject *)geoLocation;

@end

NS_ASSUME_NONNULL_END
