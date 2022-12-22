/**
 * @copyright Copyright (c) 2021 Ivan Sein <ivan@nextcloud.com>
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

#import "DetailedOptionsSelectorTableViewController.h"

#import "NCAppBranding.h"
#import "NextcloudTalk-Swift.h"

@interface DetailedOptionsSelectorTableViewController ()

@end

@implementation DetailedOption
@end

@implementation DetailedOptionsSelectorTableViewController

- (instancetype)initWithOptions:(NSArray *)options forSenderIdentifier:(NSString *)senderId
{
    self = [super initWithStyle:UITableViewStyleGrouped];

    self.options = options;
    self.senderId = senderId;
    self.type = DetailedOptionsSelectorTypeDefault;

    return self;
}

- (instancetype)initWithAccounts:(NSArray *)accounts
{
    self = [super initWithStyle:UITableViewStyleGrouped];

    self.options = accounts;
    self.type = DetailedOptionsSelectorTypeAccounts;
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];
    self.navigationController.navigationBar.translucent = NO;

    UIColor *themeColor = [NCAppBranding themeColor];
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = themeColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    
    NSBundle *bundle = [NSBundle bundleForClass:[AccountTableViewCell class]];
    [self.tableView registerNib:[UINib nibWithNibName:@"AccountTableViewCell" bundle:bundle] forCellReuseIdentifier:@"AccountTableViewCellIdentifier"];
    
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
        AccountTableViewCell *accountCell = [tableView dequeueReusableCellWithIdentifier:@"AccountTableViewCellIdentifier" forIndexPath:indexPath];
        accountCell.accountNameLabel.text = option.title;
        accountCell.accountServerLabel.text = [option.subtitle stringByReplacingOccurrencesOfString:@"https://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [option.subtitle length])];
        accountCell.accountImageView.image = option.image;
        accountCell.accountImageView.backgroundColor = [UIColor systemBackgroundColor];
        return accountCell;
    }

    [cell.imageView setImage:option.image];
    cell.textLabel.text = option.title;
    cell.detailTextLabel.text = option.subtitle;
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
