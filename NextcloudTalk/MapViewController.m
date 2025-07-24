//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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

    [NCAppBranding styleViewController:self];

    self.navigationItem.title = NSLocalizedString(@"Shared location", nil);

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
