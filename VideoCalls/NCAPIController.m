//
//  NCAPIController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCAPIController.h"

#import "NCAPISessionManager.h"
#import "NCPushProxySessionManager.h"
#import "NCSettingsController.h"

NSString * const kNCOCSAPIVersion       = @"/ocs/v2.php";
NSString * const kNCSpreedAPIVersion    = @"/apps/spreed/api/v1";

@interface NCAPIController () <NSURLSessionTaskDelegate, NSURLSessionDelegate>
{
    NSString *_serverUrl;
    NSString *_authToken;
    NSString *_userAgent;
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
    [[NCAPISessionManager sharedInstance].requestSerializer setValue:authHeader forHTTPHeaderField:@"Authorization"];
    
    _authToken = token;
}

- (NSString *)currentServerUrl
{
    return _serverUrl;
}

- (NSString *)getRequestURLForSpreedEndpoint:(NSString *)endpoint
{
    return [NSString stringWithFormat:@"%@%@%@/%@", _serverUrl, kNCOCSAPIVersion, kNCSpreedAPIVersion, endpoint];
}

#pragma mark - Contacts Controller

- (void)getContactsWithSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@%@/apps/files_sharing/api/v1/sharees", _serverUrl, kNCOCSAPIVersion];
    NSDictionary *parameters = @{@"fomat" : @"json",
                                 @"search" : search ? search : @"",
                                 @"perPage" : @"200",
                                 @"itemType" : @"call"};

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseUsers = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"users"];
        NSArray *responseExtactUsers = [[[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"exact"] objectForKey:@"users"];
        NSArray *responseContacts = [responseUsers arrayByAddingObjectsFromArray:responseExtactUsers];
        NSMutableArray *users = [[NSMutableArray alloc] initWithCapacity:responseContacts.count];
        for (NSDictionary *user in responseContacts) {
            NCUser *ncUser = [NCUser userWithDictionary:user];
            if (![ncUser.userId isEqualToString:[NCSettingsController sharedInstance].ncUser]) {
                [users addObject:ncUser];
            }
        }
        if (block) {
            block(users, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

#pragma mark - Rooms Controller

- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *rooms = [[NSMutableArray alloc] initWithCapacity:responseRooms.count];
        for (NSDictionary *room in responseRooms) {
            NCRoom *ncRoom = [NCRoom roomWithDictionary:room];
            [rooms addObject:ncRoom];
        }

        // Sort by lastPing
        NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastPing" ascending:NO];
        NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
        [rooms sortUsingDescriptors:descriptors];
        

        if (block) {
            block(rooms, nil, 0);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            NSInteger statusCode = 0;
            if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                statusCode = httpResponse.statusCode;
            }
            block(nil, error, statusCode);
        }
    }];
}

- (void)getRoomWithToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *roomDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NCRoom *room = [NCRoom roomWithDictionary:roomDict];
        if (block) {
            block(room, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)getRoomWithId:(NSInteger)roomId withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    
    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        for (NSDictionary *room in responseRooms) {
            NCRoom *ncRoom = [NCRoom roomWithDictionary:room];
            if (ncRoom.roomId == roomId) {
                if (block) {
                    block(ncRoom, nil);
                }
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)createRoomWith:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    
    [parameters setObject:@(type) forKey:@"roomType"];
    
    if (invite) {
        [parameters setObject:invite forKey:@"invite"];
    }
    
    if (roomName) {
        [parameters setObject:roomName forKey:@"roomName"];
    }
    
    [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *token = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"token"];
        if (block) {
            block(token, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];
    NSDictionary *parameters = @{@"roomName" : newName};

    [[NCAPISessionManager sharedInstance] PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(AddParticipantCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants", token]];
    NSDictionary *parameters = @{@"newParticipant" : user};

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)removeSelfFromRoom:(NSString *)token withCompletionBlock:(RemoveSelfFromRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/self", token]];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)deleteRoom:(NSString *)token withCompletionBlock:(DeleteRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)setPassword:(NSString *)password toRoom:(NSString *)token withCompletionBlock:(SetPasswordCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/password", token]];
    NSDictionary *parameters = @{@"password" : password};

    [[NCAPISessionManager sharedInstance] PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)joinRoom:(NSString *)token withCompletionBlock:(JoinRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/active", token]];

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *sessionId = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"sessionId"];
        if (block) {
            block(sessionId, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)exitRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/active", token]];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

#pragma mark - Call Controller

- (void)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responsePeers = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *peers = [[NSMutableArray alloc] initWithArray:responsePeers];
        if (block) {
            block(peers, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@/ping", token]];

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

#pragma mark - Signaling Controller

- (void)sendSignalingMessages:(NSString *)messages withCompletionBlock:(SendSignalingMessagesCompletionBlock)block
{
    [self sendSignalingMessages:messages toRoom:nil withCompletionBlock:block];
}
- (void)pullSignalingMessagesWithCompletionBlock:(PullSignalingMessagesCompletionBlock)block
{
    [self pullSignalingMessagesFromRoom:nil withCompletionBlock:block];
}

- (void)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
{
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/messages/%@", token] : @"signaling";
    NSString *URLString = [self getRequestURLForSpreedEndpoint:endpoint];
    NSDictionary *parameters = @{@"messages" : messages};

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

- (void)pullSignalingMessagesFromRoom:(NSString *)token withCompletionBlock:(PullSignalingMessagesCompletionBlock)block
{
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/messages/%@", token] : @"signaling";
    NSString *URLString = [self getRequestURLForSpreedEndpoint:endpoint];

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)getSignalingSettingsWithCompletionBlock:(GetSignalingSettingsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"signaling/settings"];

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

#pragma mark - User avatars

- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId andSize:(NSInteger)size
{
    #warning TODO - Clear cache from time to time and reload possible new images
    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/avatar/%@/%ld", _serverUrl, userId, (long)size];
    return [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                            cachePolicy:NSURLRequestReturnCacheDataElseLoad
                        timeoutInterval:60];
}

#pragma mark - User profile

- (void)getUserProfileWithCompletionBlock:(GetUserProfileCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/user", _serverUrl];
    NSDictionary *parameters = @{@"fomat" : @"json"};

    [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *profile = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(profile, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}

- (void)getServerCapabilitiesWithCompletionBlock:(GetServerCapabilitiesCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/capabilities", _serverUrl];
    NSDictionary *parameters = @{@"fomat" : @"json"};
    
    [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *capabilities = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(capabilities, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}


#pragma mark - Push Notifications

- (void)subscribeToNextcloudServer:(SubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", _serverUrl];
    NSString *devicePublicKey = [[NSString alloc] initWithData:[NCSettingsController sharedInstance].ncPNPublicKey encoding:NSUTF8StringEncoding];

    NSDictionary *parameters = @{@"pushTokenHash" : [[NCSettingsController sharedInstance] pushTokenSHA512],
                                 @"devicePublicKey" : devicePublicKey,
                                 @"proxyServer" : kNCPushServer
                                 };

    [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
}
- (void)unsubscribeToNextcloudServer:(UnsubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", _serverUrl];

    [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}
- (void)subscribeToPushServer:(SubscribeToPushProxyCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", kNCPushServer];

    NSDictionary *parameters = @{@"pushToken" : [NCSettingsController sharedInstance].ncPushToken,
                                 @"deviceIdentifier" : [NCSettingsController sharedInstance].ncDeviceIdentifier,
                                 @"deviceIdentifierSignature" : [NCSettingsController sharedInstance].ncDeviceSignature,
                                 @"userPublicKey" : [NCSettingsController sharedInstance].ncUserPublicKey
                                 };

    [[NCPushProxySessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}
- (void)unsubscribeToPushServer:(UnsubscribeToPushProxyCompletionBlock)block
{    
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", kNCPushServer];

    NSDictionary *parameters = @{@"deviceIdentifier" : [NCSettingsController sharedInstance].ncDeviceIdentifier,
                                 @"deviceIdentifierSignature" : [NCSettingsController sharedInstance].ncDeviceSignature,
                                 @"userPublicKey" : [NCSettingsController sharedInstance].ncUserPublicKey
                                 };

    [[NCPushProxySessionManager sharedInstance] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        if (block) {
            block(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(error);
        }
    }];
}

#pragma mark - Utils

- (void)cancelAllOperations
{
    [_manager.operationQueue cancelAllOperations];
}


@end
