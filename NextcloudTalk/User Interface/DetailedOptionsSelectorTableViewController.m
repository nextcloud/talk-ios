/**
 * SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "DetailedOptionsSelectorTableViewController.h"

#import "NCAppBranding.h"
#import "NextcloudTalk-Swift.h"

@interface DetailedOptionsSelectorTableViewController ()

@end

@implementation DetailedOption
@end

@implementation DetailedOptionsSelectorTableViewController

- (instancetype)initWithOptions:(NSArray *)options forSenderIdentifier:(NSString *)senderId andStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];

    self.options = options;
    self.senderId = senderId;
    self.type = DetailedOptionsSelectorTypeDefault;

    return self;
}

- (instancetype)initWithAccounts:(NSArray *)accounts andStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];

    self.options = accounts;
    self.type = DetailedOptionsSelectorTypeAccounts;
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [NCAppBranding styleViewController:self];
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DetailedOption *option = [_options objectAtIndex:indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailOptionIdentifier"];

    if (_type == DetailedOptionsSelectorTypeAccounts) {
        [cell.imageView setImage:[NCUtils renderAspectImageWithImage:option.image ofSize:CGSizeMake(20, 20) centerImage:YES]];
        [cell.detailTextLabel setText:[option.subtitle stringByReplacingOccurrencesOfString:@"https://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [option.subtitle length])]];
        [cell.detailTextLabel setTextColor:[UIColor secondaryLabelColor]];
    } else {
        [cell.imageView setImage:option.image];
        cell.detailTextLabel.text = option.subtitle;
    }

    cell.textLabel.text = option.title;
    cell.detailTextLabel.numberOfLines = 0;
    [cell.detailTextLabel sizeToFit];
    cell.accessoryType = option.selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DetailedOption *option = [_options objectAtIndex:indexPath.row];
    [self.delegate detailedOptionsSelector:self didSelectOptionWithIdentifier:option];
}

- (void)cancelButtonPressed
{
    [self.delegate detailedOptionsSelectorWasCancelled:self];
}

@end
