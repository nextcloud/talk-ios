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

#import "ShareLocationViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "NCAppBranding.h"

typedef enum ShareLocationSection {
    kShareLocationSectionCurrent = 0,
    kShareLocationSectionNearby,
    kShareLocationSectionNumber
} ShareLocationSection;

@interface ShareLocationViewController () <CLLocationManagerDelegate, MKMapViewDelegate, UITableViewDelegate, UITableViewDataSource>
{
    CLLocationManager *_locationManager;
    CLLocation *_currentLocation;
    NSArray *_nearbyPlaces;
    BOOL _hasBeenCentered;
}

@end

@implementation ShareLocationViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Share location", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.navigationController.navigationBar.translucent = NO;
    
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    [_locationManager requestWhenInUseAuthorization];
    
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    NSLog(@"didChangeAuthorizationStatus: %d", status);
}

#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation
{
    if (!_hasBeenCentered) {
        _hasBeenCentered = YES;
        MKCoordinateRegion mapRegion;
        mapRegion.center = mapView.userLocation.coordinate;
        mapRegion.span = MKCoordinateSpanMake(0.01, 0.01);
        [mapView setRegion:mapRegion animated: YES];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_currentLocation = mapView.userLocation.location;
        [self.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:kShareLocationSectionCurrent] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    [self searchForNearbyPlaces];
}

#pragma mark - Search places

- (void)searchForNearbyPlaces
{
    if (@available(iOS 14.0, *)) {
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
}

#pragma mark - UITableView delegate and data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kShareLocationSectionCurrent) {
        return _currentLocation ? 1 : 0;
    } else if (section == kShareLocationSectionNearby) {
        return _nearbyPlaces.count;
    }
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
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
    if (indexPath.section == kShareLocationSectionCurrent) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"UserLocationCellIdentifier"];
        [cell.imageView setImage:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        cell.textLabel.text = NSLocalizedString(@"Share current location", nil);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %.0fm", NSLocalizedString(@"Accuracy", nil), _currentLocation.horizontalAccuracy];
        return cell;
    } else if (indexPath.section == kShareLocationSectionNearby) {
        MKMapItem *nearbyPlace = [_nearbyPlaces objectAtIndex:indexPath.row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NearbyLocationCellIdentifier"];
        [cell.imageView setImage:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        cell.imageView.tintColor = [NCAppBranding placeholderColor];
        cell.textLabel.text = nearbyPlace.name;
        return cell;
    }
    
    return nil;
}

@end
