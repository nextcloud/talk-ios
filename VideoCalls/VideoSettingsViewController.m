//
//  VideoSettingsViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 15.03.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "VideoSettingsViewController.h"

#import "NCSettingsController.h"

typedef enum VideoSettingsSection {
    kVideoSettingsSectionResolution = 0,
    kVideoSettingsSectionDefaultVideo,
    kVideoSettingsSectionCount
} VideoSettingsSection;

@interface VideoSettingsViewController ()

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
    
    self.navigationItem.title = @"Video settings";
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
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
            
            cell.textLabel.text = @"Video resolution";
            cell.detailTextLabel.text = [[[NCSettingsController sharedInstance] videoSettingsModel] currentVideoResolutionSettingFromStore];
        }
            break;
        case kVideoSettingsSectionDefaultVideo:
        {
            cell = [tableView dequeueReusableCellWithIdentifier:kDefaultVideoToggleCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kDefaultVideoToggleCellIdentifier];
            }
            
            cell.textLabel.text = @"Start call with video disabled";
            cell.detailTextLabel.text = @"NO";
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kVideoSettingsSectionResolution:
            break;
        case kVideoSettingsSectionDefaultVideo:
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
