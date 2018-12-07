//
//  NCPushProxySessionManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 04.12.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCPushProxySessionManager.h"
#import "CCCertificate.h"

@implementation NCPushProxySessionManager

+ (NCPushProxySessionManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCPushProxySessionManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    self = [super initWithSessionConfiguration:configuration];
    if (self) {
        _userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@ (PushKit)",
                      [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
        
        self.responseSerializer = [[AFHTTPResponseSerializer alloc] init];
        self.requestSerializer = [[AFHTTPRequestSerializer alloc] init];
        
        AFSecurityPolicy* policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        self.securityPolicy = policy;
        
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
