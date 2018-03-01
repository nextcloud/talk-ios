//
//  AuthenticationViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 07.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class AuthenticationViewController;
@protocol AuthenticationViewControllerDelegate <NSObject>

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController;

@end

@interface AuthenticationViewController : UIViewController

@property (nonatomic, weak) id<AuthenticationViewControllerDelegate> delegate;

@property(strong,nonatomic) WKWebView *webView;
@property(strong, nonatomic) NSString *serverUrl;

- (id)initWithServerUrl:(NSString *)serverUrl;

@end
