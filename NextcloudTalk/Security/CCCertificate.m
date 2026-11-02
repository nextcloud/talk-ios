//
// SPDX-FileCopyrightText: 2016 Marino Faggiana <m.faggiana@twsweb.it>, TWS
// SPDX-License-Identifier: GPL-3.0-or-later
//

#import "CCCertificate.h"

#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

@interface CCCertificate ()

// Last untrusted certificate per host, offered when the user is asked to accept it
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *pendingCertificates;

@end

@implementation CCCertificate

NSString *const appCertificates = @"Library/Application Support/Certificates";

// Stored next to the certificate of a host, as the directory name is a hash of the host
static NSString *const hostFileName = @"host";
static NSString *const certificateFileName = @"certificate.der";

//Singleton
+ (CCCertificate *)sharedManager {
    static CCCertificate *CCCertificate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CCCertificate = [[self alloc] init];
        CCCertificate.pendingCertificates = [NSMutableDictionary dictionary];
        [CCCertificate removeLegacyCertificates];
    });
    return CCCertificate;
}

static SecCertificateRef SecTrustGetLeafCertificate(SecTrustRef trust)
// Returns the leaf certificate from a SecTrust object (that is always the 
// certificate at index 0).
{
    SecCertificateRef   result;
    
    assert(trust != NULL);
    
    if (SecTrustGetCertificateCount(trust) > 0) {
        result = SecTrustGetCertificateAtIndex(trust, 0);
        assert(result != NULL);
    } else {
        result = NULL;
    }
    return result;
}

- (BOOL)checkTrustedChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    SecTrustRef trust = [protectionSpace serverTrust];

    if (trust == nil) {
        return NO;
    }

    NSData *certificateData = [self leafCertificateDataOfTrust:trust];
    NSString *hostDirectory = [self directoryForHost:protectionSpace.host];

    if (!certificateData || !hostDirectory) {
        return NO;
    }

    NSData *acceptedCertificateData = [NSData dataWithContentsOfFile:[hostDirectory stringByAppendingPathComponent:certificateFileName]];

    if ([acceptedCertificateData isEqualToData:certificateData]) {
        NSLog(@"Certificated matched with one saved previously.");
        return YES;
    }

    @synchronized (self.pendingCertificates) {
        self.pendingCertificates[[protectionSpace.host lowercaseString]] = certificateData;
    }

    return NO;
}

- (NSData *)leafCertificateDataOfTrust:(SecTrustRef)trust
{
    SecCertificateRef certificate = SecTrustGetLeafCertificate(trust);

    if (!certificate) {
        return nil;
    }

    return (__bridge_transfer NSData *)SecCertificateCopyData(certificate);
}

- (NSString *)hostFromError:(NSError *)error
{
    id failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];

    return [failingURL isKindOfClass:[NSURL class]] ? [failingURL host] : nil;
}

- (void)presentViewControllerCertificateWithError:(NSError *)error viewController:(UIViewController *)viewController delegate:(id)delegate
{
    if (![viewController isKindOfClass:[UIViewController class]])
        return;

    // Only the certificate seen for the failed host is accepted, and only for that host
    NSString *host = [self hostFromError:error];
    NSData *certificateData = nil;

    @synchronized (self.pendingCertificates) {
        certificateData = self.pendingCertificates[[host lowercaseString]];
    }

    if (!certificateData || !host) {
        NSLog(@"[LOG] Untrusted certificate error without certificate or host");
        return;
    }

    __weak id<CCCertificateDelegate> weakDelegate = delegate;

    NSString *certificatePath = [[self directoryForHost:host] stringByAppendingPathComponent:certificateFileName];
    BOOL certificateChanged = [[NSFileManager defaultManager] fileExistsAtPath:certificatePath];

    NSString *message = NSLocalizedString(@"Do you want to connect to the server anyway?", nil);

    if (certificateChanged) {
        message = NSLocalizedString(@"The certificate of this server has changed since you last accepted it. Do you want to connect to the server anyway?", nil);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:error.localizedDescription message:message preferredStyle:UIAlertControllerStyleAlert];
        
        [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            
            [[CCCertificate sharedManager] acceptCertificate:certificateData forHost:host];
            
            if([weakDelegate respondsToSelector:@selector(trustedCerticateAccepted)])
                [weakDelegate trustedCerticateAccepted];
        }]];
        
        [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"No", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            
            if([weakDelegate respondsToSelector:@selector(trustedCerticateDenied)])
                [weakDelegate trustedCerticateDenied];
        }]];
        
        [viewController presentViewController:alertController animated:YES completion:nil];
    });
}

- (BOOL)acceptCertificate:(NSData *)certificateData forHost:(NSString *)host
{
    NSString *hostDirectory = [self directoryForHost:host];

    if (!hostDirectory) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;

    // Replaces the certificate previously accepted for this host
    [fileManager removeItemAtPath:hostDirectory error:NULL];

    if (![fileManager createDirectoryAtPath:hostDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[LOG] Error: %@", [error localizedDescription]);
        return NO;
    }

    if (![host writeToFile:[hostDirectory stringByAppendingPathComponent:hostFileName] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[LOG] Error: %@", [error localizedDescription]);
        return NO;
    }

    NSString *currentCertLocation = [hostDirectory stringByAppendingPathComponent:certificateFileName];

    NSLog(@"[LOG] currentCertLocation: %@", currentCertLocation);

    if (![certificateData writeToFile:currentCertLocation options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[LOG] Error: %@", [error localizedDescription]);
        return NO;
    }
    
    return YES;
}

- (NSArray<NSString *> *)acceptedCertificateHosts
{
    NSString *localCertificatesFolder = [self getDirectoryCerificates];
    NSMutableArray<NSString *> *hosts = [NSMutableArray array];

    for (NSString *directoryName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:localCertificatesFolder error:NULL]) {
        NSString *hostFilePath = [[localCertificatesFolder stringByAppendingPathComponent:directoryName] stringByAppendingPathComponent:hostFileName];
        NSString *host = [NSString stringWithContentsOfFile:hostFilePath encoding:NSUTF8StringEncoding error:NULL];

        if (host.length > 0) {
            [hosts addObject:host];
        }
    }

    return [hosts sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSURL *)acceptedCertificateURLForHost:(NSString *)host
{
    NSString *hostDirectory = [self directoryForHost:host];

    if (!hostDirectory) {
        return nil;
    }

    return [NSURL fileURLWithPath:[hostDirectory stringByAppendingPathComponent:certificateFileName]];
}

- (BOOL)removeAcceptedCertificateForHost:(NSString *)host
{
    NSString *hostDirectory = [self directoryForHost:host];

    if (!hostDirectory) {
        return NO;
    }

    return [[NSFileManager defaultManager] removeItemAtPath:hostDirectory error:NULL];
}

- (NSString *)directoryForHost:(NSString *)host
{
    if (host.length == 0) {
        return nil;
    }

    // Hashed, as a host is not guaranteed to be a valid file name
    NSString *directoryName = [NCUtils sha256FromString:[host lowercaseString]];

    return [[self getDirectoryCerificates] stringByAppendingPathComponent:directoryName];
}

// Certificates accepted before they were stored per host are no longer trusted
- (void)removeLegacyCertificates
{
    NSString *localCertificatesFolder = [self getDirectoryCerificates];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:localCertificatesFolder error:NULL]) {
        NSString *path = [localCertificatesFolder stringByAppendingPathComponent:fileName];
        BOOL isDirectory = NO;

        if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
            [fileManager removeItemAtPath:path error:NULL];
        }
    }
}

- (NSString *)getDirectoryCerificates
{
    NSURL *dirGroup = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier];
    
    NSString *dir = [[dirGroup URLByAppendingPathComponent:appCertificates] path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir])
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    
    return dir;
}

@end
