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

#import <NCCommunication/NCCommunication.h>

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCSettingsController.h"
#import "NCUtils.h"
#import "MBProgressHUD.h"

@interface ShareConfirmationViewController () <NCCommunicationCommonDelegate>
{
    UIBarButtonItem *_sendButton;
    UIActivityIndicatorView *_sharingIndicatorView;
    MBProgressHUD *_hud;
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
    
    self.navigationController.navigationBar.tintColor = [NCAppBranding primaryTextColor];
    self.navigationController.navigationBar.barTintColor = [NCAppBranding primaryColor];
    self.tabBarController.tabBar.tintColor = [NCAppBranding primaryColor];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding primaryColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding primaryTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
    
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
    
    _sharingIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    
    // Configure communication lib
    NSString *userToken = [[NCSettingsController sharedInstance] tokenForAccountId:_account.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    
    [[NCCommunicationCommon shared] setupWithAccount:_account.accountId user:_account.user userId:_account.userId password:userToken url:_account.server userAgent:userAgent capabilitiesGroup:@"group.com.nextcloud.Talk" webDavRoot:_serverCapabilities.webDAVRoot davRoot:nil nextcloudVersion:_serverCapabilities.versionMajor delegate:self];
    
    // Set to section
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:15],
                                 NSForegroundColorAttributeName:[UIColor darkTextColor]};
    NSDictionary *subAttribute = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:15],
                                   NSForegroundColorAttributeName:[UIColor lightGrayColor]};
    NSMutableAttributedString *toString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@"To: %@", nil), _room.displayName] attributes:attributes];
    [toString addAttributes:subAttribute range:NSMakeRange(0, 3)];
    self.toTextView.attributedText = toString;
    
    [self setUIForShareType:_type];
}

- (void)cancelButtonPressed
{
    [self.delegate shareConfirmationViewControllerDidFinish:self];
}

- (void)sendButtonPressed
{
    if (_type == ShareConfirmationTypeText) {
        [self sendSharedText];
    } else if (_type == ShareConfirmationTypeImage ||
               _type == ShareConfirmationTypeFile  ||
               _type == ShareConfirmationTypeImageFile) {
        [self uploadAndShareFile];
    }
    
    [self startAnimatingSharingIndicator];
}

- (void)setSharedText:(NSString *)sharedText
{
    _sharedText = sharedText;
    
    _type = ShareConfirmationTypeText;
    [self setUIForShareType:_type];
}

- (void)setSharedFileWithFileURL:(NSURL *)fileURL
{
    [self setSharedFileWithFileURL:fileURL andFileName:nil];
}

- (void)setSharedFileWithFileURL:(NSURL *)fileURL andFileName:(NSString *_Nullable)fileName
{
    _sharedFileURL = fileURL;
    _sharedFileName = fileName ? fileName : [fileURL lastPathComponent];
    _sharedFile = [NSData dataWithContentsOfURL:fileURL];
    
    _type = ShareConfirmationTypeFile;
    
    UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:fileURL]];
    if (image) {
        _type = ShareConfirmationTypeImageFile;
        _sharedImage = image;
    }
    
    CFStringRef fileExtension = (__bridge CFStringRef)[fileURL pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    
    NSString *mimeType = (__bridge NSString *)MIMEType;
    NSString *imageName = [[NCUtils previewImageForFileMIMEType:mimeType] stringByAppendingString:@"-chat-preview"];
    _sharedFileImage = [UIImage imageNamed:imageName];
    
    [self setUIForShareType:_type];
}

- (void)setSharedImage:(UIImage *)image withImageName:(NSString *)imageName
{
    _sharedImage = image;
    _sharedImageName = imageName;
    
    _type = ShareConfirmationTypeImage;
    [self setUIForShareType:_type];
}

- (void)setIsModal:(BOOL)isModal
{
    _isModal = isModal;
}

#pragma mark - Actions

- (void)sendSharedText
{
    [[NCAPIController sharedInstance] sendChatMessage:_sharedText toRoom:_room.token displayName:nil replyTo:-1 referenceId:nil forAccount:_account withCompletionBlock:^(NSError *error) {
        if (error) {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
            NSLog(@"Failed to send shared item");
        } else {
            [self.delegate shareConfirmationViewControllerDidFinish:self];
        }
        [self stopAnimatingSharingIndicator];
    }];
}

- (void)uploadAndShareFile
{
    NSString *fileName = (_type == ShareConfirmationTypeImage) ? _sharedImageName : _sharedFileName;
    NSString *fileLocalPath = [self localFilePath];
    if (_type == ShareConfirmationTypeImage) {
        NSData *pngData = UIImageJPEGRepresentation(_sharedImage, 0.7);
        [pngData writeToFile:fileLocalPath atomically:YES];
    } else {
        [_sharedFile writeToFile:fileLocalPath atomically:YES];
    }
    
    _hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    _hud.mode = MBProgressHUDModeAnnularDeterminate;
    _hud.label.text = NSLocalizedString(@"Uploading file", nil);
    if (_type == ShareConfirmationTypeImage || _type == ShareConfirmationTypeImageFile) {
        _hud.label.text = NSLocalizedString(@"Uploading image", nil);
    }
    
    [self checkForUniqueNameAndUploadFileWithName:fileName withOriginalName:YES];
}

- (void)checkForUniqueNameAndUploadFileWithName:(NSString *)fileName withOriginalName:(BOOL)isOriginalName
{
    NSString *filePath = [self serverFilePathForFileName:fileName];
    NSString *fileServerURL = [self serverFileURLForFilePath:filePath];
    NSString *fileLocalPath = [self localFilePath];
    
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:fileServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // File already exist
        if (errorCode == 0 && files.count == 1) {
            NSString *alternativeName = [self alternativeNameForFileName:fileName original:isOriginalName];
            [self checkForUniqueNameAndUploadFileWithName:alternativeName withOriginalName:NO];
        // File do not exist
        } else if (errorCode == 404) {
            [self uploadFileToServerURL:fileServerURL withFilePath:filePath locatedInLocalPath:fileLocalPath];
        } else {
            NSLog(@"Error checking file name");
            [self stopAnimatingSharingIndicator];
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        }
    }];
}

- (void)checkAttachmentFolderAndUploadFileToServerURL:(NSString *)fileServerURL withFilePath:(NSString *)filePath locatedInLocalPath:(NSString *)fileLocalPath
{
    NSString *attachmentFolderServerURL = [self attachmentFolderServerURL];
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:attachmentFolderServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // Attachment folder do not exist
        if (errorCode == 404) {
            [[NCCommunication shared] createFolder:attachmentFolderServerURL customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *account, NSString *nose, NSDate *date, NSInteger errorCode, NSString *errorDescription) {
                if (errorCode == 0) {
                    [self uploadFileToServerURL:fileServerURL withFilePath:filePath locatedInLocalPath:fileLocalPath];
                }
            }];
        } else {
            NSLog(@"Error checking attachment folder");
            [self stopAnimatingSharingIndicator];
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        }
    }];
}

- (void)uploadFileToServerURL:(NSString *)fileServerURL withFilePath:(NSString *)filePath locatedInLocalPath:(NSString *)fileLocalPath
{
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:fileLocalPath dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        self->_hud.progress = progress.fractionCompleted;
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);
        [self->_hud hideAnimated:YES];
        if (errorCode == 0) {
            [[NCAPIController sharedInstance] shareFileOrFolderForAccount:self->_account atPath:filePath toRoom:self->_room.token withCompletionBlock:^(NSError *error) {
                if (error) {
                    [self.delegate shareConfirmationViewControllerDidFailed:self];
                    NSLog(@"Failed to send shared file");
                } else {
                    [self.delegate shareConfirmationViewControllerDidFinish:self];
                }
                [self stopAnimatingSharingIndicator];
            }];
        } else if (errorCode == 404) {
            [self checkAttachmentFolderAndUploadFileToServerURL:fileServerURL withFilePath:filePath locatedInLocalPath:fileLocalPath];
        } else {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        }
        [self stopAnimatingSharingIndicator];
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

- (NSString *)localFilePath
{
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileLocalURL = [[tmpDirURL URLByAppendingPathComponent:@"file"] URLByAppendingPathExtension:@"data"];
    
    return [fileLocalURL path];
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

- (void)setUIForShareType:(ShareConfirmationType)shareConfirmationType
{
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (shareConfirmationType) {
            case ShareConfirmationTypeText:
            {
                self.shareTextView.hidden = NO;
                self.shareImageView.hidden = YES;
                self.shareFileImageView.hidden = YES;
                self.shareFileTextView.hidden = YES;
                
                self.shareTextView.text = self->_sharedText;
                self.shareTextView.editable = NO;
            }
                break;
            case ShareConfirmationTypeImage:
            case ShareConfirmationTypeImageFile:
            {
                self.shareTextView.hidden = YES;
                self.shareImageView.hidden = NO;
                self.shareFileImageView.hidden = YES;
                self.shareFileTextView.hidden = YES;
                
                [self.shareImageView setImage:self->_sharedImage];
            }
                break;
            case ShareConfirmationTypeFile:
            {
                self.shareTextView.hidden = YES;
                self.shareImageView.hidden = YES;
                self.shareFileImageView.hidden = NO;
                self.shareFileTextView.hidden = NO;
                
                [self.shareFileImageView setImage:self->_sharedFileImage];
                self.shareFileTextView.text = self->_sharedFileName;
                self.shareFileTextView.editable = NO;
            }
                break;
            default:
                break;
        }
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
