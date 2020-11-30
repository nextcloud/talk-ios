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

#import "ShareConfirmationViewController.h"
#import "ShareConfirmationCollectionViewCell.h"

#import <NCCommunication/NCCommunication.h>

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCSettingsController.h"
#import "NCUtils.h"
#import "MBProgressHUD.h"
#import <QuickLook/QuickLook.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>

@interface ShareConfirmationViewController () <NCCommunicationCommonDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, QLPreviewControllerDataSource, QLPreviewControllerDelegate, ShareItemControllerDelegate>
{
    UIBarButtonItem *_sendButton;
    UIActivityIndicatorView *_sharingIndicatorView;
    MBProgressHUD *_hud;
    dispatch_group_t _uploadGroup;
    BOOL _uploadFailed;
}

@end

@implementation ShareConfirmationViewController

- (id)initWithRoom:(NCRoom *)room account:(TalkAccount *)account serverCapabilities:(ServerCapabilities *)serverCapabilities
{
    self = [super init];
    if (self) {
        self.room = room;
        self.account = account;
        self.serverCapabilities = serverCapabilities;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.translucent = NO;
    
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
    
    self.pageControl.currentPageIndicatorTintColor = [NCAppBranding themeColor];
    self.pageControl.pageIndicatorTintColor = [NCAppBranding placeholderColor];
    self.pageControl.hidesForSinglePage = YES;
    self.pageControl.numberOfPages = 1;
    
    if (_isModal) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        cancelButton.accessibilityHint = NSLocalizedString(@"Double tap to dismiss sharing options", nil);
        self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    }
    
    _sendButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Send", nil) style:UIBarButtonItemStyleDone
                                                  target:self action:@selector(sendButtonPressed)];
    _sendButton.accessibilityHint = NSLocalizedString(@"Double tap to share with selected conversations", nil);
    self.navigationItem.rightBarButtonItem = _sendButton;
    
    _sharingIndicatorView = [[UIActivityIndicatorView alloc] init];
    _sharingIndicatorView.color = [NCAppBranding themeTextColor];
    
    // Configure communication lib
    NSString *userToken = [[NCSettingsController sharedInstance] tokenForAccountId:_account.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    
    [[NCCommunicationCommon shared] setupWithAccount:_account.accountId user:_account.user userId:_account.userId password:userToken
                                             urlBase:_account.server userAgent:userAgent webDav:_serverCapabilities.webDAVRoot dav:nil
                                    nextcloudVersion:_serverCapabilities.versionMajor delegate:self];
    
    // Set to section
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:15],
                                 NSForegroundColorAttributeName:[UIColor darkTextColor]};
    NSDictionary *subAttribute = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:15],
                                   NSForegroundColorAttributeName:[UIColor lightGrayColor]};
    NSMutableAttributedString *toString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@"To: %@", nil), _room.displayName] attributes:attributes];
    [toString addAttributes:subAttribute range:NSMakeRange(0, 3)];
    self.toTextView.attributedText = toString;
        
    self.shareCollectionView.delegate = self;
    
    self.shareItemController = [[ShareItemController alloc] init];
    self.shareItemController.delegate = self;
    
    NSBundle *bundle = [NSBundle bundleForClass:[ShareConfirmationCollectionViewCell class]];
    [self.shareCollectionView registerNib:[UINib nibWithNibName:kShareConfirmationTableCellNibName bundle:bundle] forCellWithReuseIdentifier:kShareConfirmationCellIdentifier];
    
    [[NSNotificationCenter defaultCenter]
                         addObserver:self
                            selector:@selector(keyboardWillShow:)
                                name:UIKeyboardWillShowNotification
                              object:nil];
    
    _type = ShareConfirmationTypeItem;
}

- (void)viewDidAppear:(BOOL)animated
{
    if (_type == ShareConfirmationTypeText) {
        [self.shareTextView becomeFirstResponder];
    }
}

- (void)cancelButtonPressed
{
    [self.delegate shareConfirmationViewControllerDidFinish:self];
}

- (void)sendButtonPressed
{
    if (_type == ShareConfirmationTypeText) {
        [self sendSharedText];
    } else {
        [self uploadAndShareFiles];
    }
    
    [self startAnimatingSharingIndicator];
}

- (void)shareText:(NSString *)sharedText
{
    _type = ShareConfirmationTypeText;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.shareCollectionView.hidden = YES;
        self.shareTextView.hidden = NO;
        self.shareTextView.text = sharedText;
    });
}

- (void)setIsModal:(BOOL)isModal
{
    _isModal = isModal;
}

#pragma mark - Actions

- (void)sendSharedText
{
    [[NCAPIController sharedInstance] sendChatMessage:self.shareTextView.text toRoom:_room.token displayName:nil replyTo:-1 referenceId:nil forAccount:_account withCompletionBlock:^(NSError *error) {
        if (error) {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
            NSLog(@"Failed to send shared item");
        } else {
            [self.delegate shareConfirmationViewControllerDidFinish:self];
        }
        [self stopAnimatingSharingIndicator];
    }];
}

- (void)updateHudProgress
{
    if (!_hud) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat progress = 0;
        long items = 0;
        
        for (ShareItem *item in self->_shareItemController.shareItems) {
            progress += item.uploadProgress;
            items++;
        }
        
        self->_hud.progress = (progress / items);
    });
}

- (void)uploadAndShareFiles
{
    _hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    _hud.mode = MBProgressHUDModeAnnularDeterminate;
    _hud.label.text = [NSString stringWithFormat:NSLocalizedString(@"Uploading %ld elements", nil), [self.shareItemController.shareItems count]];
    
    _uploadGroup = dispatch_group_create();
    _uploadFailed = NO;
    
    for (ShareItem *item in self.shareItemController.shareItems) {
        NSLog(@"Uploading %@", item.fileURL);
        
        dispatch_group_enter(_uploadGroup);
        [self checkForUniqueNameAndUploadFileWithName:item.fileName withItem:item withOriginalName:YES];
    }
    
    dispatch_group_notify(_uploadGroup, dispatch_get_main_queue(),^{
        [self stopAnimatingSharingIndicator];
        [self->_hud hideAnimated:YES];
        
        [self->_shareItemController removeAllItems];
        
        // TODO: Do error reporting per item
        if (self->_uploadFailed) {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        } else {
            [self.delegate shareConfirmationViewControllerDidFinish:self];
        }
    });
}

- (void)checkForUniqueNameAndUploadFileWithName:(NSString *)fileName withItem:(ShareItem *)item withOriginalName:(BOOL)isOriginalName
{
    NSString *fileServerPath = [self serverFilePathForFileName:fileName];
    NSString *fileServerURL = [self serverFileURLForFilePath:fileServerPath];
    
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:fileServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // File already exists
        if (errorCode == 0 && files.count == 1) {
            NSString *alternativeName = [self alternativeNameForFileName:fileName original:isOriginalName];
            [self checkForUniqueNameAndUploadFileWithName:alternativeName withItem:item withOriginalName:NO];
        // File does not exist
        } else if (errorCode == 404) {
            [self uploadFileToServerURL:fileServerURL withFilePath:fileServerPath withItem:item];
        } else {
            NSLog(@"Error checking file name");
            
            self->_uploadFailed = YES;
            dispatch_group_leave(self->_uploadGroup);
        }
    }];
}

- (void)checkAttachmentFolderAndUploadFileToServerURL:(NSString *)fileServerURL withFilePath:(NSString *)filePath withItem:(ShareItem *)item
{
    NSString *attachmentFolderServerURL = [self attachmentFolderServerURL];
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:attachmentFolderServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // Attachment folder do not exist
        if (errorCode == 404) {
            [[NCCommunication shared] createFolder:attachmentFolderServerURL customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *account, NSString *nose, NSDate *date, NSInteger errorCode, NSString *errorDescription) {
                if (errorCode == 0) {
                    [self uploadFileToServerURL:fileServerURL withFilePath:filePath withItem:item];
                }
            }];
        } else {
            NSLog(@"Error checking attachment folder");
            
            self->_uploadFailed = YES;
            dispatch_group_leave(self->_uploadGroup);
        }
    }];
}

- (void)uploadFileToServerURL:(NSString *)fileServerURL withFilePath:(NSString *)filePath withItem:(ShareItem *)item
{
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:item.filePath dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        item.uploadProgress = progress.fractionCompleted;
        [self updateHudProgress];
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSDictionary *allHeaderFields, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);

        if (errorCode == 0) {
            [[NCAPIController sharedInstance] shareFileOrFolderForAccount:self->_account atPath:filePath toRoom:self->_room.token withCompletionBlock:^(NSError *error) {
                if (error) {
                    NSLog(@"Failed to send shared file");
                    
                    self->_uploadFailed = YES;
                    dispatch_group_leave(self->_uploadGroup);
                } else {
                    dispatch_group_leave(self->_uploadGroup);
                }
            }];
        } else if (errorCode == 404) {
            [self checkAttachmentFolderAndUploadFileToServerURL:fileServerURL withFilePath:filePath withItem:item];
        } else {
            self->_uploadFailed = YES;
            dispatch_group_leave(self->_uploadGroup);
        }
    }];
}

#pragma mark - Utils

- (NSString *)serverFilePathForFileName:(NSString *)fileName
{
    NSString *attachmentsFolder = _serverCapabilities.attachmentsFolder ? _serverCapabilities.attachmentsFolder : @"";
    return [NSString stringWithFormat:@"%@/%@", attachmentsFolder, fileName];
}

- (NSString *)attachmentFolderServerURL
{
    NSString *attachmentsFolder = _serverCapabilities.attachmentsFolder ? _serverCapabilities.attachmentsFolder : @"";
    return [NSString stringWithFormat:@"%@/%@%@", _account.server, _serverCapabilities.webDAVRoot, attachmentsFolder];
}

- (NSString *)serverFileURLForFilePath:(NSString *)filePath
{
    return [NSString stringWithFormat:@"%@/%@%@", _account.server, _serverCapabilities.webDAVRoot, filePath];
}

- (NSString *)alternativeNameForFileName:(NSString *)fileName original:(BOOL)isOriginal
{
    NSString *extension = [fileName pathExtension];
    NSString *nameWithoutExtension = [fileName stringByDeletingPathExtension];
    NSString *alternativeName = nameWithoutExtension;
    NSString *newSuffix = @" (1)";
    
    if (!isOriginal) {
        // Check if the name ends with ` (n)`
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@" \\((\\d+)\\)$" options:NSRegularExpressionCaseInsensitive error:&error];
        NSTextCheckingResult *match = [regex firstMatchInString:nameWithoutExtension options:0 range:NSMakeRange(0, nameWithoutExtension.length)];
        if ([match numberOfRanges] > 1) {
            NSRange suffixRange = [match rangeAtIndex: 0];
            NSInteger suffixNumber = [[nameWithoutExtension substringWithRange:[match rangeAtIndex: 1]] intValue];
            newSuffix = [NSString stringWithFormat:@" (%ld)", suffixNumber + 1];
            alternativeName = [nameWithoutExtension stringByReplacingCharactersInRange:suffixRange withString:@""];
        }
    }
    
    alternativeName = [alternativeName stringByAppendingString:newSuffix];
    alternativeName = [alternativeName stringByAppendingPathExtension:extension];
    
    return alternativeName;
}

#pragma mark - User Interface

- (void)startAnimatingSharingIndicator
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_sharingIndicatorView startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self->_sharingIndicatorView];
    });
}

- (void)stopAnimatingSharingIndicator
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_sharingIndicatorView stopAnimating];
        self.navigationItem.rightBarButtonItem = self->_sendButton;
    });
}

-(void)keyboardWillShow:(NSNotification *)notification
 {
     // see https://stackoverflow.com/a/22719225/2512312
     NSDictionary *info = notification.userInfo;
     NSValue *value = info[UIKeyboardFrameEndUserInfoKey];

     CGRect rawFrame = [value CGRectValue];
     CGRect keyboardFrame = [self.view convertRect:rawFrame fromView:nil];
     
     [UIView animateWithDuration:0.3 animations:^{
         self.bottomSpacer.constant = keyboardFrame.size.height;
         [self.view layoutIfNeeded];
     }];
 }

#pragma mark - ScrollView/CollectionView

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ShareConfirmationCollectionViewCell *cell = (ShareConfirmationCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:kShareConfirmationCellIdentifier forIndexPath:indexPath];
    ShareItem *item = [self.shareItemController.shareItems objectAtIndex:indexPath.row];
    
    // Setting placeholder here in case we can't generate any other preview
    [cell setPlaceHolderImage:item.placeholderImage];
    [cell setPlaceHolderText:item.fileName];

    // Check if we got an image
    NSData *fileData = [NSData dataWithContentsOfURL:item.fileURL];
    UIImage *image = [UIImage imageWithData:fileData];
    
    if (image) {
        // We're able to get an image directly from the fileURL -> use it
        [cell setPreviewImage:image];
    } else {
        // We need to generate our own preview/thumbnail here
        [self generatePreviewForCell:cell withCollectionView:collectionView withItem:item];
    }
    
    return cell;
}

- (void)generatePreviewForCell:(ShareConfirmationCollectionViewCell *)cell withCollectionView:(UICollectionView *)collectionView withItem:(ShareItem *)item
{
    if (@available(iOS 13.0, *)) {
        CGSize size = CGSizeMake(collectionView.bounds.size.width, collectionView.bounds.size.height);
        CGFloat scale = [UIScreen mainScreen].scale;
        
        // updateHandler might be called multiple times, starting from low quality representation to high-quality
        QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:item.fileURL size:size scale:scale representationTypes:(QLThumbnailGenerationRequestRepresentationTypeLowQualityThumbnail | QLThumbnailGenerationRequestRepresentationTypeThumbnail)];
        [QLThumbnailGenerator.sharedGenerator generateRepresentationsForRequest:request updateHandler:^(QLThumbnailRepresentation * _Nullable thumbnail, QLThumbnailRepresentationType type, NSError * _Nullable error) {
            if (error) {
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [cell setPreviewImage:thumbnail.UIImage];
            });
        }];
    }
}

- (NSInteger)collectionView:(nonnull UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.shareItemController.shareItems count];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width, collectionView.bounds.size.height);
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    // see: https://stackoverflow.com/a/46181277/2512312
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pageControl.currentPage = scrollView.contentOffset.x / scrollView.frame.size.width;
    });
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    QLPreviewController * preview = [[QLPreviewController alloc] init];
    preview.currentPreviewItemIndex = indexPath.row;
    preview.dataSource = self;
    preview.delegate = self;
    
    preview.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    preview.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    preview.tabBarController.tabBar.tintColor = [NCAppBranding themeColor];

    UIColor *themeColor = [NCAppBranding themeColor];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        preview.navigationItem.standardAppearance = appearance;
        preview.navigationItem.compactAppearance = appearance;
        preview.navigationItem.scrollEdgeAppearance = appearance;
    }

    [self.navigationController pushViewController:preview animated:YES];
}

#pragma mark - PreviewController

- (nonnull id<QLPreviewItem>)previewController:(nonnull QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    // Don't use index here, as this relates to numberOfPreviewItems
    // When we have numberOfPreviewItema > 1 this will show an additional list of items
    ShareItem *item = [self.shareItemController.shareItems objectAtIndex:self.shareCollectionView.indexPathsForSelectedItems.firstObject.row];
    
    if (item && item.fileURL) {
        return item.fileURL;
    }
    
    return nil;
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return 1;
}

- (QLPreviewItemEditingMode)previewController:(QLPreviewController *)controller editingModeForPreviewItem:(id<QLPreviewItem>)previewItem  API_AVAILABLE(ios(13.0)) {
    return QLPreviewItemEditingModeCreateCopy;
}

- (void)previewController:(QLPreviewController *)controller didSaveEditedCopyOfPreviewItem:(id<QLPreviewItem>)previewItem atURL:(NSURL *)modifiedContentsURL {
    ShareItem *item = [self.shareItemController.shareItems objectAtIndex:self.shareCollectionView.indexPathsForSelectedItems.firstObject.row];
    
    if (item) {
        [self.shareItemController updateItem:item withURL:modifiedContentsURL];
    }
}


#pragma mark - ShareItemController Delegate
 
- (void)shareItemControllerItemsChanged:(nonnull ShareItemController *)shareItemController {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.shareCollectionView reloadData];
        self.pageControl.numberOfPages = [self.shareItemController.shareItems count];
    });
}

#pragma mark - NCCommunicationCommon Delegate

- (void)authenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    // The pinnning check
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end
