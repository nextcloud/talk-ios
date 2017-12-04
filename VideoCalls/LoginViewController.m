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


@interface LoginViewController () <UITextFieldDelegate, CCCertificateDelegate>

@end

@implementation LoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.appLogo.image = [UIImage imageNamed:@"loginLogo"];
    self.login.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.activityIndicatorView.color = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.activityIndicatorView.hidden = YES;
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
    NSString *serverUrl = self.serverUrl.text;
    
    // Check whether baseUrl contain protocol. If not add https:// by default.
    if(![serverUrl hasPrefix:@"https"] && ![serverUrl hasPrefix:@"http"]) {
        serverUrl = [NSString stringWithFormat:@"https://%@",serverUrl];
    }
    
    // Remove trailing slash
    if([serverUrl hasSuffix:@"/"]) {
        serverUrl = [serverUrl substringToIndex:[serverUrl length] - 1];
    }
    
    // Remove stored cookies
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies])
    {
        [storage deleteCookie:cookie];
    }
    
    [self.activityIndicatorView startAnimating];
    self.activityIndicatorView.hidden = NO;
    
    [[NCAPIController sharedInstance] setNCServer:serverUrl];
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger statusCode) {
        [self.activityIndicatorView stopAnimating];
        self.activityIndicatorView.hidden = YES;
        
        if (error) {
            // Self signed certificate
            if ([error code] == NSURLErrorServerCertificateUntrusted) {
                NSLog(@"Untrusted certificate");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
                });
                
            } else {
                if (statusCode == 401) {
                    AuthenticationViewController *authVC = [[AuthenticationViewController alloc] initWithServerUrl:serverUrl];
                    [self presentViewController:authVC animated:YES completion:nil];
                } else {
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:@"Nextcloud Talk app not found"
                                                 message:@"Please, check that you enter the correct Nextcloud server url and the Nextcloud Talk app is enabled in that instance."
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    
                    
                    
                    UIAlertAction* okButton = [UIAlertAction
                                               actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                               handler:nil];
                    
                    [alert addAction:okButton];
                    
                    [self presentViewController:alert animated:YES completion:nil];
                }
            }
        }
    }];
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

@end
