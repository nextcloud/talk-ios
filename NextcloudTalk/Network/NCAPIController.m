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

- (NSInteger)conversationAPIVersionForAccount:(TalkAccount *)account
{
    NSInteger conversationAPIVersion = APIv2;
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadStatus forAccountId:account.accountId]) {
        conversationAPIVersion = APIv3;
    }
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityConversationV4 forAccountId:account.accountId]) {
        conversationAPIVersion = APIv4;
    }
    
    return conversationAPIVersion;
}

- (NSInteger)callAPIVersionForAccount:(TalkAccount *)account
{
    return [self conversationAPIVersionForAccount:account];
}

- (NSInteger)chatAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)reactionsAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)pollsAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)breakoutRoomsAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)federationAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)banAPIVersionForAccount:(TalkAccount *)account
{
    return APIv1;
}

- (NSInteger)signalingAPIVersionForAccount:(TalkAccount *)account
{
    NSInteger signalingAPIVersion = APIv1;
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySIPSupport forAccountId:account.accountId]) {
        signalingAPIVersion = APIv2;
    }
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySignalingV3 forAccountId:account.accountId]) {
        signalingAPIVersion = APIv3;
    }
    
    return signalingAPIVersion;
}

- (NSString *)filesPathForAccount:(TalkAccount *)account
{
    return [NSString stringWithFormat:@"%@/files/%@", kDavEndpoint, account.userId];
}

- (NSString *)getRequestURLForConversationEndpoint:(NSString *)endpoint forAccount:(TalkAccount *)account
{
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    return [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
}

- (NSString *)getRequestURLForEndpoint:(NSString *)endpoint withAPIVersion:(NSInteger)apiVersion forAccount:(TalkAccount *)account
{
    return [NSString stringWithFormat:@"%@%@%@%ld/%@", account.server, kNCOCSAPIVersion, kNCSpreedAPIVersionBase, (long)apiVersion, endpoint];
}

#pragma mark - Chat Controller

- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token
                                  fromLastMessageId:(NSInteger)messageId
                                           inThread:(NSInteger)threadId
                                            history:(BOOL)history
                                 includeLastMessage:(BOOL)include
                                            timeout:(BOOL)timeout
                                              limit:(NSInteger)limit
                              lastCommonReadMessage:(NSInteger)lastCommonReadMessage
                                      setReadMarker:(BOOL)setReadMarker
                            markNotificationsAsRead:(BOOL)markNotificationsAsRead
                                         forAccount:(TalkAccount *)account
                                withCompletionBlock:(GetChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];

    if (limit <= 0) {
        // Ensure we don't try to request an invalid number of messages (although there's a limit server side)
        limit = kReceivedChatMessagesLimit;
    }

    NSDictionary *parameters = @{@"lookIntoFuture" : history ? @(0) : @(1),
                                 @"limit" : @(MIN(kReceivedChatMessagesLimit, limit)),
                                 @"timeout" : timeout ? @(30) : @(0),
                                 @"lastKnownMessageId" : @(messageId),
                                 @"lastCommonReadId" : @(lastCommonReadMessage),
                                 @"setReadMarker" : setReadMarker ? @(1) : @(0),
                                 @"includeLastKnown" : include ? @(1) : @(0),
                                 @"markNotificationsAsRead" : markNotificationsAsRead ? @(1) : @(0),
                                 @"threadId" : @(threadId)};

    NCAPISessionManager *apiSessionManager;

    if (timeout) {
        apiSessionManager = [_longPollingApiSessionManagers objectForKey:account.accountId];
    } else {
        apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    }

    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseMessages = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        // Get X-Chat-Last-Given and X-Chat-Last-Common-Read headers
        NSHTTPURLResponse *response = ((NSHTTPURLResponse *)[task response]);
        NSDictionary *headers = [response allHeaderFields];
        NSString *lastKnowMessageHeader = [headers objectForKey:@"X-Chat-Last-Given"];
        NSInteger lastKnownMessage = -1;
        if (lastKnowMessageHeader) {
            lastKnownMessage = [lastKnowMessageHeader integerValue];
        }
        NSString *lastCommonReadMessageHeader = [headers objectForKey:@"X-Chat-Last-Common-Read"];
        NSInteger lastCommonReadMessage = -1;
        if (lastCommonReadMessageHeader) {
            lastCommonReadMessage = [lastCommonReadMessageHeader integerValue];
        }
        
        if (block) {
            block(responseMessages, lastKnownMessage, lastCommonReadMessage, nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, -1, -1, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token threadTitle:(NSString *)threadTitle replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:message forKey:@"message"];
    if (replyTo > -1) {
        [parameters setObject:@(replyTo) forKey:@"replyTo"];
    }
    if (referenceId) {
        [parameters setObject:referenceId forKey:@"referenceId"];
    }
    if (silently) {
        [parameters setObject:@(silently) forKey:@"silent"];
    }
    if (threadTitle) {
        [parameters setObject:threadTitle forKey:@"threadTitle"];
    }

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    // Workaround: When sendChatMessage is called from Share Extension session managers are not initialized.
    if (!apiSessionManager) {
        [self initSessionManagers];
        apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    }

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

- (NSURLSessionDataTask *)deleteChatMessageInRoom:(NSString *)token withMessageId:(NSInteger)messageId forAccount:(TalkAccount *)account withCompletionBlock:(DeleteChatMessageCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/%ld", encodedToken, (long)messageId];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *messageDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(messageDict, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)editChatMessageInRoom:(NSString *)token withMessageId:(NSInteger)messageId withMessage:(NSString *)message forAccount:(TalkAccount *)account withCompletionBlock:(EditChatMessageCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/%ld", encodedToken, (long)messageId];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:message forKey:@"message"];

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];

    NSURLSessionDataTask *task = [apiSessionManager PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *messageDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(messageDict, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)clearChatHistoryInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ClearChatHistoryCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *messageDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(messageDict, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)shareRichObject:(NSDictionary *)richObject inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/share", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:richObject progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)setChatReadMarker:(NSInteger)lastReadMessage inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/read", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSDictionary *parameters = nil;
    if (lastReadMessage > 0) {
        parameters = @{@"lastReadMessage" : @(lastReadMessage)};
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

- (NSURLSessionDataTask *)markChatAsUnreadInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/read", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
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

- (NSURLSessionDataTask *)getSharedItemsOverviewInRoom:(NSString *)token withLimit:(NSInteger)limit forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsOverviewCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/share/overview", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    if (limit > -1) {
        [parameters setObject:@(limit) forKey:@"limit"];
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseSharedItems = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        // Create dictionary [String: [NCChatMessage]]
        NSMutableDictionary *sharedItems = [NSMutableDictionary new];
        for (NSString *key in responseSharedItems.allKeys) {
            NSArray *responseMessages = [responseSharedItems objectForKey:key];
            NSMutableArray *messages = [NSMutableArray new];
            for (NSDictionary *messageDict in responseMessages) {
                NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict];

                if (message) {
                    [messages addObject:message];
                }
            }
            [sharedItems setObject:messages forKey:key];
        }
        
        if (block) {
            block(sharedItems, nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getSharedItemsOfType:(NSString *)objectType fromLastMessageId:(NSInteger)messageId withLimit:(NSInteger)limit inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/share", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:objectType forKey:@"objectType"];
    if (messageId > -1) {
        [parameters setObject:@(messageId) forKey:@"lastKnownMessageId"];
    }
    if (limit > -1) {
        [parameters setObject:@(limit) forKey:@"limit"];
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        id responseData = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        // Create array [NCChatMessage]
        NSMutableArray *sharedItems = [NSMutableArray new];
        if ([responseData isKindOfClass:[NSDictionary class]]) {
            NSDictionary *responseSharedItems = responseData;
            for (NSDictionary *messageDict in responseSharedItems.allValues) {
                NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict];
                [sharedItems addObject:message];
            }
        }
        // Get X-Chat-Last-Given
        NSHTTPURLResponse *response = ((NSHTTPURLResponse *)[task response]);
        NSDictionary *headers = [response allHeaderFields];
        NSString *lastKnowMessageHeader = [headers objectForKey:@"X-Chat-Last-Given"];
        NSInteger lastKnownMessage = -1;
        if (lastKnowMessageHeader) {
            lastKnownMessage = [lastKnowMessageHeader integerValue];
        }
        
        if (block) {
            block(sharedItems, lastKnownMessage, nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, -1, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getMessageContextInRoom:(NSString *)token forMessageId:(NSInteger)messageId inThread:(NSInteger)threadId withLimit:(NSInteger)limit forAccount:(TalkAccount *)account withCompletionBlock:(GetMessageContextInRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/%ld/context", encodedToken, (long)messageId];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];

    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    if (limit && limit > 0) {
        // Limit is optional server-side and defaults to 50, maximum is 100
        [parameters setObject:@(limit) forKey:@"limit"];
    }
    if (threadId && threadId > 0) {
        [parameters setObject:@(threadId) forKey:@"threadId"];
    }

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];

    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseMessages = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];

        if (block) {
            block(responseMessages, nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];

    return task;
}

#pragma mark - Polls Controller

- (NSURLSessionDataTask *)createPollWithQuestion:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token asDraft:(BOOL)asDraft forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@", encodedToken];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"question" : question,
                                 @"options" : options,
                                 @"resultMode" : @(resultMode),
                                 @"draft" : @(asDraft),
                                 @"maxVotes" : @(maxVotes)
    };
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *pollDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCPoll *poll = [NCPoll initWithPollDictionary:pollDict];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(poll, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getPollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@/%ld", encodedToken, (long)pollId];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *pollDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCPoll *poll = [NCPoll initWithPollDictionary:pollDict];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(poll, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)editPollDraftWithId:(NSInteger)draftId question:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@/draft/%ld", encodedToken, (long)draftId];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"question" : question,
                                 @"options" : options,
                                 @"resultMode" : @(resultMode),
                                 @"maxVotes" : @(maxVotes)
    };
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *pollDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCPoll *poll = [NCPoll initWithPollDictionary:pollDict];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(poll, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)getPollDraftsInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollDraftsCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@/drafts", encodedToken];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *pollDrafts = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(pollDrafts, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)voteOnPollWithId:(NSInteger)pollId inRoom:(NSString *)token withOptions:(NSArray *)options forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@/%ld", encodedToken, (long)pollId];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"optionIds" : options};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *pollDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCPoll *poll = [NCPoll initWithPollDictionary:pollDict];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(poll, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)closePollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@/%ld", encodedToken, (long)pollId];
    NSInteger pollsAPIVersion = [self pollsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:pollsAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *pollDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCPoll *poll = [NCPoll initWithPollDictionary:pollDict];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(poll, nil, httpResponse.statusCode);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error, statusCode);
        }
    }];
    
    return task;
}

#pragma mark - Files

- (void)readFolderForAccount:(TalkAccount *)account atPath:(NSString *)path depth:(NSString *)depth withCompletionBlock:(ReadFolderCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    NSString *serverUrlString = [NSString stringWithFormat:@"%@%@/%@", account.server, [self filesPathForAccount:account], path ? path : @""];

    // We don't need all properties, so we limit the request to the needed ones to reduce size and processing time
    NSString *body = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
            <d:propfind xmlns:d=\"DAV:\" xmlns:oc=\"http://owncloud.org/ns\" xmlns:nc=\"http://nextcloud.org/ns\">\
                <d:prop>\
                    <d:getlastmodified />\
                    <d:getcontenttype />\
                    <d:resourcetype />\
                    <fileid xmlns=\"http://owncloud.org/ns\"/>\
                    <is-encrypted xmlns=\"http://nextcloud.org/ns\"/>\
                    <has-preview xmlns=\"http://nextcloud.org/ns\"/>\
                </d:prop>\
            </d:propfind>";

    NKRequestOptions *options = [[NKRequestOptions alloc] initWithEndpoint:nil customHeader:nil customUserAgent:nil contentType:nil e2eToken:nil timeout:60 queue:dispatch_get_main_queue()];
    [[NextcloudKit shared] readFileOrFolderWithServerUrlFileName:serverUrlString depth:depth showHiddenFiles:NO includeHiddenFiles:@[] requestBody:[body dataUsingEncoding:NSUTF8StringEncoding] options:options completion:^(NSString *account, NSArray<NKFile *> *files, NSData *responseDates, NKError *error) {
        if (error.errorCode == 0 && block) {
            block(files, nil);
        } else if (block) {
            NSError *nsError = [NSError errorWithDomain:NSURLErrorDomain code:error.errorCode userInfo:nil];
            block(nil, nsError);
        }
    }];
}

- (void)shareFileOrFolderForAccount:(TalkAccount *)account atPath:(NSString *)path toRoom:(NSString *)token talkMetaData:(NSDictionary *)talkMetaData referenceId:(NSString *)referenceId withCompletionBlock:(ShareFileOrFolderCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/files_sharing/api/v1/shares", account.server];
    
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:path forKey:@"path"];
    [parameters setObject:@(10) forKey:@"shareType"];
    [parameters setObject:token forKey:@"shareWith"];
    if (referenceId) {
        [parameters setObject:referenceId forKey:@"referenceId"];
    }

    if (talkMetaData) {
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:talkMetaData
                                                           options:0
                                                             error:&error];
        if (error) {
            NSLog(@"Error serializing JSON: %@", error);
        } else {
            [parameters setObject:[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] forKey:@"talkMetaData"];
        }
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    // Workaround: When shareFileOrFolderForAccount is called from Share Extension session managers are not initialized.
    if (!apiSessionManager) {
        [self initSessionManagers];
        apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    }
    [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
        // Do not return error when re-sharing a file or folder.
        if (httpResponse.statusCode == 403 && block) {
            block(nil);
        } else if (block) {
            block(error);
        }
    }];
}

- (void)uniqueNameForFileUploadWithName:(NSString *)fileName originalName:(BOOL)isOriginalName forAccount:(TalkAccount *)account withCompletionBlock:(GetFileUniqueNameCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    
    NSString *fileServerPath = [self serverFilePathForFileName:fileName andAccountId:account.accountId];
    NSString *fileServerURL = [self serverFileURLForFilePath:fileServerPath andAccountId:account.accountId];

    NKRequestOptions *options = [[NKRequestOptions alloc] initWithEndpoint:nil customHeader:nil customUserAgent:nil contentType:nil e2eToken:nil timeout:60 queue:dispatch_get_main_queue()];
    [[NextcloudKit shared] readFileOrFolderWithServerUrlFileName:fileServerURL depth:@"0" showHiddenFiles:NO includeHiddenFiles:@[] requestBody:nil options:options completion:^(NSString *accountId, NSArray<NKFile *> *files, NSData *data, NKError *error) {
        // File already exists
        if (error.errorCode == 0 && files.count == 1) {
            NSString *alternativeName = [self alternativeNameForFileName:fileName original:isOriginalName];
            [self uniqueNameForFileUploadWithName:alternativeName originalName:NO forAccount:account withCompletionBlock:block];
        // File does not exist
        } else if (error.errorCode == 404) {
            if (block) {
                block(fileServerURL, fileServerPath, 0, nil);
            }
        } else {
            NSLog(@"Error checking file name: %@", error.errorDescription);
            if (block) {
                block(nil, nil, error.errorCode, error.errorDescription);
            }
        }
    }];
}

- (void)checkOrCreateAttachmentFolderForAccount:(TalkAccount *)account withCompletionBlock:(CheckAttachmentFolderCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    
    NSString *attachmentFolderServerURL = [self attachmentFolderServerURLForAccountId:account.accountId];
    NKRequestOptions *options = [[NKRequestOptions alloc] initWithEndpoint:nil customHeader:nil customUserAgent:nil contentType:nil e2eToken:nil timeout:60 queue:dispatch_get_main_queue()];

    [[NextcloudKit shared] readFileOrFolderWithServerUrlFileName:attachmentFolderServerURL depth:@"0" showHiddenFiles:NO includeHiddenFiles:@[] requestBody:nil options:options completion:^(NSString *accountId, NSArray<NKFile *> *files, NSData *data, NKError *error) {
        // Attachment folder do not exist
        if (error.errorCode == 404) {
            [[NextcloudKit shared] createFolderWithServerUrlFileName:attachmentFolderServerURL options:options completion:^(NSString *accountId, NSString *ocId, NSDate *data, NKError *error) {
                if (block) {
                    block(error.errorCode == 0, error.errorCode);
                }
            }];
        } else {
            NSLog(@"Error checking attachment folder: %@", error.errorDescription);
            if (block) {
                block(NO, error.errorCode);
            }
        }
    }];
}

- (NSString *)serverFilePathForFileName:(NSString *)fileName andAccountId:(NSString *)accountId;
{
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:accountId];
    NSString *attachmentsFolder = serverCapabilities.attachmentsFolder ? serverCapabilities.attachmentsFolder : @"";
    return [NSString stringWithFormat:@"%@/%@", attachmentsFolder, fileName];
}

- (NSString *)attachmentFolderServerURLForAccountId:(NSString *)accountId;
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:accountId];
    NSString *attachmentsFolder = serverCapabilities.attachmentsFolder ? serverCapabilities.attachmentsFolder : @"";
    return [NSString stringWithFormat:@"%@%@%@", account.server, [self filesPathForAccount:account], attachmentsFolder];
}

- (NSString *)serverFileURLForFilePath:(NSString *)filePath andAccountId:(NSString *)accountId;
{
    TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:accountId];
    return [NSString stringWithFormat:@"%@%@%@", account.server, [self filesPathForAccount:account], filePath];
}

- (NSString *)alternativeNameForFileName:(NSString *)fileName original:(BOOL)isOriginal
{
    NSString *extension = [fileName pathExtension];
    NSString *nameWithoutExtension = [fileName stringByDeletingPathExtension];
    NSString *alternativeName = nameWithoutExtension;
    NSString *newSuffix = @" (1)";
    
    if (!isOriginal) {
        // Check if the name ends with ` (n)`
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@" \\((\\d+)\\)$" options:NSRegularExpressionCaseInsensitive error:&error];
        NSTextCheckingResult *match = [regex firstMatchInString:nameWithoutExtension options:0 range:NSMakeRange(0, nameWithoutExtension.length)];
        if ([match numberOfRanges] > 1) {
            NSRange suffixRange = [match rangeAtIndex: 0];
            NSInteger suffixNumber = [[nameWithoutExtension substringWithRange:[match rangeAtIndex: 1]] intValue];
            newSuffix = [NSString stringWithFormat:@" (%ld)", suffixNumber + 1];
            alternativeName = [nameWithoutExtension stringByReplacingCharactersInRange:suffixRange withString:@""];
        }
    }
    
    alternativeName = [alternativeName stringByAppendingString:newSuffix];
    alternativeName = [alternativeName stringByAppendingPathExtension:extension];
    
    return alternativeName;
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

#pragma mark - App Store info

- (NSURLSessionDataTask *)getAppStoreAppIdWithCompletionBlock:(GetAppIdCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"http://itunes.apple.com/lookup?bundleId=%@", bundleIdentifier];

    NSURLSessionDataTask *task = [_defaultAPISessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *appId = nil;
        NSArray *results = [responseObject objectForKey:@"results"];
        if (results.count > 0) {
            NSDictionary *appInfo = [results objectAtIndex:0];
            appId = [[appInfo objectForKey:@"trackId"] stringValue];
        }
        if (block) {
            block(appId, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];

    return task;
}

#pragma mark - Remote Wipe

- (NSURLSessionDataTask *)checkWipeStatusForAccount:(TalkAccount *)account withCompletionBlock:(GetWipeStatusCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/index.php/core/wipe/check", account.server];

    NSString *token = [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId];
    if (!token) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(NO, error);
        }
        return nil;
    }

    NSDictionary *parameters = @{
        @"token" : token
    };

    NSURLSessionDataTask *task = [_defaultAPISessionManager POST:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        BOOL wipe = [responseObject objectForKey:@"wipe"];
        if (block) {
            block(wipe, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(NO, error);
        }
    }];

    return task;
}

- (NSURLSessionDataTask *)confirmWipeForAccount:(TalkAccount *)account withCompletionBlock:(ConfirmWipeCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/index.php/core/wipe/success", account.server];

    NSString *token = [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId];
    if (!token) {
        if (block) {
            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
            block(error);
        }
        return nil;
    }

    NSDictionary *parameters = @{
        @"token" : token
    };

    NSURLSessionDataTask *task = [_defaultAPISessionManager POST:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];

    return task;
}

#pragma mark - Push Notifications

- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account withPublicKey:(NSData *)publicKey toNextcloudServerWithCompletionBlock:(SubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", account.server];
    NSString *devicePublicKey = [[NSString alloc] initWithData:publicKey encoding:NSUTF8StringEncoding];

    NSDictionary *parameters = @{@"pushTokenHash" : [[NCKeyChainController sharedInstance] pushTokenSHA512],
                                 @"devicePublicKey" : devicePublicKey,
                                 @"proxyServer" : pushNotificationServer
                                 };
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(responseDict, nil);
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

- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromNextcloudServerWithCompletionBlock:(UnsubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", account.server];
    
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

- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account toPushServerWithCompletionBlock:(SubscribeToPushProxyCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", pushNotificationServer];
    NSDictionary *parameters = @{@"pushToken" : [[NCKeyChainController sharedInstance] combinedPushToken],
                                 @"deviceIdentifier" : account.deviceIdentifier,
                                 @"deviceIdentifierSignature" : account.deviceSignature,
                                 @"userPublicKey" : account.userPublicKey
                                 };

    NSURLSessionDataTask *task = [[NCPushProxySessionManager shared] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromPushServerWithCompletionBlock:(UnsubscribeToPushProxyCompletionBlock)block
{    
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", pushNotificationServer];
    NSDictionary *parameters = @{@"deviceIdentifier" : account.deviceIdentifier,
                                 @"deviceIdentifierSignature" : account.deviceSignature,
                                 @"userPublicKey" : account.userPublicKey
                                 };

    NSURLSessionDataTask *task = [[NCPushProxySessionManager shared] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
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
- (NSDictionary *)getResponseHeaders:(NSURLResponse *)response
{
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        return [httpResponse allHeaderFields];
    }
    
    return nil;
}

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

- (void)checkProxyResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account forRoom:(NSString *)token
{
    NSString *proxyHash = [headers objectForKey:@"X-Nextcloud-Talk-Proxy-Hash"];

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
