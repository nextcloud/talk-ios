//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AFNetworking.h"
#import "NCRoom.h"
#import "NCUser.h"

typedef void (^GetContactsCompletionBlock)(NSMutableArray *contacts, NSError *error);

typedef void (^GetRoomsCompletionBlock)(NSMutableArray *rooms, NSError *error, NSInteger statusCode);
typedef void (^GetRoomCompletionBlock)(NCRoom *room, NSError *error);
typedef void (^CreateRoomCompletionBlock)(NSString *token, NSError *error);
typedef void (^RenameRoomCompletionBlock)(NSError *error);
typedef void (^AddParticipantCompletionBlock)(NSError *error);
typedef void (^RemoveSelfFromRoomCompletionBlock)(NSError *error);
typedef void (^MakeRoomPublicCompletionBlock)(NSError *error);
typedef void (^MakeRoomPrivateCompletionBlock)(NSError *error);
typedef void (^DeleteRoomCompletionBlock)(NSError *error);
typedef void (^SetPasswordCompletionBlock)(NSError *error);
typedef void (^JoinRoomCompletionBlock)(NSString *sessionId, NSError *error);
typedef void (^ExitRoomCompletionBlock)(NSError *error);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error);
typedef void (^JoinCallCompletionBlock)(NSError *error);
typedef void (^PingCallCompletionBlock)(NSError *error);
typedef void (^LeaveCallCompletionBlock)(NSError *error);

typedef void (^SendSignalingMessagesCompletionBlock)(NSError *error);
typedef void (^PullSignalingMessagesCompletionBlock)(NSDictionary *messages, NSError *error);
typedef void (^GetSignalingSettingsCompletionBlock)(NSDictionary *settings, NSError *error);

typedef void (^GetUserProfileCompletionBlock)(NSDictionary *userProfile, NSError *error);

typedef void (^GetServerCapabilitiesCompletionBlock)(NSDictionary *serverCapabilities, NSError *error);

typedef void (^SubscribeToNextcloudServerCompletionBlock)(NSDictionary *responseDict, NSError *error);
typedef void (^UnsubscribeToNextcloudServerCompletionBlock)(NSError *error);
typedef void (^SubscribeToPushProxyCompletionBlock)(NSError *error);
typedef void (^UnsubscribeToPushProxyCompletionBlock)(NSError *error);

extern NSString * const NCRoomCreatedNotification;


@interface NCAPIController : NSObject

@property (nonatomic, strong) AFHTTPSessionManager *manager;
@property (nonatomic, strong) NSURLSession *session;

+ (instancetype)sharedInstance;
- (void)setNCServer:(NSString *)serverUrl;
- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token;
- (NSString *)currentServerUrl;

// Contacts Controller
- (void)getContactsWithSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block;

// Rooms Controller
- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block;
- (void)getRoomWithToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block;
- (void)getRoomWithId:(NSInteger)roomId withCompletionBlock:(GetRoomCompletionBlock)block;
- (void)createRoomWith:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block;
- (void)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block;
- (void)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(AddParticipantCompletionBlock)block;
- (void)removeSelfFromRoom:(NSString *)token withCompletionBlock:(RemoveSelfFromRoomCompletionBlock)block;
- (void)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block;
- (void)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block;
- (void)deleteRoom:(NSString *)token withCompletionBlock:(DeleteRoomCompletionBlock)block;
- (void)setPassword:(NSString *)password toRoom:(NSString *)token withCompletionBlock:(SetPasswordCompletionBlock)block;
- (void)joinRoom:(NSString *)token withCompletionBlock:(JoinRoomCompletionBlock)block;
- (void)exitRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block;


// Call Controller
- (void)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (void)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block;
- (void)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block;
- (void)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block;

// Signaling Controller
- (void)sendSignalingMessages:(NSString *)messages withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (void)pullSignalingMessagesWithCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (void)getSignalingSettingsWithCompletionBlock:(GetSignalingSettingsCompletionBlock)block;

// User avatars
- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId andSize:(NSInteger)size;

// User Profile
- (void)getUserProfileWithCompletionBlock:(GetUserProfileCompletionBlock)block;

// Server capabilities
- (void)getServerCapabilitiesWithCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;

// Push Notifications
- (void)subscribeToNextcloudServer:(SubscribeToNextcloudServerCompletionBlock)block;
- (void)unsubscribeToNextcloudServer:(UnsubscribeToNextcloudServerCompletionBlock)block;
- (void)subscribeToPushServer:(SubscribeToPushProxyCompletionBlock)block;
- (void)unsubscribeToPushServer:(UnsubscribeToPushProxyCompletionBlock)block;


//Utils
- (void)cancelAllOperations;

@end
