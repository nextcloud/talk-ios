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

#import "VideoSettingsViewController.h"

#import "NCAppBranding.h"
#import "NCSettingsController.h"
#import "VideoResolutionsViewController.h"

typedef enum VideoSettingsSection {
    kVideoSettingsSectionResolution = 0,
    kVideoSettingsSectionDefaultVideo,
    kVideoSettingsSectionCount
} VideoSettingsSection;

@interface VideoSettingsViewController ()
{
    UISwitch *_videoDisabledSwitch;
}

@end

@implementation VideoSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:(UITableViewStyle)UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Video calls", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding primaryTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding primaryTextColor];
    
    _videoDisabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_videoDisabledSwitch addTarget: self action: @selector(videoDisabledValueChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.tableView reloadData];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kVideoSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kVideoSettingsSectionResolution:
            return NSLocalizedString(@"Quality", nil);
            break;
            
        case kVideoSettingsSectionDefaultVideo:
            return NSLocalizedString(@"Settings", nil);
            break;
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *kVideoResolutionCellIdentifier = @"VideoResolutionCellIdentifier";
    static NSString *kDefaultVideoToggleCellIdentifier = @"DefaultVideoToggleCellIdentifier";
    
    switch (indexPath.section) {
        case kVideoSettingsSectionResolution:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:kVideoResolutionCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kVideoResolutionCellIdentifier];
            }
            
            cell.textLabel.text = NSLocalizedString(@"Video resolution", nil);
            NSString *resolution = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
            cell.detailTextLabel.text = [[[NCSettingsController sharedInstance] videoSettingsModel] readableResolution:resolution];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
            break;
        case kVideoSettingsSectionDefaultVideo:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:kDefaultVideoToggleCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDefaultVideoToggleCellIdentifier];
            }
            
            cell.textLabel.text = NSLocalizedString(@"Video disabled on start", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            BOOL videoDisabled = [[[NCSettingsController sharedInstance] videoSettingsModel] videoDisabledSettingFromStore];
            [_videoDisabledSwitch setOn:videoDisabled];
            cell.accessoryView = _videoDisabledSwitch;
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kVideoSettingsSectionResolution:
        {
            VideoResolutionsViewController *videoResolutionsVC = [[VideoResolutionsViewController alloc] init];
            [self.navigationController pushViewController:videoResolutionsVC animated:YES];
        }
            break;
        case kVideoSettingsSectionDefaultVideo:
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Video disabled switch

- (void)videoDisabledValueChanged:(id)sender
{
    BOOL videoDisable = _videoDisabledSwitch.on;
    [[[NCSettingsController sharedInstance] videoSettingsModel] storeVideoDisabledDefault:videoDisable];
}


@end
