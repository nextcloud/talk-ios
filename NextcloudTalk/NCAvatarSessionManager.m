/**
 * SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCAppBranding.h"
#import "NCAvatarSessionManager.h"
#import "AFImageDownloader.h"

#import "CCCertificate.h"

@implementation NCAvatarSessionManager

+ (NCAvatarSessionManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCAvatarSessionManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    NSURLSessionConfiguration *configuration = [AFImageDownloader defaultURLSessionConfiguration];

    // In case of avatars we want to use the cache and store it on disk
    // As we use the memory cache from AFImageDownloader, we only want disk cache here
    NSURL *avatarCacheURL = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] URLByAppendingPathComponent:@"AvatarCache"];
    self.cache = [[NSURLCache alloc] initWithMemoryCapacity:0
                                               diskCapacity:100 * 1024 * 1024
                                               directoryURL:avatarCacheURL];

    configuration.URLCache = self.cache;

    self = [super initWithSessionConfiguration:configuration];
    if (self) {
        _userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@",
                      [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
        
        self.responseSerializer = [[AFImageResponseSerializer alloc] init];
        self.requestSerializer = [[AFHTTPRequestSerializer alloc] init];
        
        AFSecurityPolicy* policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        self.securityPolicy = policy;
        
        self.responseSerializer.acceptableContentTypes = [self.responseSerializer.acceptableContentTypes setByAddingObject:@"image/jpg"];
        [self.requestSerializer setValue:_userAgent forHTTPHeaderField:@"User-Agent"];
    }
    return self;
}

-(void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end
