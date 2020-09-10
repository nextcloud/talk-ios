//
//  ShareConfirmationViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 01.09.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import "ShareConfirmationViewController.h"

#import <NCCommunication/NCCommunication.h>

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCSettingsController.h"
#import "MBProgressHUD.h"

@interface ShareConfirmationViewController () <NCCommunicationCommonDelegate>
{
    UIBarButtonItem *_sendButton;
    UIActivityIndicatorView *_sharingIndicatorView;
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
    
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[UIColor whiteColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
    
    if (_isModal) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        cancelButton.accessibilityHint = @"Double tap to dismiss sharing options";
        self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    }
    
    _sendButton = [[UIBarButtonItem alloc] initWithTitle:@"Send" style:UIBarButtonItemStyleDone
                                                  target:self action:@selector(sendButtonPressed)];
    _sendButton.accessibilityHint = @"Double tap to share with selected conversations";
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
    NSMutableAttributedString *toString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"To: %@", _room.displayName] attributes:attributes];
    [toString addAttributes:subAttribute range:NSMakeRange(0, 3)];
    self.toTextView.attributedText = toString;
}

- (void)cancelButtonPressed
{
    [self.delegate shareConfirmationViewControllerDidFinish:self];
}

- (void)sendButtonPressed
{
    if (_type == ShareConfirmationTypeText) {
        [self sendSharedText];
    } else if (_type == ShareConfirmationTypeImage) {
        [self sendSharedImage];
    } else if (_type == ShareConfirmationTypeFile) {
        [self sendSharedFile];
    }
    
    [self startAnimatingSharingIndicator];
}

- (void)setSharedText:(NSString *)sharedText
{
    _sharedText = sharedText;
    
    self.type = ShareConfirmationTypeText;
    self.shareTextView.text = _sharedText;
    self.shareTextView.editable = NO;
}

- (void)setSharedImage:(UIImage *)sharedImage
{
    _sharedImage = sharedImage;
    
    self.type = ShareConfirmationTypeImage;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.shareImageView setImage:self->_sharedImage];
    });
}

- (void)setSharedFileName:(NSString *)sharedFileName
{
    _sharedFileName = sharedFileName;
    
    self.shareFileTextView.text = _sharedFileName;
    self.shareFileTextView.editable = NO;
}

- (void)setSharedFile:(NSData *)sharedFile
{
    _sharedFile = sharedFile;
    
    [self.shareFileImageView setImage:[UIImage imageNamed:@"file"]];
}

- (void)setType:(ShareConfirmationType)type
{
    _type = type;
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

- (void)sendSharedImage
{
    NSString *attachmentsFolder = _serverCapabilities.attachmentsFolder ? _serverCapabilities.attachmentsFolder : @"";
    NSString *filePath = [NSString stringWithFormat:@"%@/%@", attachmentsFolder, _sharedImageName];
    NSString *fileServerURL = [NSString stringWithFormat:@"%@/%@%@", _account.server, _serverCapabilities.webDAVRoot, filePath];
    NSData *pngData = UIImagePNGRepresentation(_sharedImage);
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileLocalURL = [[tmpDirURL URLByAppendingPathComponent:@"image"] URLByAppendingPathExtension:@"jpg"];
    [pngData writeToFile:[fileLocalURL path] atomically:YES];
    
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeAnnularDeterminate;
    hud.label.text = @"Uploading image";
    
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:[fileLocalURL path] dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        hud.progress = progress.fractionCompleted;
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);
        [hud hideAnimated:YES];
        if (errorCode == 0) {
            [[NCAPIController sharedInstance] shareFileOrFolderForAccount:self->_account atPath:filePath toRoom:self->_room.token withCompletionBlock:^(NSError *error) {
                if (error) {
                    [self.delegate shareConfirmationViewControllerDidFailed:self];
                    NSLog(@"Failed to send shared image");
                } else {
                    [self.delegate shareConfirmationViewControllerDidFinish:self];
                }
                [self stopAnimatingSharingIndicator];
            }];
        } else {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        }
        [self stopAnimatingSharingIndicator];
    }];
}

- (void)sendSharedFile
{
    NSString *attachmentsFolder = _serverCapabilities.attachmentsFolder ? _serverCapabilities.attachmentsFolder : @"";
    NSString *filePath = [NSString stringWithFormat:@"%@/%@", attachmentsFolder, _sharedFileName];
    NSString *fileServerURL = [NSString stringWithFormat:@"%@/%@%@", _account.server, _serverCapabilities.webDAVRoot, filePath];
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileLocalURL = [[tmpDirURL URLByAppendingPathComponent:@"file"] URLByAppendingPathExtension:@"data"];
    [_sharedFile writeToFile:[fileLocalURL path] atomically:YES];
    
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeAnnularDeterminate;
    hud.label.text = @"Uploading file";
    
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:[fileLocalURL path] dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        hud.progress = progress.fractionCompleted;
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);
        [hud hideAnimated:YES];
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
        } else {
            [self.delegate shareConfirmationViewControllerDidFailed:self];
        }
        [self stopAnimatingSharingIndicator];
    }];
}

#pragma mark - User Interface

- (void)startAnimatingSharingIndicator
{
    [_sharingIndicatorView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_sharingIndicatorView];
}

- (void)stopAnimatingSharingIndicator
{
    [_sharingIndicatorView stopAnimating];
    self.navigationItem.rightBarButtonItem = _sendButton;
}

- (void)setUIForShareType:(ShareConfirmationType)shareConfirmationType
{
    switch (shareConfirmationType) {
        case ShareConfirmationTypeText:
        {
            self.shareTextView.hidden = NO;
            self.shareImageView.hidden = YES;
            self.shareFileImageView.hidden = YES;
            self.shareFileTextView.hidden = YES;
        }
            break;
        case ShareConfirmationTypeImage:
        {
            self.shareTextView.hidden = YES;
            self.shareImageView.hidden = NO;
            self.shareFileImageView.hidden = YES;
            self.shareFileTextView.hidden = YES;
        }
            break;
        case ShareConfirmationTypeFile:
        {
            self.shareTextView.hidden = YES;
            self.shareImageView.hidden = YES;
            self.shareFileImageView.hidden = NO;
            self.shareFileTextView.hidden = NO;
        }
            break;
        default:
            break;
    }
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
