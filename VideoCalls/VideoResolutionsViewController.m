//
//  VideoResolutionsViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 15.03.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

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
    self.navigationItem.title = @"Resolutions";
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
    
    cell.textLabel.text = resolution;
    cell.accessoryType = (isStoredResolution) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *resolution = [_videoResolutions objectAtIndex:indexPath.row];
    [[[NCSettingsController sharedInstance] videoSettingsModel] storeVideoResolutionSetting:resolution];
    [self.tableView reloadData];
}

@end
