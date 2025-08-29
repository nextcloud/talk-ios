/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "AFNetworking.h"
#import "NCPoll.h"
#import "NCRoom.h"
#import "NCUser.h"

@class NKFile;
@class NCNotificationAction;

@class SDWebImageCombinedOperation;
@class SDWebImageDownloaderRequestModifier;

typedef void (^GetContactsCompletionBlock)(NSArray *indexes, NSMutableDictionary *contacts, NSMutableArray *contactList, NSError *error);
typedef void (^GetContactsWithPhoneNumbersCompletionBlock)(NSDictionary *contacts, NSError *error);
typedef void (^SearchUsersCompletionBlock)(NSArray *indexes, NSMutableDictionary *users, NSMutableArray *userList, NSError *error);

typedef void (^GetRoomCompletionBlock)(NSDictionary *roomDict, NSError *error);

typedef void (^PrepareSwitchRoomCompletionBlock)(NSError *error);
typedef void (^RequestAssistanceCompletionBlock)(NSError *error);

typedef void (^LeaveRoomCompletionBlock)(NSInteger errorCode, NSError *error);
typedef void (^ParticipantModificationCompletionBlock)(NSError *error);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error, NSInteger statusCode);
typedef void (^JoinCallCompletionBlock)(NSError *error, NSInteger statusCode);
typedef void (^LeaveCallCompletionBlock)(NSError *error);

typedef void (^GetChatMessagesCompletionBlock)(NSArray *messages, NSInteger lastKnownMessage, NSInteger lastCommonReadMessage, NSError *error, NSInteger statusCode);
typedef void (^SendChatMessagesCompletionBlock)(NSError *error);
typedef void (^DeleteChatMessageCompletionBlock)(NSDictionary *messageDict, NSError *error, NSInteger statusCode);
typedef void (^EditChatMessageCompletionBlock)(NSDictionary *messageDict, NSError *error, NSInteger statusCode);
typedef void (^ClearChatHistoryCompletionBlock)(NSDictionary *messageDict, NSError *error, NSInteger statusCode);
typedef void (^GetSharedItemsOverviewCompletionBlock)(NSDictionary *sharedItemsOverview, NSError *error, NSInteger statusCode);
typedef void (^GetSharedItemsCompletionBlock)(NSArray *sharedItems, NSInteger lastKnownMessage, NSError *error, NSInteger statusCode);
typedef void (^GetMessageContextInRoomCompletionBlock)(NSArray *messages, NSError *error, NSInteger statusCode);

typedef void (^GetTranslationsCompletionBlock)(NSArray *languages, BOOL languageDetection, NSError *error, NSInteger statusCode);
typedef void (^MessageTranslationCompletionBlock)(NSDictionary *translationDict, NSError *error, NSInteger statusCode);

typedef void (^MessageReactionCompletionBlock)(NSDictionary *reactionsDict, NSError *error, NSInteger statusCode);

typedef void (^PollCompletionBlock)(NCPoll *poll, NSError *error, NSInteger statusCode);
typedef void (^PollDraftsCompletionBlock)(NSArray *polls, NSError *error, NSInteger statusCode);

typedef void (^SendSignalingMessagesCompletionBlock)(NSError *error);
typedef void (^PullSignalingMessagesCompletionBlock)(NSDictionary *messages, NSError *error);

typedef void (^SetReadStatusPrivacySettingCompletionBlock)(NSError *error);
typedef void (^SetTypingPrivacySettingCompletionBlock)(NSError *error);

typedef void (^ReadFolderCompletionBlock)(NSArray *items, NSError *error);
typedef void (^ShareFileOrFolderCompletionBlock)(NSError *error);
typedef void (^GetFileUniqueNameCompletionBlock)(NSString *fileServerURL, NSString *fileServerPath, NSInteger errorCode, NSString *errorDescription);
typedef void (^CheckAttachmentFolderCompletionBlock)(BOOL created, NSInteger errorCode);

typedef void (^GetUserActionsCompletionBlock)(NSDictionary *userActions, NSError *error);

typedef void (^GetUserAvatarImageForUserCompletionBlock)(UIImage *image, NSError *error);
typedef void (^GetFederatedUserAvatarImageForUserCompletionBlock)(UIImage *image, NSError *error);

typedef void (^GetAvatarForConversationWithImageCompletionBlock)(UIImage *image, NSError *error);
typedef void (^SetAvatarForConversationWithImageCompletionBlock)(NSError *error);
typedef void (^RemoveAvatarForConversationWithImageCompletionBlock)(NSError *error);

typedef void (^GetPreviewForFileCompletionBlock)(UIImage *image, NSString *fileId, NSError *error);

typedef void (^GetUserProfileCompletionBlock)(NSDictionary *userProfile, NSError *error);
typedef void (^GetUserProfileEditableFieldsCompletionBlock)(NSArray *userProfileEditableFields, NSError *error);
typedef void (^SetUserProfileFieldCompletionBlock)(NSError *error, NSInteger statusCode);

typedef void (^GetUserStatusCompletionBlock)(NSDictionary *userStatus, NSError *error);
typedef void (^SetUserStatusCompletionBlock)(NSError *error);

typedef void (^GetAppIdCompletionBlock)(NSString *appId, NSError *error);

typedef void (^GetWipeStatusCompletionBlock)(BOOL wipe, NSError *error);
typedef void (^ConfirmWipeCompletionBlock)(NSError *error);

typedef void (^GetServerCapabilitiesCompletionBlock)(NSDictionary *serverCapabilities, NSError *error);

typedef void (^GetServerNotificationCompletionBlock)(NSDictionary *notification, NSError *error, NSInteger statusCode);
typedef void (^GetServerNotificationsCompletionBlock)(NSArray *notifications, NSString *ETag, NSString *userStatus, NSError *error);
typedef void (^ExecuteNotificationActionCompletionBlock)(NSError *error);
typedef void (^CheckNotificationExistanceBlock)(NSArray *notificationIds, NSError *error);

typedef void (^SubscribeToNextcloudServerCompletionBlock)(NSDictionary *responseDict, NSError *error);
typedef void (^UnsubscribeToNextcloudServerCompletionBlock)(NSError *error);
typedef void (^SubscribeToPushProxyCompletionBlock)(NSError *error);
typedef void (^UnsubscribeToPushProxyCompletionBlock)(NSError *error);

typedef void (^GetReferenceForUrlStringCompletionBlock)(NSDictionary *references, NSError *error);

typedef void (^StartRecordingCompletionBlock)(NSError *error);
typedef void (^StopRecordingCompletionBlock)(NSError *error);
typedef void (^DismissStoredRecordingNotificationCompletionBlock)(NSError *error);
typedef void (^ShareStoredRecordingCompletionBlock)(NSError *error);

typedef void (^SetReminderForMessage)(NSError *error);
typedef void (^DeleteReminderForMessage)(NSError *error);
typedef void (^GetReminderForMessage)(NSDictionary *responseDict, NSError *error);

extern NSInteger const APIv1;
extern NSInteger const APIv2;
extern NSInteger const APIv3;
extern NSInteger const APIv4;
extern NSInteger const kReceivedChatMessagesLimit;

@interface OCURLSessionManager : AFURLSessionManager
@end

@interface NCAPIController : NSObject

@property (nonatomic, strong) NSMutableDictionary *apiSessionManagers;
@property (nonatomic, strong) NSMutableDictionary *longPollingApiSessionManagers;
@property (nonatomic, strong) NSMutableDictionary *calDAVSessionManagers;

+ (instancetype)sharedInstance;
- (void)createAPISessionManagerForAccount:(TalkAccount *)account;
- (void)removeAPISessionManagerForAccount:(TalkAccount *)account;
- (void)setupNCCommunicationForAccount:(TalkAccount *)account;
- (NSInteger)conversationAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)callAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)chatAPIVersionForAccount:(TalkAccount *)accounts;
- (NSInteger)reactionsAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)pollsAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)breakoutRoomsAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)signalingAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)federationAPIVersionForAccount:(TalkAccount *)account;
- (NSInteger)banAPIVersionForAccount:(TalkAccount *)account;
- (NSString *)filesPathForAccount:(TalkAccount *)account;
- (SDWebImageDownloaderRequestModifier *)getRequestModifierForAccount:(TalkAccount *)account;

// App Store
- (NSURLSessionDataTask *)getAppStoreAppIdWithCompletionBlock:(GetAppIdCompletionBlock)block;

// Remote Wipe
- (NSURLSessionDataTask *)checkWipeStatusForAccount:(TalkAccount *)account withCompletionBlock:(GetWipeStatusCompletionBlock)block;
- (NSURLSessionDataTask *)confirmWipeForAccount:(TalkAccount *)account withCompletionBlock:(GetWipeStatusCompletionBlock)block;

// Contacts Controller
- (NSURLSessionDataTask *)searchContactsForAccount:(TalkAccount *)account withPhoneNumbers:(NSDictionary *)phoneNumbers andCompletionBlock:(GetContactsWithPhoneNumbersCompletionBlock)block;
- (NSURLSessionDataTask *)getContactsForAccount:(TalkAccount *)account forRoom:(NSString *)room groupRoom:(BOOL)groupRoom withSearchParam:(NSString *)search andCompletionBlock:(GetContactsCompletionBlock)block;
- (NSURLSessionDataTask *)searchUsersForAccount:(TalkAccount *)account withSearchParam:(NSString *)search andCompletionBlock:(SearchUsersCompletionBlock)block;

// Breakout Rooms Controller
- (NSURLSessionDataTask *)requestAssistanceInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(RequestAssistanceCompletionBlock)block;
- (NSURLSessionDataTask *)stopRequestingAssistanceInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(RequestAssistanceCompletionBlock)block;

// Participants Controller
- (NSURLSessionDataTask *)promoteParticipant:(NSString *)user toModeratorOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)demoteModerator:(NSString *)moderator toParticipantOfRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;
- (NSURLSessionDataTask *)resendInvitationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Call Controller
- (NSURLSessionDataTask *)getPeersForCall:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (NSURLSessionDataTask *)joinCall:(NSString *)token withCallFlags:(NSInteger)flags silently:(BOOL)silently silentFor:(NSArray *)silentFor recordingConsent:(BOOL)recordingConsent forAccount:(TalkAccount *)account withCompletionBlock:(JoinCallCompletionBlock)block;
- (NSURLSessionDataTask *)leaveCall:(NSString *)token forAllParticipants:(BOOL)allParticipants forAccount:(TalkAccount *)account withCompletionBlock:(LeaveCallCompletionBlock)block;
- (NSURLSessionDataTask *)sendCallNotificationToParticipant:(NSString *)participant inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ParticipantModificationCompletionBlock)block;

// Chat Controller
- (NSURLSessionDataTask *)receiveChatMessagesOfRoom:(NSString *)token fromLastMessageId:(NSInteger)messageId inThread:(NSInteger)threadId history:(BOOL)history includeLastMessage:(BOOL)include timeout:(BOOL)timeout lastCommonReadMessage:(NSInteger)lastCommonReadMessage setReadMarker:(BOOL)setReadMarker markNotificationsAsRead:(BOOL)markNotificationsAsRead forAccount:(TalkAccount *)account withCompletionBlock:(GetChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)sendChatMessage:(NSString *)message toRoom:(NSString *)token threadTitle:(NSString *)threadTitle replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId silently:(BOOL)silently forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)deleteChatMessageInRoom:(NSString *)token withMessageId:(NSInteger)messageId forAccount:(TalkAccount *)account withCompletionBlock:(DeleteChatMessageCompletionBlock)block;
- (NSURLSessionDataTask *)editChatMessageInRoom:(NSString *)token withMessageId:(NSInteger)messageId withMessage:(NSString *)message forAccount:(TalkAccount *)account withCompletionBlock:(EditChatMessageCompletionBlock)block;
- (NSURLSessionDataTask *)shareRichObject:(NSDictionary *)richObject inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)clearChatHistoryInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ClearChatHistoryCompletionBlock)block;
- (NSURLSessionDataTask *)setChatReadMarker:(NSInteger)lastReadMessage inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)markChatAsUnreadInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendChatMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)getSharedItemsOverviewInRoom:(NSString *)token withLimit:(NSInteger)limit forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsOverviewCompletionBlock)block;
- (NSURLSessionDataTask *)getSharedItemsOfType:(NSString *)objectType fromLastMessageId:(NSInteger)messageId withLimit:(NSInteger)limit inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(GetSharedItemsCompletionBlock)block;
- (NSURLSessionDataTask *)getMessageContextInRoom:(NSString *)token forMessageId:(NSInteger)messageId withLimit:(NSInteger)limit forAccount:(TalkAccount *)account withCompletionBlock:(GetMessageContextInRoomCompletionBlock)block;

// Translations
- (NSURLSessionDataTask *)getAvailableTranslationsForAccount:(TalkAccount *)account withCompletionBlock:(GetTranslationsCompletionBlock)block;
- (NSURLSessionDataTask *)translateMessage:(NSString *)message from:(NSString *)from to:(NSString *)to forAccount:(TalkAccount *)account withCompletionBlock:(MessageTranslationCompletionBlock)block;

// Reactions Controller
- (NSURLSessionDataTask *)addReaction:(NSString *)reaction toMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;
- (NSURLSessionDataTask *)removeReaction:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;
- (NSURLSessionDataTask *)getReactions:(NSString *)reaction fromMessage:(NSInteger)messageId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(MessageReactionCompletionBlock)block;

// Polls Controller
- (NSURLSessionDataTask *)createPollWithQuestion:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token asDraft:(BOOL)asDraft forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)getPollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)editPollDraftWithId:(NSInteger)draftId question:(NSString *)question options:(NSArray *)options resultMode:(NCPollResultMode)resultMode maxVotes:(NSInteger)maxVotes inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)getPollDraftsInRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollDraftsCompletionBlock)block;
- (NSURLSessionDataTask *)voteOnPollWithId:(NSInteger)pollId inRoom:(NSString *)token withOptions:(NSArray *)options forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;
- (NSURLSessionDataTask *)closePollWithId:(NSInteger)pollId inRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PollCompletionBlock)block;

// Signaling Controller
- (NSURLSessionDataTask *)sendSignalingMessages:(NSString *)messages toRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(SendSignalingMessagesCompletionBlock)block;
- (NSURLSessionDataTask *)pullSignalingMessagesFromRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(PullSignalingMessagesCompletionBlock)block;
- (NSString *)authenticationBackendUrlForAccount:(TalkAccount *)account;

// Settings Controller
- (NSURLSessionDataTask *)setReadStatusPrivacySettingEnabled:(BOOL)enabled forAccount:(TalkAccount *)account withCompletionBlock:(SetReadStatusPrivacySettingCompletionBlock)block;
- (NSURLSessionDataTask *)setTypingPrivacySettingEnabled:(BOOL)enabled forAccount:(TalkAccount *)account withCompletionBlock:(SetTypingPrivacySettingCompletionBlock)block;

// DAV client
- (void)readFolderForAccount:(TalkAccount *)account atPath:(NSString *)path depth:(NSString *)depth withCompletionBlock:(ReadFolderCompletionBlock)block;
- (void)shareFileOrFolderForAccount:(TalkAccount *)account atPath:(NSString *)path toRoom:(NSString *)token talkMetaData:(NSDictionary *)talkMetaData referenceId:(NSString *)referenceId withCompletionBlock:(ShareFileOrFolderCompletionBlock)block;
- (void)uniqueNameForFileUploadWithName:(NSString *)fileName originalName:(BOOL)isOriginalName forAccount:(TalkAccount *)account withCompletionBlock:(GetFileUniqueNameCompletionBlock)block;
- (void)checkOrCreateAttachmentFolderForAccount:(TalkAccount *)account withCompletionBlock:(CheckAttachmentFolderCompletionBlock)block;

// User avatars
- (SDWebImageCombinedOperation *)getUserAvatarForUser:(NSString *)userId usingAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetUserAvatarImageForUserCompletionBlock)block;
- (SDWebImageCombinedOperation *)getFederatedUserAvatarForUser:(NSString *)userId inRoom:(NSString *)token usingAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetFederatedUserAvatarImageForUserCompletionBlock)block;

// Conversation avatars
- (SDWebImageCombinedOperation *)getAvatarForRoom:(NCRoom *)room withStyle:(UIUserInterfaceStyle)style withCompletionBlock:(GetAvatarForConversationWithImageCompletionBlock)block;
- (NSURLSessionDataTask *)setAvatarForRoom:(NCRoom *)room withImage:(UIImage *)image withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block;
- (NSURLSessionDataTask *)setAvatarForRoomWithToken:(NSString *)token image:(UIImage *)image account:(TalkAccount *)account withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block;
- (NSURLSessionDataTask *)setEmojiAvatarForRoom:(NCRoom *)room withEmoji:(NSString *)emoji andColor:(NSString *)color withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block;
- (NSURLSessionDataTask *)setEmojiAvatarForRoomWithToken:(NSString *)token withEmoji:(NSString *)emoji andColor:(NSString *)color account:(TalkAccount *)account withCompletionBlock:(SetAvatarForConversationWithImageCompletionBlock)block;
- (NSURLSessionDataTask *)removeAvatarForRoom:(NCRoom *)room withCompletionBlock:(RemoveAvatarForConversationWithImageCompletionBlock)block;

// User actions
- (NSURLSessionDataTask *)getUserActionsForUser:(NSString *)userId usingAccount:(TalkAccount *)account withCompletionBlock:(GetUserActionsCompletionBlock)block;

// File previews
- (SDWebImageCombinedOperation *)getPreviewForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height usingAccount:(TalkAccount *)account withCompletionBlock:(GetPreviewForFileCompletionBlock)block;

// User Profile
- (NSURLSessionDataTask *)getUserProfileForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileCompletionBlock)block;
- (NSURLSessionDataTask *)getUserProfileEditableFieldsForAccount:(TalkAccount *)account withCompletionBlock:(GetUserProfileEditableFieldsCompletionBlock)block;
- (NSURLSessionDataTask *)setUserProfileField:(NSString *)field withValue:(NSString*)value forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (NSURLSessionDataTask *)removeUserProfileImageForAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (NSURLSessionDataTask *)setUserProfileImage:(UIImage *)image forAccount:(TalkAccount *)account withCompletionBlock:(SetUserProfileFieldCompletionBlock)block;
- (void)saveProfileImageForAccount:(TalkAccount *)account;
- (UIImage *)userProfileImageForAccount:(TalkAccount *)account withStyle:(UIUserInterfaceStyle)style;
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
- (void)executeNotificationAction:(NCNotificationAction *)action forAccount:(TalkAccount *)account withCompletionBlock:(ExecuteNotificationActionCompletionBlock)block;
- (NSURLSessionDataTask *)checkNotificationExistance:(NSArray *)notificationIds forAccount:(TalkAccount *)account withCompletionBlock:(CheckNotificationExistanceBlock)block;

// Push Notifications
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account withPublicKey:(NSData *)publicKey toNextcloudServerWithCompletionBlock:(SubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromNextcloudServerWithCompletionBlock:(UnsubscribeToNextcloudServerCompletionBlock)block;
- (NSURLSessionDataTask *)subscribeAccount:(TalkAccount *)account toPushServerWithCompletionBlock:(SubscribeToPushProxyCompletionBlock)block;
- (NSURLSessionDataTask *)unsubscribeAccount:(TalkAccount *)account fromPushServerWithCompletionBlock:(UnsubscribeToPushProxyCompletionBlock)block;

// Reference data
- (NSURLSessionDataTask *)getReferenceForUrlString:(NSString *)url forAccount:(TalkAccount *)account withCompletionBlock:(GetReferenceForUrlStringCompletionBlock)block;

// Recording
- (NSURLSessionDataTask *)startRecording:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(StartRecordingCompletionBlock)block;
- (NSURLSessionDataTask *)stopRecording:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(StopRecordingCompletionBlock)block;
- (NSURLSessionDataTask *)dismissStoredRecordingNotificationWithTimestamp:(NSString *)timestamp forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(DismissStoredRecordingNotificationCompletionBlock)block;
- (NSURLSessionDataTask *)shareStoredRecordingWithTimestamp:(NSString *)timestamp withFileId:(NSString *)fileId forRoom:(NSString *)token forAccount:(TalkAccount *)account withCompletionBlock:(ShareStoredRecordingCompletionBlock)block;

// Remind me later
- (NSURLSessionDataTask *)setReminderForMessage:(NCChatMessage *)message withTimestamp:(NSString *)timestamp withCompletionBlock:(SetReminderForMessage)block;
- (NSURLSessionDataTask *)deleteReminderForMessage:(NCChatMessage *)message withCompletionBlock:(DeleteReminderForMessage)block;
- (NSURLSessionDataTask *)getReminderForMessage:(NCChatMessage *)message withCompletionBlock:(GetReminderForMessage)block;

// Internal method exposed for swift extension
- (NSString * _Nonnull)getRequestURLForConversationEndpoint:(NSString *_Nonnull)endpoint forAccount:(TalkAccount *_Nonnull)account;
- (NSString * _Nonnull)getRequestURLForEndpoint:(NSString *_Nonnull)endpoint withAPIVersion:(NSInteger)apiVersion forAccount:(TalkAccount *_Nonnull)account;
- (NSDictionary * _Nullable)getResponseHeaders:(NSURLResponse *_Nonnull)response;
- (void)checkResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account;
- (NSInteger)getResponseStatusCode:(NSURLResponse *)response;
- (void)checkResponseStatusCode:(NSInteger)statusCode forAccount:(TalkAccount *)account;
- (void)checkProxyResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account forRoom:(NSString *)token;

@end
