//
//  NCImageSessionManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 04.12.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCImageSessionManager.h"
#import "CCCertificate.h"

@implementation NCImageSessionManager

+ (NCImageSessionManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCImageSessionManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    // Set ephemeralSessionConfiguration and just use AFAutoPurgingImageCache for caching images.
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
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
