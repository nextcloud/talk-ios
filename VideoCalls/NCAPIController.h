//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AFNetworking.h"
#import "AFImageDownloader.h"
#import "OCCommunication.h"
#import "OCFrameworkConstants.h"
#import "NCChatMessage.h"
#import "NCDatabaseManager.h"
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
typedef void (^JoinRoomCompletionBlock)(NSString *sessionId, NSError *error, NSInteger statusCode);
typedef void (^ExitRoomCompletionBlock)(NSError *error);
typedef void (^FavoriteRoomCompletionBlock)(NSError *error);
typedef void (^NotificationLevelCompletionBlock)(NSError *error);
typedef void (^ReadOnlyCompletionBlock)(NSError *error);
typedef void (^SetLobbyStateCompletionBlock)(NSError *error);

typedef void (^GetParticipantsFromRoomCompletionBlock)(NSMutableArray *participants, NSError *error);
typedef void (^LeaveRoomCompletionBlock)(NSInteger errorCode, NSError *error);
typedef void (^ParticipantModificationCompletionBlock)(NSError *error);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error);
typedef void (^JoinCallCompletionBlock)(NSError *error);
typedef void (^PingCallCompletionBlock)(NSError *error);
typedef void (^LeaveCallCompletionBlock)(NSError *error);

typedef void (^GetChatMessagesCompletionBlock)(NSMutableArray *messages, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode);
typedef void (^SendChatMessagesCompletionBlock)(NSError *error);
typedef void (^GetMentionSuggestionsCompletionBlock)(NSMutableArray *mentions, NSError *error);

typedef void (^SendSignalingMessagesCompletionBlock)(NSError *error);
typedef void (^PullSignalingMessagesCompletionBlock)(NSDictionary *messages, NSError *error);
typedef void (^GetSignalingSettingsCompletionBlock)(NSDictionary *settings, NSError *error);

typedef void (^ReadFolderCompletionBlock)(NSArray *items, NSError *error);
typedef void (^ShareFileOrFolderCompletionBlock)(NSError *error);

typedef void (^GetUserProfileCompletionBlock)(NSDictionary *userProfile, NSError *error);

typedef void (^GetServerCapabilitiesCompletionBlock)(NSDictionary *serverCapabilities, NSError *error);
typedef void (^GetServerNotificationCompletionBlock)(NSDictionary *notification, NSError *error, NSInteger statusCode);

typedef void (^SubscribeToNextcloudServerCompletionBlock)(NSDictionary *responseDict, NSError *error);
typedef void (^UnsubscribeToNextcloudServerCompletionBlock)(NSError *error);
typedef void (^SubscribeToPushProxyCompletionBlock)(NSError *error);
typedef void (^UnsubscribeToPushProxyCompletionBlock)(NSError *error);

@interface OCURLSessionManager : AFURLSessionManager
@end

@interface NCAPIController : NSObject

@property (nonatomic, strong) NSMutableDictionary *apiSessionManagers;
@property (nonatomic, strong) NSMutableDictionary *apiUsingCookiesSessionManagers;
@property (nonatomic, strong) AFImageDownloader *imageDownloader;
@property (nonatomic, strong) AFImageDownloader *imageDownloaderNoCache;

+ (instancetype)sharedInstance;
- (void)createAPISessionManagerForAccount:(TalkAccount *)account;

// Contacts Controller
- (NSURLSessionDataTask *)getContactsForAccount:(TalkAccount *)account withSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block;
- (NSMutableDictionary *)indexedUsersFromUsersArray:(NSArray *)users;

// Rooms Controller
- (NSURLSessionDataTask *)getRoomsForAccount:(TalkAccount *)account withCompletionBlock:(GetRoomsCompletionBlock)block;
- (NSURLSessionDataTask *)getRoomForAccount:(TalkAccount *)account withToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block;
- (NSURLSessionDataTask *)getRoomForAccount:(TalkAccount *)account withId:(NSInteger)roomId withCompletionBlock:(GetRoomCompletionBlock)block;
- (NSURLSessionDataTask *)createRoomForAccount:(TalkAccount *)account with:(NSString *)invite ofType:(NCRoomType)type andName:(NSString *)roomName withCompletionBlock:(CreateRoomCompletionBlock)block;
- (NSURLSessionDataTask *)renameRoom:(NSString *)token forAccount:(TalkAccount *)account withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block;
- (NSURLSessionDataTask *)makeRoomPublic:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MakeRoomPublicCompletionBlock)block;
- (NSURLSessionDataTask *)makeRoomPrivate:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MakeRoomPrivateCompletionBlock)block;
- (NSURLSessionDataTask *)deleteRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(DeleteRoomCompletionBlock)block;
- (NSURLSessionDataTask *)setPassword:(NSString *)password toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetPasswordCompletionBlock)block;
- (NSURLSessionDataTask *)joinRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(JoinRoomCompletionBlock)block;
- (NSURLSessionDataTask *)exitRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ExitRoomCompletionBlock)block;
- (NSURLSessionDataTask *)addRoomToFavorites:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(FavoriteRoomCompletionBlock)block;
- (NSURLSessionDataTask *)removeRoomFromFavorites:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(FavoriteRoomCompletionBlock)block;
- (NSURLSessionDataTask *)setNotificationLevel:(NCRoomNotificationLevel)level forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(NotificationLevelCompletionBlock)block;
- (NSURLSessionDataTask *)setReadOnlyState:(NCRoomReadOnlyState)state forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ReadOnlyCompletionBlock)block;
- (NSURLSessionDataTask *)setLobbyState:(NCRoomLobbyState)state withTimer:(NSInteger)timer forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetLobbyStateCompletionBlock)block;

// Participants Controller
- (NSURLSessionDataTask *)getParticipantsFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetParticipantsFromRoomCompletionBlock)block;
- (NSURLSessionDataTask *)addParticipant:(NSString *)user toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeParticipant:(NSString *)user fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeGuest:(NSString *)guest fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeSelfFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveRoomCompletionBlock)block;
- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Call Controller
- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (NSURLSessionDataTask *)joinCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(JoinCallCompletionBlock)block;
- (NSURLSessionDataTask *)pingCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PingCallCompletionBlock)block;
- (NSURLSessionDataTask *)leaveCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveCallCompletionBlock)block;

// Chat Controller
- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId history:(BOOL)history includeLastMessage:(BOOL)include timeout:(BOOL)timeout forAccount:(TalkAccount *)account withCompletionBlock:(GetChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token displayName:(NSString *)displayName forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getMentionSuggestionsInRoom:(NSString *)token forString:(NSString *)string forAccount:(TalkAccount *)account withCompletionBlock:(GetMentionSuggestionsCompletionBlock)block;

// Signaling Controller
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages forAccount:(TalkAccount *)account withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesForAccount:(TalkAccount *)account withCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getSignalingSettingsForAccount:(TalkAccount *)account withCompletionBlock:(GetSignalingSettingsCompletionBlock)block;
- (NSString *)authenticationBackendUrlForAccount:(TalkAccount *)account;

// WebDAV client
- (void)readFolderForAccount:(TalkAccount *)account atPath:(NSString *)path depth:(NSString *)depth withCompletionBlock:(ReadFolderCompletionBlock)block;
- (void)shareFileOrFolderForAccount:(TalkAccount *)account atPath:(NSString *)path toRoom:(NSString *)token withCompletionBlock:(ShareFileOrFolderCompletionBlock)block;

// User avatars
- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId andSize:(NSInteger)size usingAccount:(TalkAccount *)account;

// File previews
- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height usingAccount:(TalkAccount *)account;

// User Profile
- (NSURLSessionDataTask *)getUserProfileForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileCompletionBlock)block;
- (void)saveProfileImageForAccount:(TalkAccount *)account;
- (UIImage *)userProfileImageForAccount:(TalkAccount *)account withSize:(CGSize)size;
- (void)removeProfileImageForAccount:(TalkAccount *)account;

// Server capabilities
- (NSURLSessionDataTask *)getServerCapabilitiesForServer:(NSString *)server withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;
- (NSURLSessionDataTask *)getServerCapabilitiesForAccount:(TalkAccount *)account withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;

// Server notifications
- (NSURLSessionDataTask *)getServerNotification:(NSInteger)notificationId forAccount:(TalkAccount *)account withCompletionBlock:(GetServerNotificationCompletionBlock)block;

// Push Notifications
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account toNextcloudServerWithCompletionBlock:(SubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromNextcloudServerWithCompletionBlock:(UnsubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account toPushServerWithCompletionBlock:(SubscribeToPushProxyCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromPushServerWithCompletionBlock:(UnsubscribeToPushProxyCompletionBlock)block;


@end
