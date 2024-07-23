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

@property (weak) id<CCCertificateDelegate> delegate;

+ (CCCertificate *)sharedManager;

- (BOOL)checkTrustedChallenge:(NSURLAuthenticationChallenge *)challenge;
- (BOOL)acceptCertificate;
- (void)saveCertificate:(SecTrustRef)trust withName:(NSString *)certName;

- (void)presentViewControllerCertificateWithTitle:(NSString *)title viewController:(UIViewController *)viewController delegate:(id)delegate;

@end

