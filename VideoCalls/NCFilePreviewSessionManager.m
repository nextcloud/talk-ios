//
//  NCFilePreviewSessionManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 28.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCFilePreviewSessionManager.h"
#import "CCCertificate.h"

@interface NCFilePreviewSessionManager () <NSURLSessionTaskDelegate, NSURLSessionDelegate>
{
    NSString *_serverUrl;
    NSString *_authHeader;
    NSString *_userAgent;
}

@end

@implementation NCFilePreviewSessionManager

+ (NCFilePreviewSessionManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCFilePreviewSessionManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)setNCServer:(NSString *)serverUrl
{
    _serverUrl = serverUrl;
}

- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token
{
    NSString *userTokenString = [NSString stringWithFormat:@"%@:%@", user, token];
    NSData *data = [userTokenString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Encoded = [data base64EncodedStringWithOptions:0];
    
    NSString *authHeader = [[NSString alloc]initWithFormat:@"Basic %@",base64Encoded];
    [[NCFilePreviewSessionManager sharedInstance].requestSerializer setValue:authHeader forHTTPHeaderField:@"Authorization"];
        
    _authHeader = authHeader;
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

- (NSURLSessionDataTask *)getFilePreview:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height withCompletionBlock:(GetFilePreviewCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/index.php/core/preview", _serverUrl];
    NSDictionary *parameters = @{@"fileId" : fileId,
                                 @"x" : @(width),
                                 @"y" : @(height),
                                 @"forceIcon" : @(1)};
    
    NSURLSessionDataTask *task = [[NCFilePreviewSessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(responseObject, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height
{
    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=%ld&y=%ld&forceIcon=1", _serverUrl, fileId, (long)width, (long)height];
    NSMutableURLRequest *previewRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    [previewRequest setValue:_authHeader forHTTPHeaderField:@"Authorization"];
    return previewRequest;
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
