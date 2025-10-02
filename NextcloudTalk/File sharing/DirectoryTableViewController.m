/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "DirectoryTableViewController.h"

@import NextcloudKit;

#import "UIImageView+AFNetworking.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCAppBranding.h"
#import "NCSettingsController.h"
#import "PlaceholderView.h"

#import "NextcloudTalk-Swift.h"

@interface DirectoryTableViewController ()
{
    NSString *_path;
    NSString *_userHomePath;
    NSString *_token;
    NSInteger _threadId;
    NSMutableArray *_itemsInDirectory;
    NSIndexPath *_selectedItem;
    UIBarButtonItem *_sortingButton;
    PlaceholderView *_directoryBackgroundView;
    UIActivityIndicatorView *_sharingFileView;
}

@end

@implementation DirectoryTableViewController

- (instancetype)initWithPath:(NSString *)path inRoom:(NSString *)token andThread:(NSInteger)threadId
{
    self = [super init];
    
    if (self) {
        _path = path;
        _token = token;
        _threadId = threadId;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    _userHomePath = [[NCAPIController sharedInstance] filesPathForAccount:activeAccount];
    
    [self configureNavigationBar];
    
    _sharingFileView = [[UIActivityIndicatorView alloc] init];
    if (@available(iOS 26.0, *)) {
        _sharingFileView.color = [UIColor labelColor];
    } else {
        _sharingFileView.color = [NCAppBranding themeTextColor];
    }

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // Directory placeholder view
    _directoryBackgroundView = [[PlaceholderView alloc] init];
    [_directoryBackgroundView setImage:[UIImage imageNamed:@"folder-placeholder"]];
    [_directoryBackgroundView.placeholderTextView setText:NSLocalizedString(@"No files in here", nil)];
    [_directoryBackgroundView.placeholderView setHidden:YES];
    [_directoryBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _directoryBackgroundView;

    [NCAppBranding styleViewController:self];

    self.tableView.separatorInset = UIEdgeInsetsMake(0, 64, 0, 0);
    
    [self.tableView registerNib:[UINib nibWithNibName:DirectoryTableViewCell.nibName bundle:nil] forCellReuseIdentifier:DirectoryTableViewCell.identifier];
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

- (void)addMenuToSortingButton
{
    NSMutableArray *items = [[NSMutableArray alloc] init];
    
    UIAction *alphabeticalAction = [UIAction actionWithTitle:NSLocalizedString(@"Alphabetical order", nil)
                                                       image:[self imageForSortingOption:NCAlphabeticalSorting]
                                                  identifier:nil
                                                     handler:^(UIAction *action) {
        [[NCSettingsController sharedInstance] setPreferredFileSorting:NCAlphabeticalSorting];
        [self sortItemsInDirectory];
    }];

    UIAction *modificationDateAction = [UIAction actionWithTitle:NSLocalizedString(@"Modification date", nil)
                                                           image:[self imageForSortingOption:NCModificationDateSorting]
                                                      identifier:nil
                                                         handler:^(UIAction *action) {
        [[NCSettingsController sharedInstance] setPreferredFileSorting:NCModificationDateSorting];
        [self sortItemsInDirectory];
    }];

    [items addObject:alphabeticalAction];
    [items addObject:modificationDateAction];

    _sortingButton.menu = [UIMenu menuWithTitle:@"" children:items];
}

- (UIImage *)imageForSortingOption:(NCPreferredFileSorting)option
{
    if ([[NCSettingsController sharedInstance] getPreferredFileSorting] == option) {
        return [UIImage systemImageNamed:@"checkmark"];
    }

    return nil;
}


#pragma mark - Files

- (void)getItemsInDirectory
{
    [[NCAPIController sharedInstance] readFolderForAccount:[[NCDatabaseManager sharedInstance] activeAccount] atPath:_path depth:@"1" withCompletionBlock:^(NSArray *items, NSError *error) {
        if (!error) {
            NSMutableArray *itemsInDirectory = [NSMutableArray new];
            for (NKFile *item in items) {
                NSString *currentDirectory = [self->_path isEqualToString:@""] ? @"/" : [self->_path lastPathComponent];
                NSString *itemPath = [item.path stringByReplacingOccurrencesOfString:self->_userHomePath withString:@""];

                // When nextcloud is installed in a subdirectory, it's not enough to replace the _userHomePath,
                // because the subdirectory would get a part of the itemPath (see https://github.com/nextcloud/talk-ios/issues/996)
                NSArray *itemPathParts = [item.path componentsSeparatedByString:self->_userHomePath];
                if (itemPathParts.count > 1) {
                    itemPath = itemPathParts[1];
                }

                if ([[itemPath lastPathComponent] isEqualToString:currentDirectory] && !item.e2eEncrypted) {
                    [itemsInDirectory addObject:item];
                }
            }
            self->_itemsInDirectory = itemsInDirectory;
            [self sortItemsInDirectory];
            
            [self->_directoryBackgroundView.loadingView stopAnimating];
            [self->_directoryBackgroundView.loadingView setHidden:YES];
            [self->_directoryBackgroundView.placeholderView setHidden:(itemsInDirectory.count > 0)];
        }
    }];
}

- (void)sortItemsInDirectory
{
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO];

    if ([[NCSettingsController sharedInstance] getPreferredFileSorting] == NCAlphabeticalSorting) {
        valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"fileName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    }

    NSArray *descriptors = [NSArray arrayWithObjects:valueDescriptor, nil];
    [_itemsInDirectory sortUsingDescriptors:descriptors];
    [self addMenuToSortingButton];
    [self.tableView reloadData];
}

- (void)shareFileWithPath:(NSString *)path
{
    [self setSharingFileUI];

    NSMutableDictionary *talkMetaData = [NSMutableDictionary new];
    if (_threadId > 0) {
        [talkMetaData setObject:@(_threadId) forKey:@"threadId"];
    }

    [[NCAPIController sharedInstance] shareFileOrFolderForAccount:[[NCDatabaseManager sharedInstance] activeAccount] atPath:path toRoom:_token talkMetaData:talkMetaData referenceId: nil withCompletionBlock:^(NSError *error) {
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
    _sortingButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                      style:UIBarButtonItemStylePlain
                                                     target:self
                                                     action:nil];
    [self addMenuToSortingButton];

    // Home folder
    if ([_path isEqualToString:@""]) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        self.navigationItem.leftBarButtonItem = cancelButton;
        self.navigationItem.rightBarButtonItem = _sortingButton;
        
        UIImage *navigationLogo = [UIImage systemImageNamed:@"house"];
        UIImageView *navigationImageView = [[UIImageView alloc] initWithImage:navigationLogo];
        navigationImageView.image = [navigationImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (@available(iOS 26.0, *)) {
            [navigationImageView setTintColor:[UIColor labelColor]];
        } else {
            [navigationImageView setTintColor:[NCAppBranding themeTextColor]];
        }
        self.navigationItem.titleView = navigationImageView;
        
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithImage:navigationLogo style:UIBarButtonItemStylePlain
                                                                      target:nil action:nil];
        self.navigationItem.backBarButtonItem = backButton;
        // Other directories
    } else {
        UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"sharing"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(shareButtonPressed)];
        self.navigationItem.rightBarButtonItems = @[_sortingButton, shareButton];
        
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
                                        message:[NSString stringWithFormat:NSLocalizedString(@"Do you want to share '%@' in the conversation?", nil), name]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Share", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self shareFileWithPath:path];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)showErrorSharingItem
{
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not share file", nil)
                                        message:NSLocalizedString(@"An error occurred while sharing the file", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [confirmDialog addAction:confirmAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
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
    return DirectoryTableViewCell.cellHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NKFile *item = [_itemsInDirectory objectAtIndex:indexPath.row];
    DirectoryTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DirectoryTableViewCell.identifier];
    if (!cell) {
        cell = [[DirectoryTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DirectoryTableViewCell.identifier];
    }
    
    // Name and modification date
    cell.fileNameLabel.text = item.fileName;
    cell.fileInfoLabel.text = [NCUtils relativeTimeFromDateWithDate:item.date];

    // Icon or preview
    NSString *imageName = [NCUtils previewImageForMimeType:item.contentType];
    UIImage *filePreviewImage = [UIImage imageNamed:imageName];
    if (item.directory) {
        cell.fileImageView.image = [UIImage imageNamed:@"folder"];
    } else if (item.hasPreview) {
        NSString *fileId = [NSString stringWithFormat:@"%@", item.fileId];
        [cell.fileImageView setPreviewForFileId:fileId withWidth:40 withHeight:40 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]];
    } else {
        cell.fileImageView.image = filePreviewImage;
    }
    
    // Disclosure indicator
    if (item.directory) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NKFile *item = [_itemsInDirectory objectAtIndex:indexPath.row];
    NSString *selectedItemPath = [NSString stringWithFormat:@"%@/%@", _path, item.fileName];
    
    if (item.directory) {
        DirectoryTableViewController *directoryVC = [[DirectoryTableViewController alloc] initWithPath:selectedItemPath inRoom:_token andThread:_threadId];
        [self.navigationController pushViewController:directoryVC animated:YES];
    } else {
        [self showConfirmationDialogForSharingItemWithPath:selectedItemPath andName:item.fileName];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
