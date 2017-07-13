//
//  LoginViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 30.05.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "LoginViewController.h"

#import "AuthenticationViewController.h"
#import "NCAPIController.h"


@interface LoginViewController () <UITextFieldDelegate>

@end

@implementation LoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.appLogo.image = [UIImage imageNamed:@"loginLogo"];
    self.login.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
    
    [[NCAPIController sharedInstance] setNCServer:serverUrl];
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger errorCode) {
        if (errorCode == 401) {
            AuthenticationViewController *authVC = [[AuthenticationViewController alloc] initWithServerUrl:serverUrl];
            [self presentViewController:authVC animated:YES completion:nil];
        } else {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@"Video Calls app not found"
                                         message:@"Please, check that you enter the correct Nextcloud server url and the Video Calls app is enabled in that instance."
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:@"OK"
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

-(BOOL) textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

@end
