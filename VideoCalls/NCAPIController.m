//
//  NCAPIController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCAPIController.h"

#import "AFNetworking.h"
#import "NCSettingsController.h"

NSString * const kNCOCSAPIVersion       = @"/ocs/v2.php";
NSString * const kNCSpreedAPIVersion    = @"/apps/spreed/api/v1";
NSString * const kNCUserAgent           = @"Video Calls iOS";

@interface NCAPIController ()
{
    AFHTTPRequestOperationManager *_manager;
    NSString *_serverUrl;
    NSString *_authToken;
}

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
        _manager = [[AFHTTPRequestOperationManager alloc] init];
        _manager.responseSerializer = [[AFJSONResponseSerializer alloc] init];
        _manager.requestSerializer = [[AFHTTPRequestSerializer alloc] init];
        
        _manager.requestSerializer = [[AFHTTPRequestSerializer alloc] init];
        _manager.responseSerializer = [[AFJSONResponseSerializer alloc] init];
        
        AFSecurityPolicy* policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        _manager.securityPolicy = policy;
        _manager.securityPolicy.allowInvalidCertificates = YES;
        _manager.securityPolicy.validatesDomainName = NO;
        
        [_manager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [_manager.requestSerializer setValue:@"true" forHTTPHeaderField:@"OCS-APIRequest"];
        [_manager.requestSerializer setValue:kNCUserAgent forHTTPHeaderField:@"User-Agent"];
    }
    return self;
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
    [_manager.requestSerializer setValue:authHeader forHTTPHeaderField:@"Authorization"];
    
    _authToken = token;
}

- (NSString *)getRequestURLForSpreedEndpoint:(NSString *)endpoint
{
    return [NSString stringWithFormat:@"%@%@%@/%@", _serverUrl, kNCOCSAPIVersion, kNCSpreedAPIVersion, endpoint];
}

#pragma mark - Contacts Controller

- (void)getContactsWithCompletionBlock:(GetContactsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@%@/apps/files_sharing/api/v1/sharees?format=json&search=&perPage=200&itemType=call", _serverUrl, kNCOCSAPIVersion];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSArray *responseUsers = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"users"];
        NSMutableArray *users = [[NSMutableArray alloc] initWithCapacity:responseUsers.count];
        for (NSDictionary *user in responseUsers) {
            NCUser *ncUser = [NCUser userWithDictionary:user];
            if (![ncUser.userId isEqualToString:[NCSettingsController sharedInstance].ncUser]) {
                [users addObject:ncUser];
            }
        }
        if (block) {
            block(users, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

#pragma mark - Rooms Controller

- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *rooms = [[NSMutableArray alloc] initWithCapacity:responseRooms.count];
        for (NSDictionary *room in responseRooms) {
            NCRoom *ncRoom = [NCRoom roomWithDictionary:room];
            [rooms addObject:ncRoom];
        }
        if (block) {
            block(rooms, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)getRoom:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *room = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(room, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)createRoomWith:(NSString *)invite ofType:(NCRoomType)type withCompletionBlock:(CreateRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    NSDictionary *parameters = @{@"roomType" : @(type), @"invite" : invite};
    
    [_manager POST:URLString parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSString *token = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"token"];
        if (block) {
            block(token, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];
    NSDictionary *parameters = @{@"roomName" : newName};
    
    [_manager PUT:URLString parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

- (void)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(AddParticipantCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants", token]];
    NSDictionary *parameters = @{@"newParticipant" : user};
    
    [_manager POST:URLString parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

- (void)removeSelfFromRoom:(NSString *)token withCompletionBlock:(RemoveSelfFromRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/self", token]];
    
    [_manager DELETE:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

- (void)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];
    
    [_manager POST:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

- (void)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];
    
    [_manager DELETE:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

#pragma mark - Call Controller

- (void)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSArray *responsePeers = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *peers = [[NSMutableArray alloc] initWithArray:responsePeers];
        if (block) {
            block(peers, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];
    
    [_manager POST:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSString *sessionId = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"sessionId"];
        if (block) {
            block(sessionId, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];
    
    [_manager PUT:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}

- (void)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];
    
    [_manager DELETE:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        if (block) {
            block(nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(error, [operation.response statusCode]);
        }
    }];
}


@end
