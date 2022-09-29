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

#import "MapViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "GeoLocationRichObject.h"
#import "NCAppBranding.h"

@interface MapViewController () <CLLocationManagerDelegate, MKMapViewDelegate>
{
    CLLocationManager *_locationManager;
    MKPointAnnotation *_annotation;
}

@end

@implementation MapViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Shared location", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.navigationController.navigationBar.translucent = NO;

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;

    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    [_locationManager requestWhenInUseAuthorization];
    
    _mapView.delegate = self;
    [self centerMapViewInSharedLocation];
    [_mapView addAnnotation:_annotation];
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationItem.leftBarButtonItem = cancelButton;
}

- (instancetype)initWithGeoLocationRichObject:(GeoLocationRichObject *)geoLocation
{
    self = [super init];
    if (self) {
        _annotation = [[MKPointAnnotation alloc] init];
        _annotation.coordinate = CLLocationCoordinate2DMake([geoLocation.latitude doubleValue], [geoLocation.longitude doubleValue]);
        _annotation.title = geoLocation.name;
    }
    
    return self;
}

#pragma mark - Actions

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Map view

- (void)centerMapViewInSharedLocation
{
    MKCoordinateRegion mapRegion;
    mapRegion.center = _annotation.coordinate;
    mapRegion.span = MKCoordinateSpanMake(0.005, 0.005);
    [self.mapView setRegion:mapRegion animated:YES];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    // If the annotation is the user location, just return nil.
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }
    
    if (annotation == _annotation) {
        MKPinAnnotationView *pinView = (MKPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:@"SharedLocationAnnotationView"];
        if (!pinView) {
            pinView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"SharedLocationAnnotationView"];
            pinView.pinTintColor = [NCAppBranding elementColor];
            pinView.animatesDrop = YES;
            pinView.canShowCallout = YES;
        } else {
            pinView.annotation = annotation;
        }
        return pinView;
    }
    return nil;
}

@end
