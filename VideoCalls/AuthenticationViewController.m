//
//  AuthenticationViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 07.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "AuthenticationViewController.h"

#import "NCAPIController.h"
#import "NCSettingsController.h"

NSString * const kNCAuthTokenFlowEndpoint       = @"/index.php/login/flow";
NSString * const NCLoginCompletedNotification   = @"NCLoginCompletedNotification";

@interface AuthenticationViewController () <WKNavigationDelegate>

@end

@implementation AuthenticationViewController

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
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", _serverUrl, kNCAuthTokenFlowEndpoint]];
    
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies])
    {
        [storage deleteCookie:cookie];
    }
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"true" forHTTPHeaderField:@"OCS-APIRequest"];
    
    _webView = [[WKWebView alloc] initWithFrame:self.view.frame
                                  configuration:configuration];
    _webView.customUserAgent = @"Video Calls iOS";
    _webView.navigationDelegate = self;
    
    [_webView loadRequest:request];
    [self.view addSubview:_webView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
                user = [component substringFromIndex:[userPrefix length]];
            if ([component hasPrefix:passPrefix])
                token = [component substringFromIndex:[passPrefix length]];
        }
        
        NSLog(@"SERVER:%@ USER:%@ TOKEN:%@", _serverUrl, user, token);
        
        [NCSettingsController sharedInstance].ncServer = _serverUrl;
        [NCSettingsController sharedInstance].ncUser = user;
        [NCSettingsController sharedInstance].ncToken = token;
        
        [UICKeyChainStore setString:_serverUrl forKey:kNCServerKey];
        [UICKeyChainStore setString:user forKey:kNCUserKey];
        [UICKeyChainStore setString:token forKey:kNCTokenKey];
        
        [[NCAPIController sharedInstance] setNCServer:_serverUrl];
        [[NCAPIController sharedInstance] setAuthHeaderWithUser:user andToken:token];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NCLoginCompletedNotification
                                                            object:self
                                                          userInfo:@{kNCServerKey:_serverUrl,
                                                                     kNCUserKey:user,
                                                                     kNCTokenKey:token}];
        
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSLog(@"Allow all");
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    CFDataRef exceptions = SecTrustCopyExceptions (serverTrust);
    SecTrustSetExceptions (serverTrust, exceptions);
    CFRelease (exceptions);
    completionHandler (NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
}


@end
