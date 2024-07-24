/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ShareLocationViewController;
@protocol ShareLocationViewControllerDelegate <NSObject>

- (void)shareLocationViewController:(ShareLocationViewController *)viewController didSelectLocationWithLatitude:(double)latitude longitude:(double)longitude andName:(NSString *)name;

@end

@interface ShareLocationViewController : UIViewController

@property (nonatomic, weak) id<ShareLocationViewControllerDelegate> delegate;
@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIButton *myLocationButton;

@end

NS_ASSUME_NONNULL_END
