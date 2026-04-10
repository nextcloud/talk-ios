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

#pragma mark - User avatars

- (SDWebImageCombinedOperation *)getUserAvatarForUser:(NSString *)userId usingAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetUserAvatarImageForUserCompletionBlock)block
{
    return [self getUserAvatarForUser:userId usingAccount:account withStyle:style ignoreCache:NO withCompletionBlock:block];
}

- (SDWebImageCombinedOperation *)getUserAvatarForUser:(NSString *)userId usingAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style ignoreCache:(BOOL)ignoreCache withCompletionBlock:(GetUserAvatarImageForUserCompletionBlock)block
{
    NSString *encodedUser = [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];

    // Since https://github.com/nextcloud/server/pull/31010 we can only request avatars in 64px or 512px
    // As we never request lower than 96px, we always get 512px anyway
    long avatarSize = 512;

    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/avatar/%@/%ld", account.server, encodedUser, avatarSize];

    if (style == UIUserInterfaceStyleDark && serverCapabilities.versionMajor >= 25) {
        urlString = [NSString stringWithFormat:@"%@/dark", urlString];
    }

    NSURL *url = [NSURL URLWithString:urlString];

    SDWebImageOptions options = SDWebImageRetryFailed;

    if (ignoreCache) {
        // In case we want to ignore our local caches, we can't provide SDWebImageRefreshCached, as this will
        // always use NSURLCache and could still return a cached value here
        options |= SDWebImageFromLoaderOnly;
    } else {
        // We want to refresh our cache when the NSURLCache determines that the resource is not fresh anymore
        // see: https://github.com/SDWebImage/SDWebImage/wiki/Common-Problems#handle-image-refresh
        // Could be removed when all conversations have a avatarVersion, see https://github.com/nextcloud/spreed/issues/9320
        options |= SDWebImageRefreshCached;
    }

    SDWebImageDownloaderRequestModifier *requestModifier = [self getRequestModifierForAccount:account];

    return [[SDWebImageManager sharedManager] loadImageWithURL:url options:options context:@{SDWebImageContextDownloadRequestModifier : requestModifier} progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (error) {
            // When the request was cancelled before completing, we expect no completion handler to be called
            if (block && error.code != SDWebImageErrorCancelled) {
                block(nil, error);
            }

            return;
        }

        if (image && block) {
            block(image, nil);
        }
    }];
}

- (SDWebImageCombinedOperation *)getFederatedUserAvatarForUser:(NSString *)userId inRoom:(NSString *)token usingAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetFederatedUserAvatarImageForUserCompletionBlock)block
{
    NSString *encodedToken = @"new";
    if (token.length > 0) {
        encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    }
    NSString *endpoint = [NSString stringWithFormat:@"proxy/%@/user-avatar/512", encodedToken];

    if (style == UIUserInterfaceStyleDark) {
        endpoint = [NSString stringWithFormat:@"%@/dark", endpoint];
    }

    NSString *encodedUserId = [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    endpoint = [NSString stringWithFormat:@"%@?cloudId=%@", endpoint, encodedUserId];

    NSInteger avatarAPIVersion = 1;
    NSString *urlString = [self getRequestURLForEndpoint:endpoint withAPIVersion:avatarAPIVersion forAccount:account];
    NSURL *url = [NSURL URLWithString:urlString];

    // See getAvatarForRoom for explanation
    SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageRefreshCached | SDWebImageQueryDiskDataSync;
    SDWebImageDownloaderRequestModifier *requestModifier = [self getRequestModifierForAccount:account];

    // Make sure we get at least a 120x120 image when retrieving an SVG with SVGKit
    SDWebImageContext *context = @{
        SDWebImageContextDownloadRequestModifier : requestModifier,
        SDWebImageContextImageThumbnailPixelSize : @(CGSizeMake(120, 120))
    };

    return [[SDWebImageManager sharedManager] loadImageWithURL:url options:options context:context progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (error) {
            // When the request was cancelled before completing, we expect no completion handler to be called
            if (block && error.code != SDWebImageErrorCancelled) {
                block(nil, error);
            }

            return;
        }

        if (image && block) {
            block(image, nil);
        }
    }];
}

#pragma mark - Conversation avatars

- (SDWebImageCombinedOperation *)getAvatarForRoom:(NCRoom *)room withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetAvatarForConversationWithImageCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:room.accountId];
    NSString *encodedToken = [room.token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/avatar", encodedToken];

    if (style == UIUserInterfaceStyleDark) {
        endpoint = [NSString stringWithFormat:@"%@/dark", endpoint];
    }

    // For non-one-to-one conversation we do have a valid avatarVersion which we can use to cache the avatar
    // For one-to-one conversations we rely on the caching that is specified by the server via cache-control header
    if (room.type != kNCRoomTypeOneToOne) {
        endpoint = [NSString stringWithFormat:@"%@?avatarVersion=%@", endpoint, room.avatarVersion];
    }

    NSInteger avatarAPIVersion = 1;
    NSString *urlString = [self getRequestURLForEndpoint:endpoint withAPIVersion:avatarAPIVersion forAccount:account];
    NSURL *url = [NSURL URLWithString:urlString];

    /*
     SDWebImageRetryFailed:         By default SDWebImage blacklists URLs that failed to load and does not try to
                                    load these URLs again, but we want to retry these.
                                    Also see https://github.com/SDWebImage/SDWebImage/wiki/Common-Problems#handle-image-refresh

     SDWebImageRefreshCached:       By default the cache-control header returned by the webserver is ignored and
                                    images are cached forever. With this parameter we let NSURLCache determine
                                    if a resource needs to be reloaded from the server again.
                                    Could be removed if this endpoint returns an avatar version for all calls.
                                    Also see https://github.com/nextcloud/spreed/issues/9320

     SDWebImageQueryDiskDataSync:   SDImage loads data from the disk cache on a separate (async) queue. This leads
                                    to 2 problems: 1. It can cause some flickering on a reload, 2. It causes UIImage methods
                                    being called to leak memory. This is noticeable in NSE with a tight memory constraint.
                                    SVG images rendered to UIImage with SVGKit will leak data and make NSE crash.
     */

    SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageQueryDiskDataSync;
    SDWebImageDownloaderRequestModifier *requestModifier = [self getRequestModifierForAccount:account];

    // Since we do not have a valid avatarVersion for one-to-one conversations, we need to rely on the
    // cache-control header by the server and therefore on NSURLCache
    // Note: There seems to be an issue with NSURLCache to correctly cache URLs that contain a query parameter
    // so it's currently only suiteable for one-to-ones that don't have a correct avatarVersion anyway
    if (room.type == kNCRoomTypeOneToOne) {
        options |= SDWebImageRefreshCached;
    }

    // Make sure we get at least a 120x120 image when retrieving an SVG with SVGKit
    SDWebImageContext *context = @{
        SDWebImageContextDownloadRequestModifier : requestModifier,
        SDWebImageContextImageThumbnailPixelSize : @(CGSizeMake(120, 120))
    };
    
    return [[SDWebImageManager sharedManager] loadImageWithURL:url options:options context:context progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (error) {
            // When the request was cancelled before completing, we expect no completion handler to be called
            if (block && error.code != SDWebImageErrorCancelled) {
                block(nil, error);
            }

            return;
        }

        if (image && block) {
            block(image, nil);
        }
    }];
}

- (NSURLSessionDataTask *)setAvatarForRoom:(NCRoom *)room withImage:(UIImage *)image withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:room.accountId];
    return [self setAvatarForRoomWithToken:room.token image:image account:account withCompletionBlock:block];
}

- (NSURLSessionDataTask *)setAvatarForRoomWithToken:(NSString *)token image:(UIImage *)image account:(TalkAccount *)account withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/avatar", encodedToken];
    NSInteger avatarAPIVersion = 1;
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:avatarAPIVersion forAccount:account];

    NSData *imageData = UIImageJPEGRepresentation(image, 0.7);

    if (!imageData) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(error);
        }

        return nil;
    }

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFileData:imageData name:@"file" fileName:@"avatar.jpg" mimeType:@"image/jpeg"];
    } progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)setEmojiAvatarForRoom:(NCRoom *)room withEmoji:(NSString *)emoji andColor:(NSString *)color withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:room.accountId];
    return [self setEmojiAvatarForRoomWithToken:room.token withEmoji:emoji andColor:color account:account withCompletionBlock:block];
}

- (NSURLSessionDataTask *)setEmojiAvatarForRoomWithToken:(NSString *)token withEmoji:(NSString *)emoji andColor:(NSString *)color account:(TalkAccount *)account withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/avatar/emoji", encodedToken];
    NSInteger avatarAPIVersion = 1;
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:avatarAPIVersion forAccount:account];

    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setValue:emoji forKey:@"emoji"];

    color = [color stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (color.length > 0) {
        [parameters setValue:color forKey:@"color"];
    }

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)removeAvatarForRoom:(NCRoom *)room withCompletionBlock:(RemoveAvatarForConversationWithImageCompletionBlock)block
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:room.accountId];
    NSString *encodedToken = [room.token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/avatar", encodedToken];
    NSInteger avatarAPIVersion = 1;
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:avatarAPIVersion forAccount:account];

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error);
        }
    }];

    return task;
}

#pragma mark - User actions

- (NSURLSessionDataTask *)getUserActionsForUser:(NSString *)userId usingAccount:(TalkAccount *)account withCompletionBlock:(GetUserActionsCompletionBlock)block
{
    NSString *encodedUser = [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/hovercard/v1/%@", account.server, encodedUser];
    NSDictionary *parameters = @{@"format" : @"json"};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *actions = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(actions, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

#pragma mark - File previews

- (SDWebImageCombinedOperation *)getPreviewForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height usingAccount:(TalkAccount *)account withCompletionBlock:(GetPreviewForFileCompletionBlock)block
{
    NSString *urlString;

    if (width > 0) {
        urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=%ld&y=%ld&forceIcon=1", account.server, fileId, (long)width, (long)height];
    } else {
        urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=-1&y=%ld&a=1&forceIcon=1", account.server, fileId, (long)height];
    }

    NSURL *url = [NSURL URLWithString:urlString];

    SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageRefreshCached;
    SDWebImageDownloaderRequestModifier *requestModifier = [self getRequestModifierForAccount:account];

    return [[SDWebImageManager sharedManager] loadImageWithURL:url options:options context:@{SDWebImageContextDownloadRequestModifier : requestModifier} progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (error) {
            // When the request was cancelled before completing, we expect no completion handler to be called
            if (block && error.code != SDWebImageErrorCancelled) {
                block(nil, fileId, error);
            }

            return;
        }

        if (image && block) {
            block(image, fileId, nil);
        }
    }];
}

#pragma mark - User profile

- (NSURLSessionDataTask *)getUserProfileForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/cloud/user", account.server];
    NSDictionary *parameters = @{@"format" : @"json"};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *profile = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(profile, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getUserProfileEditableFieldsForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileEditableFieldsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/cloud/user/fields", account.server];
    NSDictionary *parameters = @{@"format" : @"json"};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *editableFields = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(editableFields, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)setUserProfileField:(NSString *)field withValue:(NSString*)value forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block
{
    NSString *encodedUserId = [account.userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/cloud/users/%@", account.server, encodedUserId];
    NSDictionary *parameters = @{@"format" : @"json",
                                 @"key" : field,
                                 @"value" : value};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        // Ignore status code for now https://github.com/nextcloud/server/pull/26679
        // [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)setUserProfileImage:(UIImage *)image forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/spreed/temp-user-avatar", account.server];
    NSData *imageData= UIImageJPEGRepresentation(image, 0.7);
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [formData appendPartWithFileData:imageData name:@"files[]" fileName:@"avatar.jpg" mimeType:@"image/jpeg"];
    } progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        if (block) {
            block(nil, 0);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)removeUserProfileImageForAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/spreed/temp-user-avatar", account.server];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error, statusCode);
        }
    }];
    
    return task;
}

- (void)saveProfileImageForAccount:(TalkAccount *)account
{
    [self getAndStoreProfileImageForAccount:account withStyle:UIUserInterfaceStyleLight];
}

- (void)getAndStoreProfileImageForAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style
{
    __block SDWebImageCombinedOperation *operation;

    // When getting our own profile image, we need to ignore any cache to always get the latest version
    operation = [self getUserAvatarForUser:account.userId usingAccount:account withStyle:style ignoreCache:YES withCompletionBlock:^(UIImage *image, NSError *error) {
        SDWebImageDownloadToken *token = operation.loaderOperation;
        if (![token isKindOfClass:[SDWebImageDownloadToken class]]) {
            return;
        }

        NSURLResponse *response = token.response;
        NSDictionary *headers = ((NSHTTPURLResponse *)response).allHeaderFields;
        
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm beginWriteTransaction];
        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
        TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
        managedAccount.hasCustomAvatar = [[headers objectForKey:@"X-NC-IsCustomAvatar"] boolValue];
        [realm commitWriteTransaction];

        NSData *pngData = UIImagePNGRepresentation(image);
        NSString *documentsPath = [[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] path];
        NSString *fileName;
        if (style == UIUserInterfaceStyleDark) {
            fileName = [NSString stringWithFormat:@"%@-%@-dark.png", account.userId, [[NSURL URLWithString:account.server] host]];
        } else {
            fileName = [NSString stringWithFormat:@"%@-%@.png", account.userId, [[NSURL URLWithString:account.server] host]];
        }
        NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
        [pngData writeToFile:filePath atomically:YES];

        ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
        if (style == UIUserInterfaceStyleLight && !managedAccount.hasCustomAvatar && serverCapabilities.versionMajor >= 25) {
            [self getAndStoreProfileImageForAccount:account withStyle:UIUserInterfaceStyleDark];
            return;
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCUserProfileImageUpdatedNotification object:self userInfo:nil];
    }];
}

- (UIImage *)userProfileImageForAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath = [[fileManager containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] path];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    NSString *fileName;
    if (style == UIUserInterfaceStyleDark && !account.hasCustomAvatar && serverCapabilities.versionMajor >= 25) {
        fileName = [NSString stringWithFormat:@"%@-%@-dark.png", account.userId, [[NSURL URLWithString:account.server] host]];
    } else {
        fileName = [NSString stringWithFormat:@"%@-%@.png", account.userId, [[NSURL URLWithString:account.server] host]];
    }
    NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
    
    // Migrate to app group directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *oldDocumentsPath = [paths objectAtIndex:0];
    NSString *oldPath = [oldDocumentsPath stringByAppendingPathComponent:fileName];
    if ([fileManager fileExistsAtPath:oldPath]) {
        NSError *error = nil;
        [fileManager moveItemAtPath:oldPath toPath:filePath error:&error];
        NSLog(@"Migrating profile picture. Error: %@", error);
    }
    
    return [UIImage imageWithContentsOfFile:filePath];
}

- (void)removeProfileImageForAccount:(TalkAccount *)account
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath = [[fileManager containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] path];
    NSString *fileName = [NSString stringWithFormat:@"%@-%@.png", account.userId, [[NSURL URLWithString:account.server] host]];
    NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    fileName = [NSString stringWithFormat:@"%@-%@-dark.png", account.userId, [[NSURL URLWithString:account.server] host]];
    filePath = [documentsPath stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    // Legacy
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *oldDocumentsPath = [paths objectAtIndex:0];
    NSString *oldPath = [oldDocumentsPath stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:oldPath error:nil];
}

#pragma mark - User Status

- (NSURLSessionDataTask *)getUserStatusForAccount:(TalkAccount *)account withCompletionBlock:(GetUserStatusCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/user_status/api/v1/user_status", account.server];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *userStatus = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(userStatus, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)setUserStatus:(NSString *)status forAccount:(TalkAccount *)account withCompletionBlock:(SetUserStatusCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/user_status/api/v1/user_status/status", account.server];
    NSDictionary *parameters = @{@"statusType" : status};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(error);
        }
    }];
    
    return task;
}

#pragma mark - Error handling

- (NSInteger)getResponseStatusCode:(NSURLResponse *)response
{
    NSInteger statusCode = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        statusCode = httpResponse.statusCode;
    }
    return statusCode;
}

- (NSDictionary *)getFailureResponseObjectFromError:(NSError *)error
{
    NSDictionary *responseDict = @{};
    NSString* errorResponse = [[NSString alloc] initWithData:(NSData *)error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] encoding:NSUTF8StringEncoding];

    if (errorResponse.length == 0) {
        return nil;
    }

    NSData *data = [errorResponse dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        NSError* error;
        NSDictionary* jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&error];
        if (jsonData) {
            responseDict = jsonData;
        } else {
            NSLog(@"Error retrieving failure response object JSON data: %@", error);
        }
    }

    return responseDict;
}

- (void)checkResponseStatusCode:(NSInteger)statusCode forAccount:(TalkAccount *)account
{
    if (statusCode == 401) {
        // App token has been revoked
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:account.accountId forKey:@"accountId"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCTokenRevokedResponseReceivedNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else if (statusCode == 426) {
        // Upgrade required
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:account.accountId forKey:@"accountId"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCUpgradeRequiredResponseReceivedNotification
                                                            object:self
                                                          userInfo:userInfo];
    } else if (statusCode == 503) {
        // Server is in maintenance mode
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:account.accountId forKey:@"accountId"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCServerMaintenanceModeNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
}

#pragma mark - Header handling

- (void)checkResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account
{
    NSString *modifiedSince = [headers objectForKey:@"X-Nextcloud-Talk-Modified-Before"];
    NSString *configurationHash = [headers objectForKey:@"X-Nextcloud-Talk-Hash"];
    
    if (modifiedSince.length > 0) {
        [[NCDatabaseManager sharedInstance] updateLastModifiedSinceForAccountId:account.accountId with:modifiedSince];
    }

    if (!configurationHash) {
        return;
    }
    
    if (![configurationHash isEqualToString:account.lastReceivedConfigurationHash]) {
        if (account.lastReceivedConfigurationHash) {
            // We previously stored a configuration hash which now changed -> Update settings and capabilities
            NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
            [userInfo setObject:account.accountId forKey:@"accountId"];
            [userInfo setObject:configurationHash forKey:@"configurationHash"];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:NCTalkConfigurationHashChangedNotification
                                                                object:self
                                                              userInfo:userInfo];
        } else {
            [[NCDatabaseManager sharedInstance] updateTalkConfigurationHashForAccountId:account.accountId withHash:configurationHash];
        }
    }
}

- (void)checkProxyResponseHeaders:(NSString * _Nullable)proxyHash forAccount:(TalkAccount *)account forRoom:(NSString *)token
{
    if (!proxyHash) {
        return;
    }

    NSPredicate *query = [NSPredicate predicateWithFormat:@"token = %@ AND accountId = %@", token, account.accountId];
    NCRoom *managedRoom = [NCRoom objectsWithPredicate:query].firstObject;

    if (!managedRoom) {
        // The room is not known to us locally, don't try to fetch room capabilities
        return;
    }

    FederatedCapabilities *federatedCapabilities = [[NCDatabaseManager sharedInstance] federatedCapabilitiesForAccountId:managedRoom.accountId remoteServer:managedRoom.remoteServer roomToken:managedRoom.token];

    if ([proxyHash isEqualToString:managedRoom.lastReceivedProxyHash] && federatedCapabilities != nil) {
        // The proxy hash is equal to our last known proxy hash and we are also able to retrieve capabilities locally -> skip fetching capabilities
        return;
    }

    [self getRoomCapabilitiesFor:account.accountId token:token completionBlock:^(NSDictionary<NSString *,id> * _Nullable capabilities, NSString * _Nullable proxyHash) {
        if (capabilities && proxyHash) {
            [[NCDatabaseManager sharedInstance] setFederatedCapabilities:capabilities forAccountId:account.accountId remoteServer:managedRoom.remoteServer roomToken:token withProxyHash:proxyHash];
        }
    }];
}

#pragma mark - NKCommon Delegate

- (void)authenticationChallenge:(NSURLSession *)session didReceive:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    // The pinnning check
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}


@end
