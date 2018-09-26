//
//  NCAPIController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCAPIController.h"

#import "NCAPISessionManager.h"
#import "NCFilePreviewSessionManager.h"
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
    
    //Set NC server in managers that requires it
    [[NCFilePreviewSessionManager sharedInstance] setNCServer:serverUrl];
}

- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token
{
    NSString *userTokenString = [NSString stringWithFormat:@"%@:%@", user, token];
    NSData *data = [userTokenString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Encoded = [data base64EncodedStringWithOptions:0];
    
    NSString *authHeader = [[NSString alloc]initWithFormat:@"Basic %@",base64Encoded];
    [[NCAPISessionManager sharedInstance].requestSerializer setValue:authHeader forHTTPHeaderField:@"Authorization"];
    
    _authToken = token;
    
    //Set auth header in managers that requires authentication
    [[NCFilePreviewSessionManager sharedInstance] setAuthHeaderWithUser:user andToken:token];
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

- (NSURLSessionDataTask *)getContactsWithSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@%@/apps/files_sharing/api/v1/sharees", _serverUrl, kNCOCSAPIVersion];
    NSDictionary *parameters = @{@"fomat" : @"json",
                                 @"search" : search ? search : @"",
                                 @"perPage" : @"200",
                                 @"itemType" : @"call"};

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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
        NSMutableDictionary *indexedContacts = [self indexedUsersFromUsersArray:users];
        NSArray *indexes = [[indexedContacts allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        if (block) {
            block(indexes, indexedContacts, users, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, nil, nil, error);
        }
    }];
    
    return task;
}

- (NSMutableDictionary *)indexedUsersFromUsersArray:(NSArray *)users
{
    NSMutableDictionary *indexedUsers = [[NSMutableDictionary alloc] init];
    for (NCUser *user in users) {
        NSString *index = [[user.name substringToIndex:1] uppercaseString];
        NSRange first = [user.name rangeOfComposedCharacterSequenceAtIndex:0];
        NSRange match = [user.name rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet] options:0 range:first];
        if (match.location == NSNotFound) {
            index = @"#";
        }
        NSMutableArray *usersForIndex = [indexedUsers valueForKey:index];
        if (usersForIndex == nil) {
            usersForIndex = [[NSMutableArray alloc] init];
        }
        [usersForIndex addObject:user];
        [indexedUsers setObject:usersForIndex forKey:index];
    }
    return indexedUsers;
}

#pragma mark - Rooms Controller

- (NSURLSessionDataTask *)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
        NSArray *responseRooms = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *rooms = [[NSMutableArray alloc] initWithCapacity:responseRooms.count];
        for (NSDictionary *room in responseRooms) {
            NCRoom *ncRoom = [NCRoom roomWithDictionary:room];
            [rooms addObject:ncRoom];
        }
        // Sort by favorites
        NSSortDescriptor *favoriteSorting = [NSSortDescriptor sortDescriptorWithKey:@"" ascending:YES comparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            NCRoom *first = (NCRoom*)obj1;
            NCRoom *second = (NCRoom*)obj2;
            BOOL favorite1 = first.isFavorite;
            BOOL favorite2 = second.isFavorite;
            if (favorite1 != favorite2) {
                return favorite2 - favorite1;
            }
            return NSOrderedSame;
        }];
        // Sort by lastPing or lastActivity
        NSString *sortKey = ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityLastRoomActivity]) ? @"lastActivity" : @"lastPing";
        NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:sortKey ascending:NO];
        NSArray *descriptors = [NSArray arrayWithObjects:favoriteSorting, valueDescriptor, nil];
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
    
    return task;
}

- (NSURLSessionDataTask *)getRoomWithToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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
    
    return task;
}

- (NSURLSessionDataTask *)getRoomWithId:(NSInteger)roomId withCompletionBlock:(GetRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"room"];
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
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
    
    return task;
}

- (NSURLSessionDataTask *)createRoomWith:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block
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
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *token = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"token"];
        if (block) {
            block(token, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];
    NSDictionary *parameters = @{@"roomName" : newName};

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/public", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)deleteRoom:(NSString *)token withCompletionBlock:(DeleteRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)setPassword:(NSString *)password toRoom:(NSString *)token withCompletionBlock:(SetPasswordCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/password", token]];
    NSDictionary *parameters = @{@"password" : password};

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] PUT:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)joinRoom:(NSString *)token withCompletionBlock:(JoinRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/active", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSString *sessionId = [[[responseObject objectForKey:@"ocs"] objectForKey:@"data"] objectForKey:@"sessionId"];
        if (block) {
            block(sessionId, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)exitRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/active", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)addRoomToFavorites:(NSString *)token withCompletionBlock:(FavoriteRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/favorite", token]];
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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
- (NSURLSessionDataTask *)removeRoomFromFavorites:(NSString *)token withCompletionBlock:(FavoriteRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/favorite", token]];
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

#pragma mark - Participants Controller

- (NSURLSessionDataTask *)getParticipantsFromRoom:(NSString *)token withCompletionBlock:(GetParticipantsFromRoomCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants", token]];
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseParticipants = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *participants = [[NSMutableArray alloc] initWithCapacity:responseParticipants.count];
        for (NSDictionary *participantDict in responseParticipants) {
            NCRoomParticipant *participant = [NCRoomParticipant participantWithDictionary:participantDict];
            [participants addObject:participant];
        }
        
        // Sort participants by:
        // - Moderators first
        // - Online status
        // - Users > Guests
        // - Alphabetic
        NSSortDescriptor *alphabeticSorting = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        NSSortDescriptor *customSorting = [NSSortDescriptor sortDescriptorWithKey:@"" ascending:YES comparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            NCRoomParticipant *first = (NCRoomParticipant*)obj1;
            NCRoomParticipant *second = (NCRoomParticipant*)obj2;
            
            BOOL moderator1 = first.canModerate;
            BOOL moderator2 = second.canModerate;
            if (moderator1 != moderator2) {
                return moderator2 - moderator1;
            }
            
            BOOL online1 = !first.isOffline;
            BOOL online2 = !second.isOffline;
            if (online1 != online2) {
                return online2 - online1;
            }
            
            BOOL guest1 = first.participantType == kNCParticipantTypeGuest;
            BOOL guest2 = second.participantType == kNCParticipantTypeGuest;
            if (guest1 != guest2) {
                return guest1 - guest2;
            }
            
            return NSOrderedSame;
        }];
        NSArray *descriptors = [NSArray arrayWithObjects:customSorting, alphabeticSorting, nil];
        [participants sortUsingDescriptors:descriptors];
        
        if (block) {
            block(participants, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants", token]];
    NSDictionary *parameters = @{@"newParticipant" : user};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeParticipant:(NSString *)user fromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants", token]];
    NSDictionary *parameters = @{@"participant" : user};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeGuest:(NSString *)guest fromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/guests", token]];
    NSDictionary *parameters = @{@"participant" : guest};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)removeSelfFromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/participants/self", token]];
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/moderators", token]];
    NSDictionary *parameters = @{@"participant" : user};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"room/%@/moderators", token]];
    NSDictionary *parameters = @{@"participant" : moderator};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:parameters success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

#pragma mark - Call Controller

- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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
    
    return task;
}

- (NSURLSessionDataTask *)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@/ping", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"call/%@", token]];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

#pragma mark - Chat Controller

- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId history:(BOOL)history withCompletionBlock:(GetChatMessagesCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"chat/%@", token]];
    NSDictionary *parameters = @{@"lookIntoFuture" : history ? @(0) : @(1),
                                 @"limit" : @(200),
                                 @"timeout" : @"30",
                                 @"lastKnownMessageId" : @(messageId)};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *responseMessages = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *messages = [[NSMutableArray alloc] initWithCapacity:responseMessages.count];
        for (NSDictionary *message in responseMessages) {
            NCChatMessage *ncMessage = [NCChatMessage messageWithDictionary:message];
            [messages addObject:ncMessage];
        }
        
        // Sort by messageId
        NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"messageId" ascending:YES];
        NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
        [messages sortUsingDescriptors:descriptors];
        
        if (block) {
            block(messages, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token displayName:(NSString *)displayName withCompletionBlock:(SendChatMessagesCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"chat/%@", token]];
    NSDictionary *parameters = @{@"message" : message,
                                 @"token" : token};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)getMentionSuggestionsInRoom:(NSString *)token forString:(NSString *)string withCompletionBlock:(GetMentionSuggestionsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:[NSString stringWithFormat:@"chat/%@/mentions", token]];
    NSDictionary *parameters = @{@"limit" : @"20",
                                 @"search" : string ? string : @""};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSArray *mentions = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        NSMutableArray *suggestions = [[NSMutableArray alloc] initWithArray:mentions];;
        if (block) {
            block(suggestions, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

#pragma mark - Signaling Controller

- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages withCompletionBlock:(SendSignalingMessagesCompletionBlock)block
{
    return [self sendSignalingMessages:messages toRoom:nil withCompletionBlock:block];
}
- (NSURLSessionDataTask *)pullSignalingMessagesWithCompletionBlock:(PullSignalingMessagesCompletionBlock)block
{
    return [self pullSignalingMessagesFromRoom:nil withCompletionBlock:block];
}

- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
{
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/%@", token] : @"signaling";
    NSString *URLString = [self getRequestURLForSpreedEndpoint:endpoint];
    NSDictionary *parameters = @{@"messages" : messages};

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token withCompletionBlock:(PullSignalingMessagesCompletionBlock)block
{
    NSString *endpoint = (token) ? [NSString stringWithFormat:@"signaling/%@", token] : @"signaling";
    NSString *URLString = [self getRequestURLForSpreedEndpoint:endpoint];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString
                                                                parameters:nil progress:nil
                                                                   success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getSignalingSettingsWithCompletionBlock:(GetSignalingSettingsCompletionBlock)block
{
    NSString *URLString = [self getRequestURLForSpreedEndpoint:@"signaling/settings"];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = responseObject;
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSString *)authenticationBackendUrl
{
    return [self getRequestURLForSpreedEndpoint:@"signaling/backend"];
}

#pragma mark - User avatars

- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId andSize:(NSInteger)size
{
    #warning TODO - Clear cache from time to time and reload possible new images
    NSString *encodedUser = [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"%@/index.php/avatar/%@/%ld", _serverUrl, encodedUser, (long)size];
    return [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                            cachePolicy:NSURLRequestReturnCacheDataElseLoad
                        timeoutInterval:60];
}

#pragma mark - User profile

- (NSURLSessionDataTask *)getUserProfileWithCompletionBlock:(GetUserProfileCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/user", _serverUrl];
    NSDictionary *parameters = @{@"fomat" : @"json"};

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *profile = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(profile, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)getServerCapabilitiesWithCompletionBlock:(GetServerCapabilitiesCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v1.php/cloud/capabilities", _serverUrl];
    NSDictionary *parameters = @{@"fomat" : @"json"};
    
    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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


#pragma mark - Push Notifications

- (NSURLSessionDataTask *)subscribeToNextcloudServer:(SubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", _serverUrl];
    NSString *devicePublicKey = [[NSString alloc] initWithData:[NCSettingsController sharedInstance].ncPNPublicKey encoding:NSUTF8StringEncoding];

    NSDictionary *parameters = @{@"pushTokenHash" : [[NCSettingsController sharedInstance] pushTokenSHA512],
                                 @"devicePublicKey" : devicePublicKey,
                                 @"proxyServer" : kNCPushServer
                                 };

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] POST:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *responseDict = [[responseObject objectForKey:@"ocs"] objectForKey:@"data"];
        if (block) {
            block(responseDict, nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        if (block) {
            block(nil, error);
        }
    }];
    
    return task;
}

- (NSURLSessionDataTask *)unsubscribeToNextcloudServer:(UnsubscribeToNextcloudServerCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/ocs/v2.php/apps/notifications/api/v2/push", _serverUrl];

    NSURLSessionDataTask *task = [[NCAPISessionManager sharedInstance] DELETE:URLString parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

- (NSURLSessionDataTask *)subscribeToPushServer:(SubscribeToPushProxyCompletionBlock)block
{
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", kNCPushServer];

    NSDictionary *parameters = @{@"pushToken" : [NCSettingsController sharedInstance].ncPushToken,
                                 @"deviceIdentifier" : [NCSettingsController sharedInstance].ncDeviceIdentifier,
                                 @"deviceIdentifierSignature" : [NCSettingsController sharedInstance].ncDeviceSignature,
                                 @"userPublicKey" : [NCSettingsController sharedInstance].ncUserPublicKey
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

- (NSURLSessionDataTask *)unsubscribeToPushServer:(UnsubscribeToPushProxyCompletionBlock)block
{    
    NSString *URLString = [NSString stringWithFormat:@"%@/devices", kNCPushServer];

    NSDictionary *parameters = @{@"deviceIdentifier" : [NCSettingsController sharedInstance].ncDeviceIdentifier,
                                 @"deviceIdentifierSignature" : [NCSettingsController sharedInstance].ncDeviceSignature,
                                 @"userPublicKey" : [NCSettingsController sharedInstance].ncUserPublicKey
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

#pragma mark - Utils

- (void)cancelAllOperations
{
    [_manager.operationQueue cancelAllOperations];
}


@end
