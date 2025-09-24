/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ShareLocationViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "GeoLocationRichObject.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

typedef enum ShareLocationSection {
    kShareLocationSectionCurrent = 0,
    kShareLocationSectionDropPin,
    kShareLocationSectionNearby,
    kShareLocationSectionNumber
} ShareLocationSection;

@interface ShareLocationViewController () <CLLocationManagerDelegate, MKMapViewDelegate, UITableViewDelegate, UITableViewDataSource, UISearchControllerDelegate, UISearchResultsUpdating>
{
    UISearchController *_searchController;
    UITableViewController *_resultTableViewController;
    CLLocationManager *_locationManager;
    CLLocation *_currentLocation;
    NSArray *_nearbyPlaces;
    NSArray *_searchedPlaces;
    BOOL _hasBeenCentered;
    MKPointAnnotation *_dropPinAnnotation;
    CLPlacemark *_dropPinPlacemark;
    UIView *_dropPinGuideView;
    UIImageSymbolConfiguration *_iconsConfiguration;
}

@end

@implementation ShareLocationViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
    _searchController.delegate = self;
    _searchController.searchResultsUpdater = self;
    _searchController.hidesNavigationBarDuringPresentation = NO;
    [_searchController.searchBar sizeToFit];

    self.navigationItem.searchController = _searchController;

    [NCAppBranding styleViewController:self];

    UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
    searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search for places", nil)];

    self.navigationItem.title = NSLocalizedString(@"Share location", nil);

    _iconsConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20];

    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    [_locationManager requestWhenInUseAuthorization];
    
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    
    self.myLocationButton.layer.cornerRadius = 22;
    self.myLocationButton.clipsToBounds = YES;
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationItem.leftBarButtonItem = cancelButton;

    _resultTableViewController = [[UITableViewController alloc] init];
    _resultTableViewController.tableView.delegate = self;
    _resultTableViewController.tableView.dataSource = self;
    _resultTableViewController.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    // Place resultTableViewController correctly
    self.definesPresentationContext = YES;
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    CLAuthorizationStatus status = manager.authorizationStatus;

    _myLocationButton.hidden = YES;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        _myLocationButton.hidden = NO;
    } else if (status == kCLAuthorizationStatusNotDetermined) {
        [_locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusDenied) {
        [self showAuthorizationStatusDeniedAlert];
    }
}

- (void)showAuthorizationStatusDeniedAlert
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access your location", nil)
                                 message:NSLocalizedString(@"Location service has been denied. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* settingsButton = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil)
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }];
    [alert addAction:settingsButton];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation
{
    // Center the map view the first time the user location is updated
    if (!_hasBeenCentered) {
        _hasBeenCentered = YES;
        [self centerMapViewToUserLocation];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_currentLocation = mapView.userLocation.location;
        [self.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:kShareLocationSectionCurrent] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated
{
    [_mapView removeAnnotation:_dropPinAnnotation];
    [self showDropPinGuideView];
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    [self hideDropPinGuideView];
    _dropPinAnnotation = [[MKPointAnnotation alloc] init];
    _dropPinAnnotation.coordinate = CLLocationCoordinate2DMake(_mapView.centerCoordinate.latitude, _mapView.centerCoordinate.longitude);
    [_mapView addAnnotation:_dropPinAnnotation];
    
    CLLocation *location = [[CLLocation alloc] initWithLatitude:_dropPinAnnotation.coordinate.latitude longitude:_dropPinAnnotation.coordinate.longitude];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_dropPinPlacemark = placemarks[0];
                [self.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:kShareLocationSectionDropPin] withRowAnimation:UITableViewRowAnimationNone];
            });
        }
    }];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    // If the annotation is the user location, just return nil.
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }
    
    if (annotation == _dropPinAnnotation) {
        MKPinAnnotationView *pinView = (MKPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:@"SelectedLocationAnnotationView"];
        if (!pinView) {
            pinView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"SelectedLocationAnnotationView"];
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

#pragma mark - Actions

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)myLocationButtonPressed:(id)sender
{
    [self centerMapViewToUserLocation];
}

#pragma mark - Map View

- (void)centerMapViewToUserLocation
{
    MKCoordinateRegion mapRegion;
    mapRegion.center = self.mapView.userLocation.coordinate;
    mapRegion.span = MKCoordinateSpanMake(0.01, 0.01);
    [self.mapView setRegion:mapRegion animated: YES];
}

- (void)showDropPinGuideView
{
    _dropPinGuideView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
    _dropPinGuideView.backgroundColor = [NCAppBranding placeholderColor];
    _dropPinGuideView.layer.cornerRadius = 4;
    _dropPinGuideView.clipsToBounds = YES;
    
    _dropPinGuideView.center = _mapView.center;
        
    [self.mapView addSubview:_dropPinGuideView];
    [self.mapView bringSubviewToFront:_dropPinGuideView];
}

- (void)hideDropPinGuideView
{
    [_dropPinGuideView removeFromSuperview];
    _dropPinAnnotation = nil;
}


#pragma mark - Search places

- (void)searchForNearbyPlaces
{
    MKLocalPointsOfInterestRequest *request = [[MKLocalPointsOfInterestRequest alloc] initWithCoordinateRegion:self.mapView.region];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithPointsOfInterestRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        if (response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_nearbyPlaces = response.mapItems;
                [self.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:kShareLocationSectionNearby] withRowAnimation:UITableViewRowAnimationNone];
            });
        }
    }];
}

- (void)searchForPlacesWithString:(NSString *)searchString
{
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithNaturalLanguageQuery:searchString];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        if (response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_searchedPlaces = response.mapItems;
                [self->_resultTableViewController.tableView reloadData];
            });
        }
    }];
}

#pragma mark - Search controller

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self searchForPlacesWithString:_searchController.searchBar.text];
}

#pragma mark - UITableView delegate and data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == _resultTableViewController.tableView) {
        return _searchedPlaces.count;
    }
    
    if (section == kShareLocationSectionCurrent) {
        return _currentLocation ? 1 : 0;
    } else if (section == kShareLocationSectionDropPin) {
        return 1;
    } else if (section == kShareLocationSectionNearby) {
        return _nearbyPlaces.count;
    }
    
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == _resultTableViewController.tableView) {
        return 1;
    }
    
    return kShareLocationSectionNumber;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == kShareLocationSectionNearby && _nearbyPlaces.count > 0) {
        return NSLocalizedString(@"Nearby places", nil);;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Search result table view
    if (tableView == _resultTableViewController.tableView) {
        MKMapItem *searchedPlace = [_searchedPlaces objectAtIndex:indexPath.row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SearchedLocationCellIdentifier"];
        [cell.imageView setImage:[UIImage systemImageNamed:@"mappin" withConfiguration:_iconsConfiguration]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
        cell.textLabel.text = searchedPlace.name;
        NSString *subtitle = nil;
        if (searchedPlace.placemark.thoroughfare && searchedPlace.placemark.subThoroughfare) {
            subtitle = [NSString stringWithFormat:@"%@ %@, ", searchedPlace.placemark.thoroughfare, searchedPlace.placemark.subThoroughfare];
        }
        if (searchedPlace.placemark.locality) {
            subtitle = [subtitle stringByAppendingString:[NSString stringWithFormat:@"%@, ", searchedPlace.placemark.locality]];
        }
        if (searchedPlace.placemark.country) {
            subtitle = [subtitle stringByAppendingString:[NSString stringWithFormat:@"%@", searchedPlace.placemark.country]];;
        }
        cell.detailTextLabel.text = subtitle;
        return cell;
    }
    
    // Main view table view
    if (indexPath.section == kShareLocationSectionCurrent) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"UserLocationCellIdentifier"];
        [cell.imageView setImage:[UIImage systemImageNamed:@"location.fill" withConfiguration:_iconsConfiguration]];
        cell.textLabel.text = NSLocalizedString(@"Share current location", nil);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %.0fm", NSLocalizedString(@"Accuracy", nil), _currentLocation.horizontalAccuracy];
        return cell;
    } else if (indexPath.section == kShareLocationSectionDropPin) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DropPinCellIdentifier"];
        [cell.imageView setImage:[UIImage systemImageNamed:@"mappin" withConfiguration:_iconsConfiguration]];
        cell.textLabel.text = NSLocalizedString(@"Share pin location", @"Share the location of a pin that has been dropped in a map view");
        if (_dropPinPlacemark.thoroughfare && _dropPinPlacemark.subThoroughfare) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", _dropPinPlacemark.thoroughfare, _dropPinPlacemark.subThoroughfare];
        }
        return cell;
    } else if (indexPath.section == kShareLocationSectionNearby) {
        MKMapItem *nearbyPlace = [_nearbyPlaces objectAtIndex:indexPath.row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NearbyLocationCellIdentifier"];
        [cell.imageView setImage:[UIImage systemImageNamed:@"mappin" withConfiguration:_iconsConfiguration]];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
        cell.textLabel.text = nearbyPlace.name;
        cell.detailTextLabel.text = nil;
        if (nearbyPlace.placemark.thoroughfare && nearbyPlace.placemark.subThoroughfare) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", nearbyPlace.placemark.thoroughfare, nearbyPlace.placemark.subThoroughfare];
        }
        return cell;
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Search result table view
    if (tableView == _resultTableViewController.tableView) {
        MKMapItem *searchedPlace = [_searchedPlaces objectAtIndex:indexPath.row];
        [self.delegate shareLocationViewController:self didSelectLocationWithLatitude:searchedPlace.placemark.location.coordinate.latitude longitude:searchedPlace.placemark.location.coordinate.longitude andName:searchedPlace.name];
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
    // Main view table view
        if (indexPath.section == kShareLocationSectionCurrent) {
            [self.delegate shareLocationViewController:self didSelectLocationWithLatitude:_currentLocation.coordinate.latitude longitude:_currentLocation.coordinate.longitude andName:NSLocalizedString(@"My location", nil)];
        } else if (indexPath.section == kShareLocationSectionDropPin) {
            NSString *locationName = NSLocalizedString(@"Shared location", nil);
            if (_dropPinPlacemark.thoroughfare && _dropPinPlacemark.subThoroughfare) {
                locationName = [NSString stringWithFormat:@"%@ %@", _dropPinPlacemark.thoroughfare, _dropPinPlacemark.subThoroughfare];
            }
            [self.delegate shareLocationViewController:self didSelectLocationWithLatitude:_dropPinAnnotation.coordinate.latitude longitude:_dropPinAnnotation.coordinate.longitude andName:locationName];
        } else if (indexPath.section == kShareLocationSectionNearby) {
            MKMapItem *nearbyPlace = [_nearbyPlaces objectAtIndex:indexPath.row];
            [self.delegate shareLocationViewController:self didSelectLocationWithLatitude:nearbyPlace.placemark.location.coordinate.latitude longitude:nearbyPlace.placemark.location.coordinate.longitude andName:nearbyPlace.name];
        }
    }
}

@end
