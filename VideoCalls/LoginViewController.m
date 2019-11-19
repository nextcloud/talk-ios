//
//  LoginViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 30.05.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "LoginViewController.h"

#import "AuthenticationViewController.h"
#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"

@interface LoginViewController () <UITextFieldDelegate, CCCertificateDelegate, AuthenticationViewControllerDelegate>
{
    AuthenticationViewController *_authenticationViewController;
    NSString *_serverURL;
}

@end

@implementation LoginViewController

@synthesize delegate = _delegate;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.appLogo.image = [UIImage imageNamed:@"loginLogo"];
    self.view.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    NSString *serverUrlPlaceholderText = @"Server address https://…";
    self.serverUrl.textColor = [UIColor whiteColor];
    self.serverUrl.tintColor = [UIColor whiteColor];
    self.serverUrl.attributedPlaceholder = [[NSAttributedString alloc] initWithString:serverUrlPlaceholderText
                                                                           attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:0.5]}];
    
    self.login.backgroundColor = [UIColor whiteColor];
    [self.login setTitleColor:[UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0] forState:UIControlStateNormal]; //#0082C9
    
    self.activityIndicatorView.color = [UIColor whiteColor];
    self.activityIndicatorView.hidden = YES;
    
    self.cancel.hidden = !(multiAccountEnabled && [[NCDatabaseManager sharedInstance] numberOfAccounts] > 0);
    [self.cancel setTitle:@"Cancel" forState:UIControlStateNormal];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (IBAction)login:(id)sender
{
    _serverURL = self.serverUrl.text;
    
    // Check whether baseUrl contain protocol. If not add https:// by default.
    if(![_serverURL hasPrefix:@"https"] && ![_serverURL hasPrefix:@"http"]) {
        _serverURL = [NSString stringWithFormat:@"https://%@",_serverURL];
    }
    
    // Remove trailing slash
    if([_serverURL hasSuffix:@"/"]) {
        _serverURL = [_serverURL substringToIndex:[_serverURL length] - 1];
    }
    
    // Remove stored cookies
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies])
    {
        [storage deleteCookie:cookie];
    }
    
    // Check if valid URL
    NSURL *serverURL = [NSURL URLWithString:_serverURL];
    if (serverURL) {
        [self startLoginProcess];
    } else {
        [self showAlertWithTitle:@"Invalid server address" andMessage:@"Please check that you entered a valid server address."];
    }
}

- (IBAction)cancel:(id)sender
{
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)trustedCerticateAccepted
{
    [self login:self];
}

-(BOOL) textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Login

- (void)startLoginProcess
{
    [self.activityIndicatorView startAnimating];
    self.activityIndicatorView.hidden = NO;
    [[NCAPIController sharedInstance] getServerCapabilitiesForServer:_serverURL withCompletionBlock:^(NSDictionary *serverCapabilities, NSError *error) {
        [self.activityIndicatorView stopAnimating];
        self.activityIndicatorView.hidden = YES;
        if (!error) {
            NSArray *talkFeatures = [[[serverCapabilities objectForKey:@"capabilities"] objectForKey:@"spreed"] objectForKey:@"features"];
            // Check minimum required version
            if ([talkFeatures containsObject:kMinimunRequiredTalkCapability]) {
                [self presentAuthenticationView];
            } else if (talkFeatures.count == 0) {
                    [self showAlertWithTitle:@"Nextcloud Talk not installed" andMessage:@"It seems that Nextcloud Talk is not installed in your server."];
            } else {
                [self showAlertWithTitle:@"Nextcloud Talk version not supported" andMessage:@"Please update your server with the latest Nextcloud Talk version available."];
            }
        } else {
            // Self signed certificate
            if ([error code] == NSURLErrorServerCertificateUntrusted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
                });
            } else {
                [self showAlertWithTitle:@"Nextcloud server not found" andMessage:@"Please check that you entered the correct Nextcloud server address."];
            }
        }
    }];
}

- (void)presentAuthenticationView
{
    _authenticationViewController = [[AuthenticationViewController alloc] initWithServerUrl:_serverURL];
    _authenticationViewController.delegate = self;
    [self presentViewController:_authenticationViewController animated:YES completion:nil];
}

#pragma mark - Alerts

- (void)showAlertWithTitle:(NSString *)title andMessage:(NSString *)message
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:title
                                 message:message
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
                                   [_serverUrl becomeFirstResponder];
                               }];
    
    [alert addAction:okButton];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AuthenticationViewControllerDelegate

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController
{
    if (viewController == _authenticationViewController) {
        [self.delegate loginViewControllerDidFinish:self];
    }
}


@end
