/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
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

#import "NCAPIController.h"

@import NCCommunication;

#import "CCCertificate.h"
#import "NCAPISessionManager.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCImageSessionManager.h"
#import "NCPushProxySessionManager.h"
#import "NCKeyChainController.h"
#import "NotificationCenterNotifications.h"

NSInteger const APIv1                       = 1;
NSInteger const APIv2                       = 2;
NSInteger const APIv3                       = 3;
NSInteger const APIv4                       = 4;

NSString * const kDavEndpoint               = @"/remote.php/dav";
NSString * const kNCOCSAPIVersion           = @"/ocs/v2.php";
NSString * const kNCSpreedAPIVersionBase    = @"/apps/spreed/api/v";

NSInteger const kReceivedChatMessagesLimit = 100;

@interface NCAPIController () <NSURLSessionTaskDelegate, NSURLSessionDelegate, NCCommunicationCommonDelegate>

@property (nonatomic, strong) NCAPISessionManager *defaultAPISessionManager;

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
        [self initSessionManagers];
        [self initImageDownloaders];
    }
    
    return self;
}

- (void)initSessionManagers
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPCookieStorage = nil;
    _defaultAPISessionManager = [[NCAPISessionManager alloc] initWithSessionConfiguration:configuration];
    
    _apiSessionManagers = [NSMutableDictionary new];
    
    for (TalkAccount *talkAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:talkAccount];
        [self createAPISessionManagerForAccount:account];
    }
}

- (void)createAPISessionManagerForAccount:(TalkAccount *)account
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:account.accountId];
    configuration.HTTPCookieStorage = cookieStorage;
    NCAPISessionManager *apiSessionManager = [[NCAPISessionManager alloc] initWithSessionConfiguration:configuration];
    [apiSessionManager.requestSerializer setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    [_apiSessionManagers setObject:apiSessionManager forKey:account.accountId];
}

- (void)setupNCCommunicationForAccount:(TalkAccount *)account
{
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    NSString *userToken = [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId];
    NSString *userAgent = [NSString stringWithFormat:@"Mozilla/5.0 (iOS) Nextcloud-Talk v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    [[NCCommunicationCommon shared] setupWithAccount:account.accountId user:account.user userId:account.userId password:userToken urlBase:account.server userAgent:userAgent webDav:nil nextcloudVersion:serverCapabilities.versionMajor delegate:self];
}

- (void)initImageDownloaders
{
    _imageDownloader = [[AFImageDownloader alloc]
                        initWithSessionManager:[NCImageSessionManager sharedInstance]
                        downloadPrioritization:AFImageDownloadPrioritizationFIFO
                        maximumActiveDownloads:4
                                    imageCache:[[AFAutoPurgingImageCache alloc] init]];
    
    _imageDownloaderNoCache = [[AFImageDownloader alloc]
                               initWithSessionManager:[NCImageSessionManager sharedInstance]
                               downloadPrioritization:AFImageDownloadPrioritizationFIFO
                               maximumActiveDownloads:4
                                            imageCache:nil];
}

- (NSString *)authHeaderForAccount:(TalkAccount *)account
{
    NSString *userTokenString = [NSString stringWithFormat:@"%@:%@", account.user, [[NCKeyChainController sharedInstance] tokenForAccountId:account.accountId]];
    NSData *data = [userTokenString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Encoded = [data base64EncodedStringWithOptions:0];
    
    return [[NSString alloc]initWithFormat:@"Basic %@",base64Encoded];
}

- (NSInteger)conversationAPIVersionForAccount:(TalkAccount *)account
{
    NSInteger conversationAPIVersion = APIv1;
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

- (NSString *)getRequestURLForEndpoint:(NSString *)endpoint withAPIVersion:(NSInteger)apiVersion forAccount:(TalkAccount *)account
{
    return [NSString stringWithFormat:@"%@%@%@%ld/%@", account.server, kNCOCSAPIVersion, kNCSpreedAPIVersionBase, (long)apiVersion, endpoint];
}

#pragma mark - Contacts Controller

- (NSURLSessionDataTask *)searchContactsForAccount:(TalkAccount *)account withPhoneNumbers:(NSDictionary *)phoneNumbers andCompletionBlock:(GetContactsWithPhoneNumbersCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/cloud/users/search/by-phone", account.server];
    NSString *location = [[NSLocale currentLocale] countryCode];
    NSDictionary *parameters = @{@"location" : location,
                                 @"search" : phoneNumbers};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseContacts = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(responseContacts, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        // NSInteger statusCode = [self getResponseStatusCode:task.response];
        // Ignore status code for now https://github.com/nextcloud/server/pull/26679
        // [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getContactsForAccount:(TalkAccount *)account forRoom:(NSString *)room groupRoom:(BOOL)groupRoom withSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block
{
    NSMutableArray *shareTypes = [[NSMutableArray alloc] initWithObjects:@(NCShareTypeUser), nil];
    if (groupRoom && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityInviteGroupsAndMails]) {
        [shareTypes addObject:@(NCShareTypeGroup)];
        [shareTypes addObject:@(NCShareTypeEmail)];
        if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityCirclesSupport]) {
            [shareTypes addObject:@(NCShareTypeCircle)];
        }
    }
    
    NSString *URLString = [NSString stringWithFormat:@"%@%@/core/autocomplete/get", account.server, kNCOCSAPIVersion];
    NSDictionary *parameters = @{@"format" : @"json",
                                 @"search" : search ? search : @"",
                                 @"limit" : @"50",
                                 @"itemType" : @"call",
                                 @"itemId" : room ? room : @"new",
                                 @"shareTypes" : shareTypes
                                 };
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseContacts = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *users = [[NSMutableArray alloc] initWithCapacity:responseContacts.count];
        for (NSDictionary *user in responseContacts) {
            NCUser *ncUser = [NCUser userWithDictionary:user];
            TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
            if (ncUser && !([ncUser.userId isEqualToString:activeAccount.userId] && [ncUser.source isEqualToString:kParticipantTypeUser])) {
                [users addObject:ncUser];
            }
        }
        NSMutableDictionary *indexedContacts = [NCUser indexedUsersFromUsersArray:users];
        NSArray *indexes = [[indexedContacts allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        if (block) {
            block(indexes, indexedContacts, users, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(nil, nil, nil, error);
        }
    }];
    
    return task;
}

#pragma mark - Rooms Controller

- (NSURLSessionDataTask *)getRoomsForAccount:(TalkAccount *)account updateStatus:(BOOL)updateStatus withCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *endpoint = @"room";
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"noStatusUpdate" : @(!updateStatus)};
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    if (serverCapabilities.userStatus) {
        URLString = [URLString stringByAppendingString:@"?includeStatus=true"];
    }
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSHTTPURLResponse *response = ((NSHTTPURLResponse *)[task response]);
        NSDictionary *headers = [self getResponseHeaders:response];
        
        [self checkResponseHeaders:headers forAccount:account];
        
        if (block) {
            block(responseRooms, nil, 0);
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

- (NSURLSessionDataTask *)getRoomForAccount:(TalkAccount *)account withToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *roomDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSHTTPURLResponse *response = ((NSHTTPURLResponse *)[task response]);
        NSDictionary *headers = [self getResponseHeaders:response];
        
        [self checkResponseHeaders:headers forAccount:account];
        
        if (block) {
            block(roomDict, nil);
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

- (NSURLSessionDataTask *)getListableRoomsForAccount:(TalkAccount *)account withSearchTerm:(NSString *)searchTerm andCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *endpoint = @"listed-room";
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = nil;
    if (searchTerm.length > 0) {
        parameters = @{@"searchTerm" : searchTerm};
    }
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *parsedRooms = [NSMutableArray new];
        for (NSDictionary *roomDict in responseRooms) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:account.accountId];
            [parsedRooms addObject:room];
        }
        if (block) {
            block(parsedRooms, nil, 0);
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


- (NSURLSessionDataTask *)createRoomForAccount:(TalkAccount *)account with:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block
{
    NSString *endpoint = @"room";
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    
    [parameters setObject:@(type) forKey:@"roomType"];
    
    if (invite) {
        [parameters setObject:invite forKey:@"invite"];
    }
    
    if (roomName) {
        [parameters setObject:roomName forKey:@"roomName"];
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *token = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"token"];
        if (block) {
            block(token, nil);
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

- (NSURLSessionDataTask *)renameRoom:(NSString *)token forAccount:(TalkAccount *)account withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"roomName" : newName};
    
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

- (NSURLSessionDataTask *)makeRoomPublic:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MakeRoomPublicCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/public", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)makeRoomPrivate:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MakeRoomPrivateCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/public", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
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

- (NSURLSessionDataTask *)deleteRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(DeleteRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
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

- (NSURLSessionDataTask *)setPassword:(NSString *)password toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetPasswordCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/password", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"password" : password};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            if (statusCode == 400) {
                NSData *errorData = (NSData *)error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:errorData
                                                                         options:0
                                                                           error:&error];
                
                // message is already translated server-side
                NSString *errorDescription = [[[jsonData objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"message"];
                block(error, errorDescription);
            } else {
                block(error, nil);
            }
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)joinRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(JoinRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants/active", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *sessionId = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"sessionId"];
        if (block) {
            block(sessionId, nil, 0);
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

- (NSURLSessionDataTask *)exitRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ExitRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants/active", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
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

- (NSURLSessionDataTask *)addRoomToFavorites:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(FavoriteRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/favorite", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeRoomFromFavorites:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(FavoriteRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/favorite", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
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

- (NSURLSessionDataTask *)setNotificationLevel:(NCRoomNotificationLevel)level forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(NotificationLevelCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/notify", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"level" : @(level)};
    
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

- (NSURLSessionDataTask *)setCallNotificationEnabled:(BOOL)enabled forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(NotificationLevelCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/notify-calls", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"level" : @(enabled)};
    
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

- (NSURLSessionDataTask *)setReadOnlyState:(NCRoomReadOnlyState)state forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ReadOnlyCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/read-only", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"state" : @(state)};
    
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

- (NSURLSessionDataTask *)setLobbyState:(NCRoomLobbyState)state withTimer:(NSInteger)timer forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetLobbyStateCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/webinary/lobby", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    if (conversationAPIVersion >= APIv4) {
        endpoint = [NSString stringWithFormat:@"room/%@/webinar/lobby", encodedToken];
    }
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:@(state) forKey:@"state"];
    if (timer > 0) {
        [parameters setObject:@(timer) forKey:@"timer"];
    }
    
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

- (NSURLSessionDataTask *)setSIPState:(NCRoomSIPState)state forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetSIPStateCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/webinar/sip", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"state" : @(state)};
    
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

- (NSURLSessionDataTask *)setListableScope:(NCRoomListableScope)scope forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ListableCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/listable", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"scope" : @(scope)};
    
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

- (NSURLSessionDataTask *)setMessageExpiration:(NCMessageExpiration)messageExpiration forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageExpirationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/message-expiration", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"seconds" : @(messageExpiration)};
    
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

#pragma mark - Participants Controller

- (NSURLSessionDataTask *)getParticipantsFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetParticipantsFromRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    if (serverCapabilities.userStatus) {
        URLString = [URLString stringByAppendingString:@"?includeStatus=true"];
    }
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseParticipants = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *participants = [[NSMutableArray alloc] initWithCapacity:responseParticipants.count];
        for (NSDictionary *participantDict in responseParticipants) {
            NCRoomParticipant *participant = [NCRoomParticipant participantWithDictionary:participantDict];
            [participants addObject:participant];
        }
        
        // Sort participants by:
        // - Participants before groups
        // - Online status
        // - In call
        // - Type (moderators before normal participants)
        // - Alphabetic
        NSSortDescriptor *alphabeticSorting = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        NSSortDescriptor *customSorting = [NSSortDescriptor sortDescriptorWithKey:@"" ascending:YES comparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            NCRoomParticipant *first = (NCRoomParticipant*)obj1;
            NCRoomParticipant *second = (NCRoomParticipant*)obj2;
            
            BOOL group1 = first.isGroup;
            BOOL group2 = second.isGroup;
            if (group1 != group2) {
                return group1 - group2;
            }
            
            BOOL online1 = !first.isOffline;
            BOOL online2 = !second.isOffline;
            if (online1 != online2) {
                return online2 - online1;
            }
            
            BOOL inCall1 = first.inCall > 0;
            BOOL inCall2 = second.inCall > 0;
            if (inCall1 != inCall2) {
                return inCall2 - inCall1;
            }
            
            BOOL moderator1 = first.canModerate;
            BOOL moderator2 = second.canModerate;
            if (moderator1 != moderator2) {
                return moderator2 - moderator1;
            }
            
            return NSOrderedSame;
        }];
        NSArray *descriptors = [NSArray arrayWithObjects:customSorting, alphabeticSorting, nil];
        [participants sortUsingDescriptors:descriptors];
        
        if (block) {
            block(participants, nil);
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

- (NSURLSessionDataTask *)addParticipant:(NSString *)participant ofType:(NSString *)type toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:participant forKey:@"newParticipant"];
    if (type && ![type isEqualToString:@""]) {
        [parameters setObject:type forKey:@"source"];
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

- (NSURLSessionDataTask *)removeAttendee:(NSInteger)attendeeId fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/attendees", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"attendeeId" : @(attendeeId)};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeParticipant:(NSString *)user fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"participant" : user};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeGuest:(NSString *)guest fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants/guests", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"participant" : guest};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeSelfFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveRoomCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants/self", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(0, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSInteger statusCode = [self getResponseStatusCode:task.response];
        [self checkResponseStatusCode:statusCode forAccount:account];
        if (block) {
            block(statusCode, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/moderators", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"participant" : user};
    if (conversationAPIVersion >= APIv3) {
        parameters = @{@"attendeeId" : user};
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

- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/moderators", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"participant" : moderator};
    if (conversationAPIVersion >= APIv3) {
        parameters = @{@"attendeeId" : moderator};
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)resendInvitationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"room/%@/participants/resend-invitations", encodedToken];
    NSInteger conversationAPIVersion = [self conversationAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:conversationAPIVersion forAccount:account];
    NSDictionary *parameters = nil;
    if (participant) {
        parameters = @{@"attendeeId" : participant};
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

#pragma mark - Call Controller

- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetPeersForCallCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"call/%@", encodedToken];
    NSInteger callAPIVersion = [self callAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:callAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responsePeers = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *peers = [[NSMutableArray alloc] initWithArray:responsePeers];
        if (block) {
            block(peers, nil);
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

- (NSURLSessionDataTask *)joinCall:(NSString *)token withCallFlags:(NSInteger)flags silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(JoinCallCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"call/%@", encodedToken];
    NSInteger callAPIVersion = [self callAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:callAPIVersion forAccount:account];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:@(flags) forKey:@"flags"];
    if (silently) {
        [parameters setObject:@(silently) forKey:@"silent"];
    }
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)leaveCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveCallCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"call/%@", encodedToken];
    NSInteger callAPIVersion = [self callAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:callAPIVersion forAccount:account];
    
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

- (NSURLSessionDataTask *)sendCallNotificationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"/call/%@/ring/%@", encodedToken, participant];
    NSInteger callAPIVersion = [self callAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:callAPIVersion forAccount:account];
    NSDictionary *parameters = nil;
    if (participant) {
        parameters = @{@"attendeeId" : participant};
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

#pragma mark - Chat Controller

- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId history:(BOOL)history includeLastMessage:(BOOL)include timeout:(BOOL)timeout lastCommonReadMessage:(NSInteger)lastCommonReadMessage setReadMarker:(BOOL)setReadMarker forAccount:(TalkAccount *)account withCompletionBlock:(GetChatMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"lookIntoFuture" : history ? @(0) : @(1),
                                 @"limit" : @(kReceivedChatMessagesLimit),
                                 @"timeout" : timeout ? @(30) : @(0),
                                 @"lastKnownMessageId" : @(messageId),
                                 @"lastCommonReadId" : @(lastCommonReadMessage),
                                 @"setReadMarker" : setReadMarker ? @(1) : @(0),
                                 @"includeLastKnown" : include ? @(1) : @(0)};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
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

- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token displayName:(NSString *)displayName replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block
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

- (NSURLSessionDataTask *)getMentionSuggestionsInRoom:(NSString *)token forString:(NSString *)string forAccount:(TalkAccount *)account withCompletionBlock:(GetMentionSuggestionsCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"chat/%@/mentions", encodedToken];
    NSInteger chatAPIVersion = [self chatAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:chatAPIVersion forAccount:account];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    NSDictionary *parameters = @{@"limit" : @"20",
                                 @"search" : string ? string : @"",
                                 @"includeStatus" : @(serverCapabilities.userStatus)
    };
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *mentions = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *suggestions = [[NSMutableArray alloc] initWithArray:mentions];;
        if (block) {
            block(suggestions, nil);
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
    NSDictionary *parameters = @{@"lastReadMessage" : @(lastReadMessage)};
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
                [messages addObject:message];
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

#pragma mark - Reactions Controller

- (NSURLSessionDataTask *)addReaction:(NSString *)reaction toMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"reaction/%@/%ld", encodedToken, (long)messageId];
    NSInteger reactionsAPIVersion = [self reactionsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:reactionsAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"reaction" : reaction};
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *reactionsDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(reactionsDict, nil, httpResponse.statusCode);
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

- (NSURLSessionDataTask *)removeReaction:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"reaction/%@/%ld", encodedToken, (long)messageId];
    NSInteger reactionsAPIVersion = [self reactionsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:reactionsAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"reaction" : reaction};
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *reactionsDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(reactionsDict, nil, httpResponse.statusCode);
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

- (NSURLSessionDataTask *)getReactions:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"reaction/%@/%ld", encodedToken, (long)messageId];
    NSInteger reactionsAPIVersion = [self reactionsAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:reactionsAPIVersion forAccount:account];
    NSDictionary *parameters = nil;
    if (reaction) {
        parameters = @{@"reaction" : reaction};
    }
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *reactionsDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            block(reactionsDict, nil, httpResponse.statusCode);
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

- (NSURLSessionDataTask *)createPollWithQuestion:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = [NSString stringWithFormat:@"poll/%@", encodedToken];
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

#pragma mark - Signaling Controller

- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/%@", encodedToken] : @"signaling";
    NSInteger signalingAPIVersion = [self signalingAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:signalingAPIVersion forAccount:account];
    NSDictionary *parameters = @{@"messages" : messages};
    
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

- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PullSignalingMessagesCompletionBlock)block
{
    NSString *encodedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/%@", encodedToken] : @"signaling";
    NSInteger signalingAPIVersion = [self signalingAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:signalingAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString
                                             parameters:nil progress:nil
                                                success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
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

- (NSURLSessionDataTask *)getSignalingSettingsForAccount:(TalkAccount *)account withCompletionBlock:(GetSignalingSettingsCompletionBlock)block
{
    NSString *endpoint = @"signaling/settings";
    NSInteger signalingAPIVersion = [self signalingAPIVersionForAccount:account];
    NSString *URLString = [self getRequestURLForEndpoint:endpoint withAPIVersion:signalingAPIVersion forAccount:account];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
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

- (NSString *)authenticationBackendUrlForAccount:(TalkAccount *)account
{
    NSString *endpoint = @"signaling/backend";
    NSInteger signalingAPIVersion = [self signalingAPIVersionForAccount:account];
    return [self getRequestURLForEndpoint:endpoint withAPIVersion:signalingAPIVersion forAccount:account];
}

#pragma mark - Settings

- (NSURLSessionDataTask *)setReadStatusPrivacySettingEnabled:(BOOL)enabled forAccount:(TalkAccount *)account withCompletionBlock:(SetReadStatusPrivacySettingCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForEndpoint:@"settings/user" withAPIVersion:APIv1 forAccount:account];
    NSDictionary *parameters = @{@"key" : @"read_status_privacy",
                                 @"value" : @(enabled)};
    
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

#pragma mark - Files

- (void)readFolderForAccount:(TalkAccount *)account atPath:(NSString *)path depth:(NSString *)depth withCompletionBlock:(ReadFolderCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    NSString *serverUrlString = [NSString stringWithFormat:@"%@%@/%@", account.server, [self filesPathForAccount:account], path ? path : @""];
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:serverUrlString depth:depth showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil timeout:60 queue:dispatch_get_main_queue() completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        if (errorCode == 0 && block) {
            block(files, nil);
        } else if (block) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:errorCode userInfo:nil];
            block(nil, error);
        }
    }];
}

- (void)shareFileOrFolderForAccount:(TalkAccount *)account atPath:(NSString *)path toRoom:(NSString *)token talkMetaData:(NSDictionary *)talkMetaData withCompletionBlock:(ShareFileOrFolderCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/files_sharing/api/v1/shares", account.server];
    
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:path forKey:@"path"];
    [parameters setObject:@(10) forKey:@"shareType"];
    [parameters setObject:token forKey:@"shareWith"];
    
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

- (void)getFileByFileId:(TalkAccount *)account fileId:(NSString *)fileId withCompletionBlock:(GetFileByFileIdCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    
    NSString *body = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
    <d:searchrequest xmlns:d=\"DAV:\" xmlns:oc=\"http://nextcloud.com/ns\">\
        <d:basicsearch>\
            <d:select>\
                <d:prop>\
                    <d:displayname />\
                    <d:getcontenttype />\
                    <d:resourcetype />\
                    <d:getcontentlength />\
                    <d:getlastmodified />\
                    <d:creationdate />\
                    <d:getetag />\
                    <d:quota-used-bytes />\
                    <d:quota-available-bytes />\
                    <oc:permissions xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:id xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:size xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:favorite xmlns:oc=\"http://owncloud.org/ns\" />\
                </d:prop>\
            </d:select>\
            <d:from>\
                <d:scope>\
                    <d:href>/files/%@</d:href>\
                    <d:depth>infinity</d:depth>\
                </d:scope>\
            </d:from>\
            <d:where>\
                <d:eq>\
                    <d:prop>\
                        <oc:fileid xmlns:oc=\"http://owncloud.org/ns\" />\
                    </d:prop>\
                    <d:literal>%@</d:literal>\
                </d:eq>\
            </d:where>\
            <d:orderby />\
        </d:basicsearch>\
    </d:searchrequest>";
    
    NSString *bodyRequest = [NSString stringWithFormat:body, account.userId, fileId];
    [[NCCommunication shared] searchBodyRequestWithServerUrl:account.server requestBody:bodyRequest showHiddenFiles:YES customUserAgent:nil addCustomHeaders:nil timeout:0 queue:dispatch_get_main_queue() completionHandler:^(NSString *account, NSArray<NCCommunicationFile *> *files, NSInteger error, NSString *errorDescription) {
        
        if (block) {
            if ([files count] > 0) {
                block([files objectAtIndex:0], error, errorDescription);
            } else {
                block(nil, error, errorDescription);
            }
        }
    }];
}

- (void)uniqueNameForFileUploadWithName:(NSString *)fileName originalName:(BOOL)isOriginalName forAccount:(TalkAccount *)account withCompletionBlock:(GetFileUniqueNameCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    
    NSString *fileServerPath = [self serverFilePathForFileName:fileName andAccountId:account.accountId];
    NSString *fileServerURL = [self serverFileURLForFilePath:fileServerPath andAccountId:account.accountId];
    
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:fileServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil timeout:60 queue:dispatch_get_main_queue() completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // File already exists
        if (errorCode == 0 && files.count == 1) {
            NSString *alternativeName = [self alternativeNameForFileName:fileName original:isOriginalName];
            [self uniqueNameForFileUploadWithName:alternativeName originalName:NO forAccount:account withCompletionBlock:block];
        // File does not exist
        } else if (errorCode == 404) {
            if (block) {
                block(fileServerURL, fileServerPath, 0, nil);
            }
        } else {
            NSLog(@"Error checking file name: %@", errorDescription);
            if (block) {
                block(nil, nil, errorCode, errorDescription);
            }
        }
    }];
}

- (void)checkOrCreateAttachmentFolderForAccount:(TalkAccount *)account withCompletionBlock:(CheckAttachmentFolderCompletionBlock)block
{
    [self setupNCCommunicationForAccount:account];
    
    NSString *attachmentFolderServerURL = [self attachmentFolderServerURLForAccountId:account.accountId];
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:attachmentFolderServerURL depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil timeout:60 queue:dispatch_get_main_queue() completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        // Attachment folder do not exist
        if (errorCode == 404) {
            [[NCCommunication shared] createFolder:attachmentFolderServerURL customUserAgent:nil addCustomHeaders:nil timeout:60 queue:dispatch_get_main_queue() completionHandler:^(NSString *account, NSString *ocId, NSDate *date, NSInteger errorCode, NSString *errorDescription) {
                if (block) {
                    block(errorCode == 0, errorCode);
                }
            }];
        } else {
            NSLog(@"Error checking attachment folder: %@", errorDescription);
            if (block) {
                block(NO, errorCode);
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

- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId withStyle:(UIUserInterfaceStyle)style andSize:(NSInteger)size usingAccount:(TalkAccount *)account
{
    return [self createAvatarRequestForUser:userId withCachePolicy:NSURLRequestReturnCacheDataElseLoad style:style andSize:size usingAccount:account];
}

- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId withCachePolicy:(NSURLRequestCachePolicy)cachePolicy style:(UIUserInterfaceStyle)style andSize:(NSInteger)size usingAccount:(TalkAccount *)account
{
    NSString *encodedUser = [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:account.accountId];
    NSString *urlString;
    if (style == UIUserInterfaceStyleDark && serverCapabilities.versionMajor >= 25) {
        urlString = [NSString stringWithFormat:@"%@/index.php/avatar/%@/%ld/dark", account.server, encodedUser, (long)size];
    } else {
        urlString = [NSString stringWithFormat:@"%@/index.php/avatar/%@/%ld", account.server, encodedUser, (long)size];
    }
    NSMutableURLRequest *avatarRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:cachePolicy timeoutInterval:60];
    [avatarRequest setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    return avatarRequest;
}

- (void)getUserAvatarForUser:(NSString *)userId andSize:(NSInteger)size usingAccount:(TalkAccount *)account withCompletionBlock:(GetUserAvatarImageForUserCompletionBlock)block
{
    NSURLRequest *request = [self createAvatarRequestForUser:userId withStyle:UIUserInterfaceStyleLight andSize:size usingAccount:account];
    [_imageDownloader downloadImageForURLRequest:request success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull responseObject) {
        NSData *pngData = UIImagePNGRepresentation(responseObject);
        UIImage *image = [UIImage imageWithData:pngData];
        if (image && block) {
            block(image, nil);
        }
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
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

- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height usingAccount:(TalkAccount *)account
{
    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=%ld&y=%ld&forceIcon=1", account.server, fileId, (long)width, (long)height];
    NSMutableURLRequest *previewRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    [previewRequest setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    return previewRequest;
}

- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId withMaxHeight:(NSInteger) height usingAccount:(TalkAccount *)account
{
    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/core/preview?fileId=%@&x=-1&y=%ld&a=1&forceIcon=1", account.server, fileId, (long)height];
    
    NSMutableURLRequest *previewRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    [previewRequest setValue:[self authHeaderForAccount:account] forHTTPHeaderField:@"Authorization"];
    return previewRequest;
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
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/cloud/users/%@", account.server, account.userId];
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
    NSURLRequest *request = [self createAvatarRequestForUser:account.userId withCachePolicy:NSURLRequestReloadIgnoringCacheData style:style andSize:160 usingAccount:account];
    [_imageDownloader downloadImageForURLRequest:request success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull responseObject) {
        
        NSDictionary *headers = [response allHeaderFields];
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm beginWriteTransaction];
        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
        TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
        managedAccount.hasCustomAvatar = [[headers objectForKey:@"X-NC-IsCustomAvatar"] boolValue];
        [realm commitWriteTransaction];
        
        NSData *pngData = UIImagePNGRepresentation(responseObject);
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
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
        NSLog(@"Could not download user profile image");
    }];
}

- (UIImage *)userProfileImageForAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style andSize:(CGSize)size
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
    
    return [self imageWithImage:[UIImage imageWithContentsOfFile:filePath] convertToSize:size];
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

- (UIImage *)imageWithImage:(UIImage *)image convertToSize:(CGSize)size
{
    if (image) {
        UIGraphicsBeginImageContext(size);
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *destImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return destImage;
    }
    
    return nil;
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

#pragma mark - Server capabilities

- (NSURLSessionDataTask *)getServerCapabilitiesForServer:(NSString *)server withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/capabilities", server];
    NSDictionary *parameters = @{@"format" : @"json"};
    
    NSURLSessionDataTask *task = [_defaultAPISessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *capabilities = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(capabilities, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getServerCapabilitiesForAccount:(TalkAccount *)account withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/capabilities", account.server];
    NSDictionary *parameters = @{@"format" : @"json"};
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *capabilities = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(capabilities, nil);
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

#pragma mark - Server notifications

- (NSURLSessionDataTask *)getServerNotification:(NSInteger)notificationId forAccount:(TalkAccount *)account withCompletionBlock:(GetServerNotificationCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/notifications/%ld", account.server, (long)notificationId];
    
    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    // Workaround: Just in case session managers are not initialized when called from NotificationService extension.
    if (!apiSessionManager) {
        [self initSessionManagers];
        apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    }
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *notification = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(notification, nil, 0);
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

- (NSURLSessionDataTask *)getServerNotificationsForAccount:(TalkAccount *)account withLastETag:(NSString *)lastETag withCompletionBlock:(GetServerNotificationsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/notifications", account.server];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (lastETag) {
        [request addValue:lastETag forHTTPHeaderField:@"If-None-Match"];
    }

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager dataTaskWithRequest:request completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (!error) {
            NSArray *notifications = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
            NSDictionary *headers = [self getResponseHeaders:response];

            if (block) {
                block(notifications, [headers objectForKey:@"ETag"], nil);
            }
        } else {
            if (block) {
                block(nil, nil, error);
            }
        }
    }];

    [task resume];

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

    NSURLSessionDataTask *task = [[NCPushProxySessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

    NSURLSessionDataTask *task = [[NCPushProxySessionManager sharedInstance] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

#pragma mark - Reference handling

- (NSURLSessionDataTask *)getReferenceForUrlString:(NSString *)url forAccount:(TalkAccount *)account withCompletionBlock:(GetReferenceForUrlStringCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/references/resolve", account.server];
    NSDictionary *parameters = @{@"reference" : url};

    NCAPISessionManager *apiSessionManager = [_apiSessionManagers objectForKey:account.accountId];
    NSURLSessionDataTask *task = [apiSessionManager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseReferences = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"references"];
        if (block) {
            // When there's no data, the server returns an empty array instead of a dictionary
            // Also we don't want to have a dictionary with NSNull values in it
            if (![responseReferences isKindOfClass:[NSDictionary class]] || [[responseReferences objectForKey:url] isKindOfClass:[NSNull class]]) {
                block(@{}, nil);
            } else {
                block(responseReferences, nil);
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];

    return task;
}

- (NSURLRequest *)createReferenceThumbnailRequestForUrl:(NSString *)url
{
    NSMutableURLRequest *thumbnailRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    return thumbnailRequest;
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

- (void)checkResponseStatusCode:(NSInteger)statusCode forAccount:(TalkAccount *)account
{
    if (statusCode == 401) {
        // App token has been revoked
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:account.accountId forKey:@"accountId"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCTokenRevokedResponseReceivedNotification
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
    NSString *configurationHash = [headers objectForKey:@"X-Nextcloud-Talk-Hash"];
    
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

#pragma mark - NCCommunicationCommon Delegate

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

#pragma mark - OCURLSessionManager

@implementation OCURLSessionManager

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    // The pinnning check
    if ([[CCCertificate sharedManager] checkTrustedChallenge:challenge]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end
