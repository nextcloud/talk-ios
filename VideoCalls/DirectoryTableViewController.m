//
//  DirectoryTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "DirectoryTableViewController.h"

#import "DirectoryTableViewCell.h"
#import "OCFileDto.h"
#import "NCAPIController.h"
#import "NCFilePreviewSessionManager.h"
#import "NCSettingsController.h"
#import "PlaceholderView.h"
#import "UIImageView+AFNetworking.h"

@interface DirectoryTableViewController ()
{
    NSString *_path;
    NSString *_token;
    NSMutableArray *_itemsInDirectory;
    NSIndexPath *_selectedItem;
    UIBarButtonItem *_sortingButton;
    PlaceholderView *_directoryBackgroundView;
    UIActivityIndicatorView *_sharingFileView;
}

@end

@implementation DirectoryTableViewController

- (instancetype)initWithPath:(NSString *)path inRoom:(nonnull NSString *)token
{
    self = [super init];
    
    if (self) {
        _path = path;
        _token = token;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self configureNavigationBar];
    
    _sharingFileView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // Directory placeholder view
    _directoryBackgroundView = [[PlaceholderView alloc] init];
    [_directoryBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"folder-placeholder"]];
    [_directoryBackgroundView.placeholderText setText:@"No files in here"];
    [_directoryBackgroundView.placeholderView setHidden:YES];
    [_directoryBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _directoryBackgroundView;
    
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[UIColor whiteColor]}];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.navigationController.navigationBar.translucent = NO;
    
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 64, 0, 0);
    
    [self.tableView registerNib:[UINib nibWithNibName:kDirectoryTableCellNibName bundle:nil] forCellReuseIdentifier:kDirectoryCellIdentifier];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self getItemsInDirectory];
}

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareButtonPressed
{
    [self showConfirmationDialogForSharingItemWithPath:_path andName:[_path lastPathComponent]];
}

- (void)showSortingOptions
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *alphabetical = [UIAlertAction actionWithTitle:@"Alphabetical order"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^void (UIAlertAction *action) {
                                                             [[NCSettingsController sharedInstance] setPreferredFileSorting:NCAlphabeticalSorting];
                                                             [self sortItemsInDirectory];
                                                         }];
    [optionsActionSheet addAction:alphabetical];
    UIAlertAction *modificationDate = [UIAlertAction actionWithTitle:@"Modification date"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^void (UIAlertAction *action) {
                                                                 [[NCSettingsController sharedInstance] setPreferredFileSorting:NCModificationDateSorting];
                                                                 [self sortItemsInDirectory];
                                                             }];
    [optionsActionSheet addAction:modificationDate];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    UIAlertAction *selectedAction = modificationDate;
    switch ([[NCSettingsController sharedInstance] getPreferredFileSorting]) {
        case NCAlphabeticalSorting:
            selectedAction = alphabetical;
            break;
        case NCModificationDateSorting:
            selectedAction = modificationDate;
            break;
        default:
            break;
    }
    [selectedAction setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.barButtonItem = _sortingButton;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}


#pragma mark - Files

- (void)getItemsInDirectory
{
    [[NCAPIController sharedInstance] readFolderAtPath:_path depth:@"1" withCompletionBlock:^(NSArray *items, NSError *error) {
        if (!error) {
            NSMutableArray *itemsInDirectory = [NSMutableArray new];
            for (OCFileDto *item in items) {
                NSString *currentDirectory = [_path isEqualToString:@""] ? @"webdav" : [_path lastPathComponent];
                if ([[item.filePath lastPathComponent] isEqualToString:currentDirectory] && !item.isEncrypted) {
                    [itemsInDirectory addObject:item];
                }
            }
            _itemsInDirectory = itemsInDirectory;
            [self sortItemsInDirectory];
            
            [_directoryBackgroundView.loadingView stopAnimating];
            [_directoryBackgroundView.loadingView setHidden:YES];
            [_directoryBackgroundView.placeholderView setHidden:(itemsInDirectory.count > 0)];
        }
    }];
}

- (void)sortItemsInDirectory
{
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO];
    switch ([[NCSettingsController sharedInstance] getPreferredFileSorting]) {
        case NCAlphabeticalSorting:
            valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"fileName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
            break;
        case NCModificationDateSorting:
            valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO];
            break;
        default:
            break;
    }
    NSArray *descriptors = [NSArray arrayWithObjects:valueDescriptor, nil];
    [_itemsInDirectory sortUsingDescriptors:descriptors];
    [self.tableView reloadData];
}

- (void)shareFileWithPath:(NSString *)path
{
    [self setSharingFileUI];
    [[NCAPIController sharedInstance] shareFileOrFolderAtPath:path toRoom:_token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self removeSharingFileUI];
            [self showErrorSharingItem];
            NSLog(@"Error sharing file or folder: %@", [error description]);
        }
    }];
}

#pragma mark - Utils

- (void)configureNavigationBar
{
    // Sorting button
    _sortingButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"sorting"]
                                                      style:UIBarButtonItemStylePlain
                                                     target:self
                                                     action:@selector(showSortingOptions)];
    // Home folder
    if ([_path isEqualToString:@""]) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        self.navigationItem.leftBarButtonItem = cancelButton;
        self.navigationItem.rightBarButtonItem = _sortingButton;
        
        UIImage *navigationLogo = [UIImage imageNamed:@"navigation-home"];
        self.navigationItem.titleView = [[UIImageView alloc] initWithImage:navigationLogo];
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithImage:navigationLogo style:UIBarButtonItemStylePlain
                                                                      target:nil action:nil];
        self.navigationItem.backBarButtonItem = backButton;
        // Other directories
    } else {
        UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"sharing"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(shareButtonPressed)];
        self.navigationItem.rightBarButtonItems = @[shareButton, _sortingButton];
        
        self.navigationItem.title = [_path lastPathComponent];
    }
}

- (void)setSharingFileUI
{
    [_sharingFileView startAnimating];
    UIBarButtonItem *sharingFileButton = [[UIBarButtonItem alloc] initWithCustomView:_sharingFileView];
    self.navigationItem.rightBarButtonItems = @[sharingFileButton];
    self.navigationController.navigationBar.userInteractionEnabled = NO;
    self.tableView.userInteractionEnabled = NO;
}

- (void)removeSharingFileUI
{
    [_sharingFileView stopAnimating];
    [self configureNavigationBar];
    self.navigationController.navigationBar.userInteractionEnabled = YES;
    self.tableView.userInteractionEnabled = YES;
}

- (void)showConfirmationDialogForSharingItemWithPath:(NSString *)path andName:(NSString *)name
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:name
                                        message:[NSString stringWithFormat:@"Do you want to share '%@' in the conversation?", name]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self shareFileWithPath:path];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)showErrorSharingItem
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:@"Could not share file"
                                        message:@"An error occurred while sharing the file"
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [confirmDialog addAction:confirmAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (NSString *)dateDiff:(NSDate *) convertedDate
{
    NSDate *todayDate = [NSDate date];
    double ti = [convertedDate timeIntervalSinceDate:todayDate];
    ti = ti * -1;
    if (ti < 60) {
        // This minute
        return @"less than a minute ago";
    } else if (ti < 3600) {
        // This hour
        int diff = round(ti / 60);
        return [NSString stringWithFormat:@"%d minutes ago", diff];
    } else if (ti < 86400) {
        // This day
        int diff = round(ti / 60 / 60);
        return[NSString stringWithFormat:@"%d hours ago", diff];
    } else if (ti < 86400 * 30) {
        // This month
        int diff = round(ti / 60 / 60 / 24);
        return[NSString stringWithFormat:@"%d days ago", diff];
    } else {
        // Older than one month
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setFormatterBehavior:NSDateFormatterBehavior10_4];
        [df setDateStyle:NSDateFormatterMediumStyle];
        return [df stringFromDate:convertedDate];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _itemsInDirectory.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kDirectoryTableCellHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OCFileDto *item = [_itemsInDirectory objectAtIndex:indexPath.row];
    DirectoryTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDirectoryCellIdentifier];
    if (!cell) {
        cell = [[DirectoryTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDirectoryCellIdentifier];
    }
    
    // Name and modification date
    cell.fileNameLabel.text = [item.fileName stringByStandardizingPath];
    cell.fileInfoLabel.text = [self dateDiff:[NSDate dateWithTimeIntervalSince1970:item.date]];
    
    // Icon or preview
    if (item.isDirectory) {
        cell.fileImageView.image = [UIImage imageNamed:@"folder"];
    } else if (item.hasPreview) {
        NSString *fileId = [NSString stringWithFormat:@"%f", item.id];
        [cell.fileImageView setImageWithURLRequest:[[NCFilePreviewSessionManager sharedInstance] createPreviewRequestForFile:fileId width:40 height:40]
                                  placeholderImage:[UIImage imageNamed:@"file"] success:nil failure:nil];
    } else {
        cell.fileImageView.image = [UIImage imageNamed:@"file"];
    }
    
    // Disclosure indicator
    if (item.isDirectory) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OCFileDto *item = [_itemsInDirectory objectAtIndex:indexPath.row];
    NSString *selectedItemPath = [NSString stringWithFormat:@"%@%@", _path, item.fileName];
    
    if (item.isDirectory) {
        DirectoryTableViewController *directoryVC = [[DirectoryTableViewController alloc] initWithPath:selectedItemPath inRoom:_token];
        [self.navigationController pushViewController:directoryVC animated:YES];
    } else {
        [self showConfirmationDialogForSharingItemWithPath:selectedItemPath andName:[item.fileName stringByStandardizingPath]];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
