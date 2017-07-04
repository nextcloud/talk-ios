//
//  NCAPIController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCAPIController.h"

#import "AFNetworking.h"

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

- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *rooms = [[NSMutableArray alloc] initWithArray:responseRooms];
        if (block) {
            block(rooms, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

- (void)getContactsWithCompletionBlock:(GetContactsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@%@/apps/files_sharing/api/v1/sharees?format=json&search=&perPage=200&itemType=call", _serverUrl, kNCOCSAPIVersion];
    
    [_manager GET:URLString parameters:nil success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSArray *responseContacts = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"users"];
        NSMutableArray *contacts = [[NSMutableArray alloc] initWithArray:responseContacts];
        if (block) {
            block(contacts, nil, [operation.response statusCode]);
        }
    } failure:^(AFHTTPRequestOperation * _Nullable operation, NSError * _Nonnull error) {
        if (block) {
            block(nil, error, [operation.response statusCode]);
        }
    }];
}

@end
