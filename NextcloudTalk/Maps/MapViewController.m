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

    UIImage *shareImage = [UIImage systemImageNamed:@"square.and.arrow.up"];
    UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithImage:shareImage style:UIBarButtonItemStylePlain
                                                                   target:nil action:nil];
    shareButton.menu = [self shareOptionsMenu];
    self.navigationItem.rightBarButtonItem = shareButton;
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

- (UIMenu *)shareOptionsMenu
{
    UIAction *appleMapsAction = [UIAction actionWithTitle:NSLocalizedString(@"Open in Maps", nil)
                                                    image:nil
                                               identifier:nil
                                                  handler:^(UIAction *action) {
        [self openInMaps:self->_annotation.coordinate];
    }];

    UIAction *googleMapsAction = nil;

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"comgooglemaps://"]]) {
        googleMapsAction = [UIAction actionWithTitle:NSLocalizedString(@"Open in Google Maps", nil)
                                               image:nil
                                          identifier:nil
                                             handler:^(UIAction *action) {
            [self openInGoogleMaps:self->_annotation.coordinate];
        }];
    }

    NSMutableArray *actions = [NSMutableArray arrayWithObject:appleMapsAction];
    if (googleMapsAction) {
        [actions addObject:googleMapsAction];
    }

    return [UIMenu menuWithTitle:@"" children:actions];
}


#pragma mark - Map view

- (void)centerMapViewInSharedLocation
{
    MKCoordinateRegion mapRegion;
    mapRegion.center = _annotation.coordinate;
    mapRegion.span = MKCoordinateSpanMake(0.005, 0.005);
    [self.mapView setRegion:mapRegion animated:YES];
}

#pragma mark - Utils

- (void)openInMaps:(CLLocationCoordinate2D)coordinate {
    MKPlacemark *placemark = [[MKPlacemark alloc] initWithCoordinate:coordinate];
    MKMapItem *mapItem = [[MKMapItem alloc] initWithPlacemark:placemark];
    mapItem.name = NSLocalizedString(@"Shared location", nil);

    NSDictionary *options = @{
        MKLaunchOptionsMapCenterKey: [NSValue valueWithMKCoordinate:coordinate]
    };

    [mapItem openInMapsWithLaunchOptions:options];
}

- (void)openInGoogleMaps:(CLLocationCoordinate2D)coordinate {
    NSString *urlString = [NSString stringWithFormat:
                           @"comgooglemaps://?q=%f,%f&center=%f,%f&zoom=14",
                           coordinate.latitude,
                           coordinate.longitude,
                           coordinate.latitude,
                           coordinate.longitude];

    NSURL *url = [NSURL URLWithString:urlString];

    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
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
