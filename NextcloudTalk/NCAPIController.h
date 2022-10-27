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

#import <Foundation/Foundation.h>

#import "AFNetworking.h"
#import "AFImageDownloader.h"
#import "NCPoll.h"
#import "NCRoom.h"
#import "NCUser.h"

@class NCCommunicationFile;

typedef void (^GetContactsCompletionBlock)(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error);
typedef void (^GetContactsWithPhoneNumbersCompletionBlock)(NSDictionary *contacts, NSError *error);

typedef void (^GetRoomsCompletionBlock)(NSArray *rooms, NSError *error, NSInteger statusCode);
typedef void (^GetRoomCompletionBlock)(NSDictionary *roomDict, NSError *error);
typedef void (^CreateRoomCompletionBlock)(NSString *token, NSError *error);
typedef void (^RenameRoomCompletionBlock)(NSError *error);
typedef void (^MakeRoomPublicCompletionBlock)(NSError *error);
typedef void (^MakeRoomPrivateCompletionBlock)(NSError *error);
typedef void (^DeleteRoomCompletionBlock)(NSError *error);
typedef void (^SetPasswordCompletionBlock)(NSError *error, NSString *errorDescription);
typedef void (^JoinRoomCompletionBlock)(NSString *sessionId, NSError *error, NSInteger statusCode);
typedef void (^ExitRoomCompletionBlock)(NSError *error);
typedef void (^FavoriteRoomCompletionBlock)(NSError *error);
typedef void (^NotificationLevelCompletionBlock)(NSError *error);
typedef void (^ReadOnlyCompletionBlock)(NSError *error);
typedef void (^SetLobbyStateCompletionBlock)(NSError *error);
typedef void (^SetSIPStateCompletionBlock)(NSError *error);
typedef void (^ListableCompletionBlock)(NSError *error);
typedef void (^MessageExpirationCompletionBlock)(NSError *error);

typedef void (^GetParticipantsFromRoomCompletionBlock)(NSMutableArray *participants, NSError *error);
typedef void (^LeaveRoomCompletionBlock)(NSInteger errorCode, NSError *error);
typedef void (^ParticipantModificationCompletionBlock)(NSError *error);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error);
typedef void (^JoinCallCompletionBlock)(NSError *error, NSInteger statusCode);
typedef void (^LeaveCallCompletionBlock)(NSError *error);

typedef void (^GetChatMessagesCompletionBlock)(NSArray *messages, NSInteger lastKnownMessage, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode);
typedef void (^SendChatMessagesCompletionBlock)(NSError *error);
typedef void (^GetMentionSuggestionsCompletionBlock)(NSMutableArray *mentions, NSError *error);
typedef void (^DeleteChatMessageCompletionBlock)(NSDictionary *messageDict, NSError *error, NSInteger statusCode);
typedef void (^ClearChatHistoryCompletionBlock)(NSDictionary *messageDict, NSError *error, NSInteger statusCode);
typedef void (^GetSharedItemsOverviewCompletionBlock)(NSDictionary *sharedItemsOverview, NSError *error, NSInteger statusCode);
typedef void (^GetSharedItemsCompletionBlock)(NSArray *sharedItems, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode);

typedef void (^MessageReactionCompletionBlock)(NSDictionary *reactionsDict, NSError *error, NSInteger statusCode);

typedef void (^PollCompletionBlock)(NCPoll *poll, NSError *error, NSInteger statusCode);

typedef void (^SendSignalingMessagesCompletionBlock)(NSError *error);
typedef void (^PullSignalingMessagesCompletionBlock)(NSDictionary *messages, NSError *error);
typedef void (^GetSignalingSettingsCompletionBlock)(NSDictionary *settings, NSError *error);

typedef void (^SetReadStatusPrivacySettingCompletionBlock)(NSError *error);

typedef void (^ReadFolderCompletionBlock)(NSArray *items, NSError *error);
typedef void (^ShareFileOrFolderCompletionBlock)(NSError *error);
typedef void (^GetFileByFileIdCompletionBlock)(NCCommunicationFile *file, NSInteger error, NSString *errorDescription);
typedef void (^GetFileUniqueNameCompletionBlock)(NSString *fileServerURL, NSString *fileServerPath, NSInteger errorCode, NSString *errorDescription);
typedef void (^CheckAttachmentFolderCompletionBlock)(BOOL created, NSInteger errorCode);

typedef void (^GetUserActionsCompletionBlock)(NSDictionary *userActions, NSError *error);

typedef void (^GetUserAvatarImageForUserCompletionBlock)(UIImage *image, NSError *error);

typedef void (^GetUserProfileCompletionBlock)(NSDictionary *userProfile, NSError *error);
typedef void (^GetUserProfileEditableFieldsCompletionBlock)(NSArray *userProfileEditableFields, NSError *error);
typedef void (^SetUserProfileFieldCompletionBlock)(NSError *error, NSInteger statusCode);

typedef void (^GetUserStatusCompletionBlock)(NSDictionary *userStatus, NSError *error);
typedef void (^SetUserStatusCompletionBlock)(NSError *error);

typedef void (^GetServerCapabilitiesCompletionBlock)(NSDictionary *serverCapabilities, NSError *error);
typedef void (^GetServerNotificationCompletionBlock)(NSDictionary *notification, NSError *error, NSInteger statusCode);
typedef void (^GetServerNotificationsCompletionBlock)(NSArray *notifications, NSString *ETag, NSError *error);

typedef void (^SubscribeToNextcloudServerCompletionBlock)(NSDictionary *responseDict, NSError *error);
typedef void (^UnsubscribeToNextcloudServerCompletionBlock)(NSError *error);
typedef void (^SubscribeToPushProxyCompletionBlock)(NSError *error);
typedef void (^UnsubscribeToPushProxyCompletionBlock)(NSError *error);

typedef void (^GetReferenceForUrlStringCompletionBlock)(NSDictionary *references, NSError *error);

extern NSInteger const APIv1;
extern NSInteger const APIv2;
extern NSInteger const APIv3;
extern NSInteger const APIv4;
extern NSInteger const kReceivedChatMessagesLimit;

@interface OCURLSessionManager : AFURLSessionManager
@end

@interface NCAPIController : NSObject

@property (nonatomic, strong) NSMutableDictionary *apiSessionManagers;
@property (nonatomic, strong) AFImageDownloader *imageDownloader;
@property (nonatomic, strong) AFImageDownloader *imageDownloaderNoCache;

+ (instancetype)sharedInstance;
- (void)createAPISessionManagerForAccount:(TalkAccount *)account;
- (void)setupNCCommunicationForAccount:(TalkAccount *)account;
- (NSInteger)conversationAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)callAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)chatAPIVersionForAccount:(TalkAccount *)accounts;
- (NSInteger)reactionsAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)pollsAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)signalingAPIVersionForAccount:(TalkAccount *)account;
- (NSString *)filesPathForAccount:(TalkAccount *)account;

// Contacts Controller
- (NSURLSessionDataTask *)searchContactsForAccount:(TalkAccount *)account withPhoneNumbers:(NSDictionary *)phoneNumbers andCompletionBlock:(GetContactsWithPhoneNumbersCompletionBlock)block;
- (NSURLSessionDataTask *)getContactsForAccount:(TalkAccount *)account forRoom:(NSString *)room groupRoom:(BOOL)groupRoom withSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block;

// Rooms Controller
- (NSURLSessionDataTask *)getRoomsForAccount:(TalkAccount *)account updateStatus:(BOOL)updateStatus withCompletionBlock:(GetRoomsCompletionBlock)block;
- (NSURLSessionDataTask *)getRoomForAccount:(TalkAccount *)account withToken:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block;
- (NSURLSessionDataTask *)getListableRoomsForAccount:(TalkAccount *)account withSearchTerm:(NSString *)searchTerm andCompletionBlock:(GetRoomsCompletionBlock)block;
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
- (NSURLSessionDataTask *)setCallNotificationEnabled:(BOOL)enabled forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(NotificationLevelCompletionBlock)block;
- (NSURLSessionDataTask *)setReadOnlyState:(NCRoomReadOnlyState)state forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ReadOnlyCompletionBlock)block;
- (NSURLSessionDataTask *)setLobbyState:(NCRoomLobbyState)state withTimer:(NSInteger)timer forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetLobbyStateCompletionBlock)block;
- (NSURLSessionDataTask *)setSIPState:(NCRoomSIPState)state forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SetSIPStateCompletionBlock)block;
- (NSURLSessionDataTask *)setListableScope:(NCRoomListableScope)scope forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ListableCompletionBlock)block;
- (NSURLSessionDataTask *)setMessageExpiration:(NCMessageExpiration)messageExpiration forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageExpirationCompletionBlock)block;

// Participants Controller
- (NSURLSessionDataTask *)getParticipantsFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetParticipantsFromRoomCompletionBlock)block;
- (NSURLSessionDataTask *)addParticipant:(NSString *)participant ofType:(NSString *)type toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeAttendee:(NSInteger)attendeeId fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeParticipant:(NSString *)user fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeGuest:(NSString *)guest fromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)removeSelfFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveRoomCompletionBlock)block;
- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)resendInvitationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Call Controller
- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (NSURLSessionDataTask *)joinCall:(NSString *)token withCallFlags:(NSInteger)flags silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(JoinCallCompletionBlock)block;
- (NSURLSessionDataTask *)leaveCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(LeaveCallCompletionBlock)block;
- (NSURLSessionDataTask *)sendCallNotificationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Chat Controller
- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId history:(BOOL)history includeLastMessage:(BOOL)include timeout:(BOOL)timeout lastCommonReadMessage:(NSInteger)lastCommonReadMessage setReadMarker:(BOOL)setReadMarker forAccount:(TalkAccount *)account withCompletionBlock:(GetChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token displayName:(NSString *)displayName replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getMentionSuggestionsInRoom:(NSString *)token forString:(NSString *)string forAccount:(TalkAccount *)account withCompletionBlock:(GetMentionSuggestionsCompletionBlock)block;
- (NSURLSessionDataTask *)deleteChatMessageInRoom:(NSString *)token withMessageId:(NSInteger)messageId forAccount:(TalkAccount *)account withCompletionBlock:(DeleteChatMessageCompletionBlock)block;
- (NSURLSessionDataTask *)shareRichObject:(NSDictionary *)richObject inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)clearChatHistoryInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ClearChatHistoryCompletionBlock)block;
- (NSURLSessionDataTask *)setChatReadMarker:(NSInteger)lastReadMessage inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)markChatAsUnreadInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getSharedItemsOverviewInRoom:(NSString *)token withLimit:(NSInteger)limit forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsOverviewCompletionBlock)block;
- (NSURLSessionDataTask *)getSharedItemsOfType:(NSString *)objectType fromLastMessageId:(NSInteger)messageId withLimit:(NSInteger)limit inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsCompletionBlock)block;

// Reactions Controller
- (NSURLSessionDataTask *)addReaction:(NSString *)reaction toMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;
- (NSURLSessionDataTask *)removeReaction:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;
- (NSURLSessionDataTask *)getReactions:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;

// Polls Controller
- (NSURLSessionDataTask *)createPollWithQuestion:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)getPollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)voteOnPollWithId:(NSInteger)pollId inRoom:(NSString *)token withOptions:(NSArray *)options forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)closePollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;

// Signaling Controller
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getSignalingSettingsForAccount:(TalkAccount *)account withCompletionBlock:(GetSignalingSettingsCompletionBlock)block;
- (NSString *)authenticationBackendUrlForAccount:(TalkAccount *)account;

// Settings Controller
- (NSURLSessionDataTask *)setReadStatusPrivacySettingEnabled:(BOOL)enabled forAccount:(TalkAccount *)account withCompletionBlock:(SetReadStatusPrivacySettingCompletionBlock)block;

// DAV client
- (void)readFolderForAccount:(TalkAccount *)account atPath:(NSString *)path depth:(NSString *)depth withCompletionBlock:(ReadFolderCompletionBlock)block;
- (void)shareFileOrFolderForAccount:(TalkAccount *)account atPath:(NSString *)path toRoom:(NSString *)token talkMetaData:(NSDictionary *)talkMetaData withCompletionBlock:(ShareFileOrFolderCompletionBlock)block;
- (void)getFileByFileId:(TalkAccount *)account fileId:(NSString *)fileId
    withCompletionBlock:(GetFileByFileIdCompletionBlock)block;
- (void)uniqueNameForFileUploadWithName:(NSString *)fileName originalName:(BOOL)isOriginalName forAccount:(TalkAccount *)account withCompletionBlock:(GetFileUniqueNameCompletionBlock)block;
- (void)checkOrCreateAttachmentFolderForAccount:(TalkAccount *)account withCompletionBlock:(CheckAttachmentFolderCompletionBlock)block;

// User avatars
- (NSURLRequest *)createAvatarRequestForUser:(NSString *)userId withStyle:(UIUserInterfaceStyle) style andSize:(NSInteger)size usingAccount:(TalkAccount *)account;
- (void)getUserAvatarForUser:(NSString *)userId andSize:(NSInteger)size usingAccount:(TalkAccount *)account withCompletionBlock:(GetUserAvatarImageForUserCompletionBlock)block;

// User actions
- (NSURLSessionDataTask *)getUserActionsForUser:(NSString *)userId usingAccount:(TalkAccount *)account withCompletionBlock:(GetUserActionsCompletionBlock)block;

// File previews
- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height usingAccount:(TalkAccount *)account;
- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId withMaxHeight:(NSInteger) height usingAccount:(TalkAccount *)account;

// User Profile
- (NSURLSessionDataTask *)getUserProfileForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileCompletionBlock)block;
- (NSURLSessionDataTask *)getUserProfileEditableFieldsForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileEditableFieldsCompletionBlock)block;
- (NSURLSessionDataTask *)setUserProfileField:(NSString *)field withValue:(NSString*)value forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (NSURLSessionDataTask *)removeUserProfileImageForAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (NSURLSessionDataTask *)setUserProfileImage:(UIImage *)image forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (void)saveProfileImageForAccount:(TalkAccount *)account;
- (UIImage *)userProfileImageForAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style andSize:(CGSize)size;
- (void)removeProfileImageForAccount:(TalkAccount *)account;

// User Status
- (NSURLSessionDataTask *)getUserStatusForAccount:(TalkAccount *)account withCompletionBlock:(GetUserStatusCompletionBlock)block;
- (NSURLSessionDataTask *)setUserStatus:(NSString *)status forAccount:(TalkAccount *)account withCompletionBlock:(SetUserStatusCompletionBlock)block;

// Server capabilities
- (NSURLSessionDataTask *)getServerCapabilitiesForServer:(NSString *)server withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;
- (NSURLSessionDataTask *)getServerCapabilitiesForAccount:(TalkAccount *)account withCompletionBlock:(GetServerCapabilitiesCompletionBlock)block;

// Server notifications
- (NSURLSessionDataTask *)getServerNotification:(NSInteger)notificationId forAccount:(TalkAccount *)account withCompletionBlock:(GetServerNotificationCompletionBlock)block;
- (NSURLSessionDataTask *)getServerNotificationsForAccount:(TalkAccount *)account withLastETag:(NSString *)lastETag withCompletionBlock:(GetServerNotificationsCompletionBlock)block;

// Push Notifications
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account withPublicKey:(NSData *)publicKey toNextcloudServerWithCompletionBlock:(SubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromNextcloudServerWithCompletionBlock:(UnsubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account toPushServerWithCompletionBlock:(SubscribeToPushProxyCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromPushServerWithCompletionBlock:(UnsubscribeToPushProxyCompletionBlock)block;


- (NSURLSessionDataTask *)getReferenceForUrlString:(NSString *)url forAccount:(TalkAccount *)account withCompletionBlock:(GetReferenceForUrlStringCompletionBlock)block;
- (NSURLRequest *)createReferenceThumbnailRequestForUrl:(NSString *)url;

@end
