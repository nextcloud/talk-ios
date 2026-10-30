//
// SPDX-FileCopyrightText: 2016 Marino Faggiana <m.faggiana@twsweb.it>, TWS
// SPDX-License-Identifier: GPL-3.0-or-later
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol CCCertificateDelegate <NSObject>

@optional - (void)trustedCerticateAccepted;
@optional - (void)trustedCerticateDenied;

@end

@interface CCCertificate : NSObject

+ (CCCertificate *)sharedManager;

- (BOOL)checkTrustedChallenge:(NSURLAuthenticationChallenge *)challenge;
- (BOOL)acceptCertificate:(NSData *)certificateData forHost:(NSString *)host NS_SWIFT_NAME(acceptCertificate(_:forHost:));

- (void)presentViewControllerCertificateWithError:(NSError *)error viewController:(UIViewController *)viewController delegate:(id)delegate NS_SWIFT_NAME(presentViewControllerCertificate(withError:viewController:delegate:));

@end

