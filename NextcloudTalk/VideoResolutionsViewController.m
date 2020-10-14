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

#import "VideoResolutionsViewController.h"

#import "NCSettingsController.h"

@interface VideoResolutionsViewController ()
{
    NSArray *_videoResolutions;
}

@end

@implementation VideoResolutionsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = NSLocalizedString(@"Resolutions", nil);
    _videoResolutions = [[[NCSettingsController sharedInstance] videoSettingsModel] availableVideoResolutions];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _videoResolutions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kVideoResolutionsCellIdentifier = @"VideoResolutionsCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kVideoResolutionsCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kVideoResolutionsCellIdentifier];
    }
    
    NSString *resolution = [_videoResolutions objectAtIndex:indexPath.row];
    NSString *storedResolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
    BOOL isStoredResolution = [resolution isEqualToString:storedResolution];
    
    cell.textLabel.text = [[[NCSettingsController sharedInstance] videoSettingsModel] readableResolution:resolution];
    cell.accessoryType = (isStoredResolution) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *resolution = [_videoResolutions objectAtIndex:indexPath.row];
    [[[NCSettingsController sharedInstance] videoSettingsModel] storeVideoResolutionSetting:resolution];
    [self.tableView reloadData];
}

@end
