/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class AuthenticationViewController;
@protocol AuthenticationViewControllerDelegate <NSObject>

- (void)authenticationViewControllerDidFinish:(AuthenticationViewController *)viewController;

@end

@interface AuthenticationViewController : UIViewController

@property (nonatomic, weak) id<AuthenticationViewControllerDelegate> delegate;

@property(strong, nonatomic) WKWebView *webView;
@property(strong, nonatomic) NSString *serverUrl;
@property(strong, nonatomic) NSString *user;

- (id)initWithServerUrl:(NSString *)serverUrl;

@end
