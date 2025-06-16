/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

@class LoginViewController;
@protocol LoginViewControllerDelegate <NSObject>

- (void)loginViewControllerDidFinish:(LoginViewController *)viewController;

@end

@interface LoginViewController : UIViewController

@property (nonatomic, weak) id<LoginViewControllerDelegate> delegate;

@property (nonatomic, weak) IBOutlet UIImageView *appLogo;
@property (nonatomic, weak) IBOutlet UITextField *serverUrl;
@property (weak, nonatomic) IBOutlet UILabel *serverUrlNote;
@property (nonatomic, weak) IBOutlet UIButton *login;
@property (nonatomic, weak) IBOutlet UIButton *cancel;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, weak) IBOutlet UIButton *qrCodeLogin;
@property (weak, nonatomic) IBOutlet UILabel *qrCodeLoginNote;
@property (weak, nonatomic) IBOutlet UIButton *importButton;

- (void)startLoginProcessWithServerURL:(NSString *)serverURL withUser:(NSString *)user;

@end
