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
#import "NCUtils.h"

typedef enum ShareLocationSection {
    kShareLocationSectionCurrent = 0,
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
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    // Only make search available on iOS 13+
    if (@available(iOS 13.0, *)) {
        _resultTableViewController = [[UITableViewController alloc] init];
        _resultTableViewController.tableView.delegate = self;
        _resultTableViewController.tableView.dataSource = self;
        _resultTableViewController.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
        
        _searchController = [[UISearchController alloc] initWithSearchResultsController:_resultTableViewController];
        _searchController.delegate = self;
        _searchController.searchResultsUpdater = self;
        [_searchController.searchBar sizeToFit];
        
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;

        self.navigationItem.searchController = _searchController;
        self.navigationItem.searchController.searchBar.searchTextField.backgroundColor = [NCUtils searchbarBGColorForColor:themeColor];
        _searchController.searchBar.tintColor = [NCAppBranding themeTextColor];
        UITextField *searchTextField = [_searchController.searchBar valueForKey:@"searchField"];
        UIButton *clearButton = [searchTextField valueForKey:@"_clearButton"];
        searchTextField.tintColor = [NCAppBranding themeTextColor];
        searchTextField.textColor = [NCAppBranding themeTextColor];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Search bar placeholder
            searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search for places", nil)
            attributes:@{NSForegroundColorAttributeName:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]}];
            // Search bar search icon
            UIImageView *searchImageView = (UIImageView *)searchTextField.leftView;
            searchImageView.image = [searchImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [searchImageView setTintColor:[[NCAppBranding themeTextColor] colorWithAlphaComponent:0.5]];
            // Search bar search clear button
            UIImage *clearButtonImage = [clearButton.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [clearButton setImage:clearButtonImage forState:UIControlStateNormal];
            [clearButton setImage:clearButtonImage forState:UIControlStateHighlighted];
            [clearButton setTintColor:[NCAppBranding themeTextColor]];
        });
        
        // Place resultTableViewController correctly
        self.definesPresentationContext = YES;
        
        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = YES;
    }
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

#pragma mark - Actions

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
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

- (void)searchForPlacesWithString:(NSString *)searchString
{
    if (@available(iOS 13.0, *)) {
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
        MKMapItem *nearbyPlace = [_searchedPlaces objectAtIndex:indexPath.row];
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NearbyLocationCellIdentifier"];
        [cell.imageView setImage:[[UIImage imageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        cell.imageView.tintColor = [NCAppBranding placeholderColor];
        cell.textLabel.text = nearbyPlace.name;
        return cell;
    }
    
    // Main view table view
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
        cell.detailTextLabel.text = nil;
        if (nearbyPlace.placemark.thoroughfare && nearbyPlace.placemark.subThoroughfare) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", nearbyPlace.placemark.thoroughfare, nearbyPlace.placemark.subThoroughfare];
        }
        return cell;
    }
    
    return nil;
}

@end
