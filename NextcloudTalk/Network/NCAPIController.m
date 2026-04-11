/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCAPIController.h"

@import NextcloudKit;

#import <SDWebImage/SDWebImageManager.h>
#import <SDWebImageSVGKitDefine.h>
#import <SDWebImage/SDImageCache.h>

#import "CCCertificate.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCKeyChainController.h"
#import "NotificationCenterNotifications.h"

#import "NextcloudTalk-Swift.h"

NSInteger const APIv1                       = 1;
NSInteger const APIv2                       = 2;
NSInteger const APIv3                       = 3;
NSInteger const APIv4                       = 4;

NSString * const kDavEndpoint               = @"/remote.php/dav";
NSString * const kNCOCSAPIVersion           = @"/ocs/v2.php";
NSString * const kNCSpreedAPIVersionBase    = @"/apps/spreed/api/v";

NSInteger const kReceivedChatMessagesLimit = 100;

@interface NCAPIController () <NSURLSessionTaskDelegate, NSURLSessionDelegate, NKCommonDelegate>

@property (nonatomic, strong) NSCache<NSString *, NSString *> *authTokenCache;
@property (nonatomic, strong) NSCache<NSString *, SDWebImageDownloaderRequestModifier *> *requestModifierCache;

@end

@implementation NCAPIController

+ (NCAPIController *)sharedInstance
{
    static dispatch_once_t once;
    static NCAPIController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.authTokenCache = [[NSCache alloc] init];
        self.requestModifierCache = [[NSCache alloc] init];
        
        [self initSessionManagers];
        [self initImageDownloaders];
    }
    
    return self;
}

- (void)initSessionManagers
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPCookieStorage = nil;
    _defaultAPISessionManager = [[NCAPISessionManager alloc] initWithConfiguration:configuration];
    
    _apiSessionManagers = [NSMutableDictionary new];
    _longPollingApiSessionManagers = [NSMutableDictionary new];
    _calDAVSessionManagers = [NSMutableDictionary new];

    for (TalkAccount *account in [[NCDatabaseManager sharedInstance] allAccounts]) {
        [self createAPISessionManagerForAccount:account];
    }
}

- (void)createAPISessionManagerForAccount:(TalkAccount *)account
{
    // Make sure there are no old entries in our caches when we create APISessionManagers
    [self.authTokenCache removeObjectForKey:account.accountId];
    [self.requestModifierCache removeObjectForKey:account.accountId];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:account.accountId];
    configuration.HTTPCookieStorage = cookieStorage;
    NCAPISessionManager *apiSessionManager = [[NCAPISessionManager alloc] initWithConfiguration:configuration];
    [apiSessionManager.requestSerializer setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];

    // As we can run max. 30s in the background, the default timeout should be lower than 30 to avoid being killed by the OS
    [apiSessionManager.requestSerializer setTimeoutInterval:25];
    [_apiSessionManagers setObject:apiSessionManager forKey:account.accountId];

    configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:account.accountId];
    configuration.HTTPCookieStorage = cookieStorage;
    apiSessionManager = [[NCAPISessionManager alloc] initWithConfiguration:configuration];
    [apiSessionManager.requestSerializer setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    [_longPollingApiSessionManagers setObject:apiSessionManager forKey:account.accountId];

    configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:account.accountId];
    configuration.HTTPCookieStorage = cookieStorage;
    NCCalDAVSessionManager *calDAVSessionManager = [[NCCalDAVSessionManager alloc] initWithConfiguration:configuration];
    [calDAVSessionManager.requestSerializer setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    [_calDAVSessionManagers setObject:calDAVSessionManager forKey:account.accountId];
}

- (void)removeAPISessionManagerForAccount:(TalkAccount *)account
{
    [self.authTokenCache removeObjectForKey:account.accountId];
    [self.requestModifierCache removeObjectForKey:account.accountId];
    [self.apiSessionManagers removeObjectForKey:account.accountId];
    [self.longPollingApiSessionManagers removeObjectForKey:account.accountId];
    [self.calDAVSessionManagers removeObjectForKey:account.accountId];
}

- (void)setupNCCommunicationForAccount:(TalkAccount *)account
{
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    NSString *userToken = [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    [[NextcloudKit shared] setupWithAccount:account.accountId user:account.user userId:account.userId password:userToken urlBase:account.server userAgent:userAgent nextcloudVersion:serverCapabilities.versionMajor delegate:self];
}

- (void)initImageDownloaders
{
    // The defaults for the shared url cache are very low, use some sane values for caching. Apple only caches assets <= 5% of the available space.
    // Otherwise some (user) avatars will never be cached and always requested
    NSURLCache *sharedURLCache = [[NSURLCache alloc] initWithMemoryCapacity:20 * 1024 * 1024
                                                               diskCapacity:100 * 1024 * 1024
                                                                   diskPath:nil];

    [NSURLCache setSharedURLCache:sharedURLCache];

    // By default SDWebImageDownloader defaults to 6 concurrent downloads (see SDWebImageDownloaderConfig)

    // Make sure we support download SVGs with SDImageDownloader
    [[SDImageCodersManager sharedManager] addCoder:[SDImageSVGKCoder sharedCoder]];

    // Make sure we support self-signed certificates we trusted before
    [[SDWebImageDownloader sharedDownloader].config setOperationClass:[NCWebImageDownloaderOperation class]];

    // Limit the cache size to 100 MB and prevent uploading to iCloud
    // Don't set the path to an app group in order to prevent crashes
    [SDImageCache sharedImageCache].config.shouldDisableiCloud = YES;
    [SDImageCache sharedImageCache].config.maxDiskSize = 100 * 1024 * 1024;
    [SDImageCache sharedImageCache].config.maxDiskAge = 60 * 60 * 24 * 7 * 4; // 4 weeks

    // We expire the cache once on app launch, see AppDelegate
    [SDImageCache sharedImageCache].config.shouldRemoveExpiredDataWhenTerminate = NO;
    [SDImageCache sharedImageCache].config.shouldRemoveExpiredDataWhenEnterBackground = NO;

    [[SDWebImageDownloader sharedDownloader] setValue:[NCAppBranding userAgent] forHTTPHeaderField:@"User-Agent"];
}

- (NSString *)authHeaderForAccount:(TalkAccount *)account
{
    NSString *cachedHeader = [self.authTokenCache objectForKey:account.accountId];

    if (cachedHeader) {
        return cachedHeader;
    }

    NSString *userTokenString = [NSString stringWithFormat:@"%@:%@", account.user, [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId]];
    NSData *data = [userTokenString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Encoded = [data base64EncodedStringWithOptions:0];

    NSString *authHeader = [[NSString alloc] initWithFormat:@"Basic %@",base64Encoded];
    [self.authTokenCache setObject:authHeader forKey:account.accountId];

    return authHeader;
}

- (SDWebImageDownloaderRequestModifier *)getRequestModifierForAccount:(TalkAccount *)account
{
    SDWebImageDownloaderRequestModifier *cachedModifier = [self.requestModifierCache objectForKey:account.accountId];

    if (cachedModifier) {
        return cachedModifier;
    }

    NSMutableDictionary *headerDictionary = [[NSMutableDictionary alloc] init];
    [headerDictionary setObject:[self authHeaderForAccount:account] forKey:@"Authorization"];

    SDWebImageDownloaderRequestModifier *requestModifier = [[SDWebImageDownloaderRequestModifier alloc] initWithHeaders:headerDictionary];
    [self.requestModifierCache setObject:requestModifier forKey:account.accountId];

    return requestModifier;
}


@end
