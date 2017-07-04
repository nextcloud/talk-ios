//
//  LoginViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 30.05.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LoginViewController : UIViewController

@property (nonatomic, weak) IBOutlet UIImageView *appLogo;
@property (nonatomic, weak) IBOutlet UITextField *serverUrl;
@property (nonatomic, weak) IBOutlet UIImageView *imageBaseUrl;
@property (nonatomic, weak) IBOutlet UIButton *login;

@end
