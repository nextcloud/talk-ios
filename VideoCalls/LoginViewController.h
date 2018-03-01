//
//  LoginViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 30.05.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

@class LoginViewController;
@protocol LoginViewControllerDelegate <NSObject>

- (void)loginViewControllerDidFinish:(LoginViewController *)viewController;

@end

@interface LoginViewController : UIViewController

@property (nonatomic, weak) id<LoginViewControllerDelegate> delegate;

@property (nonatomic, weak) IBOutlet UIImageView *appLogo;
@property (nonatomic, weak) IBOutlet UITextField *serverUrl;
@property (nonatomic, weak) IBOutlet UIImageView *imageBaseUrl;
@property (nonatomic, weak) IBOutlet UIButton *login;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *activityIndicatorView;

@end
