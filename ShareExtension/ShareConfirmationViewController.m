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

@interface ShareConfirmationViewController () <NCCommunicationCommonDelegate>

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
    
    UIBarButtonItem *sendButton = [[UIBarButtonItem alloc] initWithTitle:@"Send" style:UIBarButtonItemStyleDone
                                                                  target:self action:@selector(sendButtonPressed)];
    sendButton.accessibilityHint = @"Double tap to share with selected conversations";
    self.navigationItem.rightBarButtonItem = sendButton;
    
    // Configure communication lib
    NSString *userToken = [[NCSettingsController sharedInstance] tokenForAccountId:_account.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    
    [[NCCommunicationCommon shared] setupWithAccount:_account.accountId user:_account.user userId:_account.userId password:userToken url:_account.server userAgent:userAgent capabilitiesGroup:@"group.com.nextcloud.Talk" webDavRoot:_serverCapabilities.webDAVRoot davRoot:nil nextcloudVersion:_serverCapabilities.versionMajor delegate:self];
    
    // Set to section
    self.toTextView.text = [NSString stringWithFormat:@"To: %@", _room.displayName];
}

- (void)sendButtonPressed
{
    if (_type == ShareConfirmationTypeText) {
        [self sendSharedText];
    } else if (_type == ShareConfirmationTypeImage) {
        [self sendSharedImage];
    }
}

- (void)setSharedText:(NSString *)sharedText
{
    _sharedText = sharedText;
    
    self.type = ShareConfirmationTypeText;
    self.shareTextView.text = _sharedText;
    self.shareTextView.editable = NO;
    self.shareImageView.hidden = YES;
}

- (void)setSharedImage:(UIImage *)sharedImage
{
    _sharedImage = sharedImage;
    
    self.type = ShareConfirmationTypeImage;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.shareImageView setImage:self->_sharedImage];
        self.shareTextView.hidden = YES;
    });
}

#pragma mark - Actions

- (void)sendSharedText
{
    [[NCAPIController sharedInstance] sendChatMessage:_sharedText toRoom:_room.token displayName:nil replyTo:-1 referenceId:nil forAccount:_account withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send shared item");
        }
    }];
    
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
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
    
    [[NCCommunication shared] uploadWithServerUrlFileName:fileServerURL fileNameLocalPath:[fileLocalURL path] dateCreationFile:nil dateModificationFile:nil customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress * progress) {
        NSLog(@"Progress: %@", progress);
    } completionHandler:^(NSString *account, NSString *ocId, NSString *etag, NSDate *date, int64_t size, NSInteger errorCode, NSString *errorDescription) {
        NSLog(@"Upload completed with error code: %ld", (long)errorCode);
        [[NCAPIController sharedInstance] shareFileOrFolderForAccount:self->_account atPath:filePath toRoom:self->_room.token withCompletionBlock:^(NSError *error) {
            NSLog(@"Error: %@", error);
        }];
    }];
    
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
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
