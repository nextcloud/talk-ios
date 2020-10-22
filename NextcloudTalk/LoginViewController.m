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
    self.view.backgroundColor = [NCAppBranding brandPrimaryColor];
    
    NSString *serverUrlPlaceholderText = NSLocalizedString(@"Server address https://…", nil);
    self.serverUrl.textColor = [NCAppBranding brandPrimaryTextColor];
    self.serverUrl.tintColor = [NCAppBranding brandPrimaryTextColor];
    self.serverUrl.attributedPlaceholder = [[NSAttributedString alloc] initWithString:serverUrlPlaceholderText
                                                                           attributes:@{NSForegroundColorAttributeName:[[NCAppBranding brandPrimaryTextColor] colorWithAlphaComponent:0.5]}];
    
    self.login.backgroundColor = [NCAppBranding brandPrimaryTextColor];
    [self.login setTitleColor:[NCAppBranding brandPrimaryColor] forState:UIControlStateNormal];
    
    self.activityIndicatorView.color = [NCAppBranding brandPrimaryTextColor];
    self.activityIndicatorView.hidden = YES;
    
    self.cancel.hidden = !(multiAccountEnabled && [[NCDatabaseManager sharedInstance] numberOfAccounts] > 0);
    [self.cancel setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
    [self.cancel setTitleColor:[NCAppBranding brandPrimaryTextColor] forState:UIControlStateNormal];
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
        [self showAlertWithTitle:NSLocalizedString(@"Invalid server address", nil) andMessage:NSLocalizedString(@"Please check that you entered a valid server address.", nil)];
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
            if ([talkFeatures containsObject:kMinimumRequiredTalkCapability]) {
                [self presentAuthenticationView];
            } else if (talkFeatures.count == 0) {
                [self showAlertWithTitle:NSLocalizedString(@"Nextcloud Talk not installed", nil) andMessage:NSLocalizedString(@"It seems that Nextcloud Talk is not installed in your server.", nil)];
            } else {
                [self showAlertWithTitle:NSLocalizedString(@"Nextcloud Talk version not supported", nil) andMessage:NSLocalizedString(@"Please update your server with the latest Nextcloud Talk version available.", nil)];
            }
        } else {
            // Self signed certificate
            if ([error code] == NSURLErrorServerCertificateUntrusted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
                });
            } else {
                [self showAlertWithTitle:NSLocalizedString(@"Nextcloud server not found", nil) andMessage:NSLocalizedString(@"Please check that you entered the correct Nextcloud server address.", nil)];
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
                               actionWithTitle:NSLocalizedString(@"OK", nil)
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
