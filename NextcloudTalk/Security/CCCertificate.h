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

// Posted on the main queue after a certificate was accepted, userInfo contains the host
extern NSString *const CCCertificateAcceptedNotification;
extern NSString *const CCCertificateHostKey;

@interface CCCertificate : NSObject

+ (CCCertificate *)sharedManager;

- (BOOL)checkTrustedChallenge:(NSURLAuthenticationChallenge *)challenge;
- (BOOL)acceptCertificate:(NSData *)certificateData forHost:(NSString *)host NS_SWIFT_NAME(acceptCertificate(_:forHost:));

- (NSArray<NSString *> *)acceptedCertificateHosts;
- (NSURL *)acceptedCertificateURLForHost:(NSString *)host NS_SWIFT_NAME(acceptedCertificateURL(forHost:));
- (BOOL)removeAcceptedCertificateForHost:(NSString *)host NS_SWIFT_NAME(removeAcceptedCertificate(forHost:));

- (void)presentViewControllerCertificateWithError:(NSError *)error viewController:(UIViewController *)viewController delegate:(id)delegate NS_SWIFT_NAME(presentViewControllerCertificate(withError:viewController:delegate:));

@end

