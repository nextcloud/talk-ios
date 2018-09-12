//
//  AuthenticationViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 07.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "AuthenticationViewController.h"

#import "CCCertificate.h"
#import "NCAPIController.h"
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
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *deviceName = [[UIDevice currentDevice] name];
    _webView.customUserAgent = [NSString stringWithFormat:@"%@ (%@)", deviceName, appDisplayName];
    _webView.navigationDelegate = self;
    
    [_webView loadRequest:request];
    [self.view addSubview:_webView];
    
    _activityIndicatorView = [[UIActivityIndicatorView alloc] init];
    _activityIndicatorView.center = self.view.center;
    _activityIndicatorView.color = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    [_activityIndicatorView startAnimating];
    [self.view addSubview:_activityIndicatorView];
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
                user = [[[component substringFromIndex:[userPrefix length]] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            if ([component hasPrefix:passPrefix])
                token = [[[component substringFromIndex:[passPrefix length]] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
        }
        
        [NCSettingsController sharedInstance].ncServer = _serverUrl;
        [NCSettingsController sharedInstance].ncUser = user;
        [NCSettingsController sharedInstance].ncToken = token;
        
        UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:@"com.nextcloud.Talk"
                                                                    accessGroup:@"group.com.nextcloud.Talk"];
        
        [keychain setString:_serverUrl forKey:kNCServerKey];
        [keychain setString:user forKey:kNCUserKey];
        [keychain setString:token forKey:kNCTokenKey];
        
        [[NCAPIController sharedInstance] setNCServer:_serverUrl];
        [[NCAPIController sharedInstance] setAuthHeaderWithUser:user andToken:token];
        
        [[NCSettingsController sharedInstance] generatePushNotificationsKeyPair];
        
        // Subscribe to NC server
        [[NCAPIController sharedInstance] subscribeToNextcloudServer:^(NSDictionary *responseDict, NSError *error) {
            if (!error) {
                NSLog(@"Subscribed to NC server successfully.");
                
                NSString *publicKey = [responseDict objectForKey:@"publicKey"];
                NSString *deviceIdentifier = [responseDict objectForKey:@"deviceIdentifier"];
                NSString *signature = [responseDict objectForKey:@"signature"];

                [NCSettingsController sharedInstance].ncUserPublicKey = publicKey;
                [NCSettingsController sharedInstance].ncDeviceIdentifier = deviceIdentifier;
                [NCSettingsController sharedInstance].ncDeviceSignature = signature;
                
                [keychain setString:publicKey forKey:kNCUserPublicKey];
                [keychain setString:deviceIdentifier forKey:kNCDeviceIdentifier];
                [keychain setString:signature forKey:kNCDeviceSignature];
                
                [[NCAPIController sharedInstance] subscribeToPushServer:^(NSError *error) {
                    if (!error) {
                        NSLog(@"Subscribed to Push Notification server successfully.");
                    } else {
                        NSLog(@"Error while subscribing to Push Notification server.");
                    }
                }];
            } else {
                NSLog(@"Error while subscribing to NC server.");
                NSLog([error localizedDescription]);
            }
        }];
        
        [self.delegate authenticationViewControllerDidFinish:self];
        
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
    [_activityIndicatorView stopAnimating];
    [_activityIndicatorView removeFromSuperview];
}


@end
