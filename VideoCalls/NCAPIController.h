//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AFNetworking.h"
#import "NCChatMessage.h"
#import "NCRoom.h"
#import "NCUser.h"

typedef void (^GetContactsCompletionBlock)(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error);

typedef void (^GetRoomsCompletionBlock)(NSMutableArray *rooms, NSError *error, NSInteger statusCode);
typedef void (^GetRoomCompletionBlock)(NCRoom *room, NSError *error);
typedef void (^CreateRoomCompletionBlock)(NSString *token, NSError *error);
typedef void (^RenameRoomCompletionBlock)(NSError *error);
typedef void (^MakeRoomPublicCompletionBlock)(NSError *error);
typedef void (^MakeRoomPrivateCompletionBlock)(NSError *error);
typedef void (^DeleteRoomCompletionBlock)(NSError *error);
typedef void (^SetPasswordCompletionBlock)(NSError *error);
typedef void (^JoinRoomCompletionBlock)(NSString *sessionId, NSError *error);
typedef void (^ExitRoomCompletionBlock)(NSError *error);
typedef void (^FavoriteRoomCompletionBlock)(NSError *error);

typedef void (^GetParticipantsFromRoomCompletionBlock)(NSMutableArray *participants, NSError *error);
typedef void (^ParticipantModificationCompletionBlock)(NSError *error);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error);
typedef void (^JoinCallCompletionBlock)(NSError *error);
typedef void (^PingCallCompletionBlock)(NSError *error);
typedef void (^LeaveCallCompletionBlock)(NSError *error);

typedef void (^GetChatMessagesCompletionBlock)(NSMutableArray *messages, NSError *error);
typedef void (^SendChatMessagesCompletionBlock)(NSError *error);
typedef void (^GetMentionSuggestionsCompletionBlock)(NSMutableArray *mentions, NSError *error);

typedef void (^SendSignalingMessagesCompletionBlock)(NSError *error);
typedef void (^PullSignalingMessagesCompletionBlock)(NSDictionary *messages, NSError *error);
typedef void (^GetSignalingSettingsCompletionBlock)(NSDictionary *settings, NSError *error);

typedef void (^GetUserProfileCompletionBlock)(NSDictionary *userProfile, NSError *error);

typedef void (^GetServerCapabilitiesCompletionBlock)(NSDictionary *serverCapabilities, NSError *error);

typedef void (^SubscribeToNextcloudServerCompletionBlock)(NSDictionary *responseDict, NSError *error);
typedef void (^UnsubscribeToNextcloudServerCompletionBlock)(NSError *error);
typedef void (^SubscribeToPushProxyCompletionBlock)(NSError *error);
typedef void (^UnsubscribeToPushProxyCompletionBlock)(NSError *error);


@interface NCAPIController : NSObject

@property (nonatomic, strong) AFHTTPSessionManager *manager;
@property (nonatomic, strong) NSURLSession *session;

+ (instancetype)sharedInstance;
- (void)setNCServer:(NSString *)serverUrl;
- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token;
- (NSString *)currentServerUrl;

// Contacts Controller
- (NSURLSessionDataTask *)getContactsWithSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block;
- (NSMutableDictionary *)indexedUsersFromUsersArray:(NSArray *)users;

// Rooms Controller
- (NSURLSessionDataTask *)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block;
- (NSURLSessionDataTask *)getRoomWithToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block;
- (NSURLSessionDataTask *)getRoomWithId:(NSInteger)roomId withCompletionBlock:(GetRoomCompletionBlock)block;
- (NSURLSessionDataTask *)createRoomWith:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block;
- (NSURLSessionDataTask *)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block;
- (NSURLSessionDataTask *)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block;
- (NSURLSessionDataTask *)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block;
- (NSURLSessionDataTask *)deleteRoom:(NSString *)token withCompletionBlock:(DeleteRoomCompletionBlock)block;
- (NSURLSessionDataTask *)setPassword:(NSString *)password toRoom:(NSString *)token withCompletionBlock:(SetPasswordCompletionBlock)block;
- (NSURLSessionDataTask *)joinRoom:(NSString *)token withCompletionBlock:(JoinRoomCompletionBlock)block;
- (NSURLSessionDataTask *)exitRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block;
- (NSURLSessionDataTask *)addRoomToFavorites:(NSString *)token withCompletionBlock:(FavoriteRoomCompletionBlock)block;
- (NSURLSessionDataTask *)removeRoomFromFavorites:(NSString *)token withCompletionBlock:(FavoriteRoomCompletionBlock)block;

// Participants Controller
- (NSURLSessionDataTask *)getParticipantsFromRoom:(NSString *)token withCompletionBlock:(GetParticipantsFromRoomCompletionBlock)block;
- (NSURLSessionDataTask *)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeParticipant:(NSString *)user fromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeGuest:(NSString *)guest fromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeSelfFromRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Call Controller
- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (NSURLSessionDataTask *)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block;
- (NSURLSessionDataTask *)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block;
- (NSURLSessionDataTask *)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block;

// Chat Controller
- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId history:(BOOL)history withCompletionBlock:(GetChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token displayName:(NSString *)displayName withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getMentionSuggestionsInRoom:(NSString *)token forString:(NSString *)string withCompletionBlock:(GetMentionSuggestionsCompletionBlock)block;

// Signaling Controller
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesWithCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token withCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getSignalingSettingsWithCompletionBlock:(GetSignalingSettingsCompletionBlock)block;
- (NSString *)authenticationBackendUrl;

// User avatars
- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId andSize:(NSInteger)size;

// User Profile
- (NSURLSessionDataTask *)getUserProfileWithCompletionBlock:(GetUserProfileCompletionBlock)block;

// Server capabilities
- (NSURLSessionDataTask *)getServerCapabilitiesWithCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;

// Push Notifications
- (NSURLSessionDataTask *)subscribeToNextcloudServer:(SubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeToNextcloudServer:(UnsubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)subscribeToPushServer:(SubscribeToPushProxyCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeToPushServer:(UnsubscribeToPushProxyCompletionBlock)block;


//Utils
- (void)cancelAllOperations;

@end
