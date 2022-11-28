/**
 * @copyright Copyright (c) 2022 Marcel Müller <marcel.mueller@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 * @author Marcel Müller <marcel.mueller@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
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
