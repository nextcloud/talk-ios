/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "AuthenticationViewController.h"


#import "NextcloudTalk-Swift.h"

#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"

NSString * const kNCAuthTokenFlowEndpoint               = @"/index.php/login/flow";

@interface AuthenticationViewController () <WKNavigationDelegate>
{
    UIActivityIndicatorView *_activityIndicatorView;
}

@end

@implementation AuthenticationViewController

@synthesize delegate = _delegate;

- (id)initWithServerUrl:(NSString *)serverUrl
{
    self = [super init];
    if (self) {
        self.serverUrl = serverUrl;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

    NSString *urlString = [NSString stringWithFormat:@"%@%@", _serverUrl, kNCAuthTokenFlowEndpoint];

    if (_user) {
        urlString = [NSString stringWithFormat:@"%@?user=%@", urlString, _user];
    }

    NSURL *url = [NSURL URLWithString:urlString];


    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies])
    {
        [storage deleteCookie:cookie];
    }

    NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
    NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        [request setValue:@"true" forHTTPHeaderField:@"OCS-APIRequest"];

        self->_webView = [[DebounceWebView alloc] initWithFrame:self.view.frame configuration:configuration];
        NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
        NSString *deviceName = [[UIDevice currentDevice] name];
        NSString *userAgent = [NSString stringWithFormat:@"%@ (%@)", deviceName, appDisplayName];
        self->_webView.customUserAgent = [[NSString alloc] initWithCString:[userAgent UTF8String] encoding:NSASCIIStringEncoding];
        self->_webView.navigationDelegate = self;
        self->_webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [self->_webView loadRequest:request];
        [self.view addSubview:self->_webView];

        self->_activityIndicatorView = [[UIActivityIndicatorView alloc] init];
        self->_activityIndicatorView.center = self.view.center;
        self->_activityIndicatorView.color = [NCAppBranding brandColor];
        [self->_activityIndicatorView startAnimating];
        [self.view addSubview:self->_activityIndicatorView];
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    UIColor *themeColor = [NCAppBranding themeColor];
    [self.view setBackgroundColor:themeColor];

    [NCAppBranding styleViewController:self];

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(cancelButtonPressed)];
    cancelButton.accessibilityHint = NSLocalizedString(@"Double tap to dismiss authentication dialog", nil);
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
}

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return [NCAppBranding statusBarStyleForBrandColor];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - WKWebView Navigation Delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSArray *components = [url.absoluteString componentsSeparatedByString:@"&"];
    NSString *ncScheme = @"nc";
    
    if ([url.scheme isEqualToString:ncScheme]) {
        NSString *user = nil;
        NSString *token = nil;
        NSString *userPrefix = @"user:";
        NSString *passPrefix = @"password:";
        
        for (NSString *component in components)
        {
            if ([component hasPrefix:userPrefix])
                user = [[[component substringFromIndex:[userPrefix length]] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            if ([component hasPrefix:passPrefix])
                token = [[[component substringFromIndex:[passPrefix length]] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
        }
        
        [[NCSettingsController sharedInstance] addNewAccountForUser:user withToken:token inServer:_serverUrl];
        
        [self.delegate authenticationViewControllerDidFinish:self];
        
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if (navigationAction.targetFrame == nil) {
        [NCUtils openLinkInBrowserWithLink:url.absoluteString];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
    // Set a different accessibility identifier, to correctly determin if the webview is interactive or not
    [self.webView setAccessibilityIdentifier:@"nonInteractiveWebLoginView"];

    // Disable user interaction to prevent any unwanted zooming while the navigation is ongoing
    [self.webView setUserInteractionEnabled:NO];
    [_activityIndicatorView stopAnimating];
    [_activityIndicatorView removeFromSuperview];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.webView setUserInteractionEnabled:YES];
    [self.webView setAccessibilityIdentifier:@"interactiveWebLoginView"];
}


@end
