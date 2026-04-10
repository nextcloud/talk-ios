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
@class NCAPISessionManager;

@class SDWebImageCombinedOperation;
@class SDWebImageDownloaderRequestModifier;

typedef void (^LeaveCallCompletionBlock)(NSError *error);

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

extern NSInteger const APIv1;
extern NSInteger const APIv2;
extern NSInteger const APIv3;
extern NSInteger const APIv4;
extern NSInteger const kReceivedChatMessagesLimit;
extern NSString * const kDavEndpoint;
extern NSString * const kNCOCSAPIVersion;
extern NSString * const kNCSpreedAPIVersionBase;

@interface NCAPIController : NSObject

@property (nonatomic, strong) NCAPISessionManager *defaultAPISessionManager;
@property (nonatomic, strong) NSMutableDictionary *apiSessionManagers;
@property (nonatomic, strong) NSMutableDictionary *longPollingApiSessionManagers;
@property (nonatomic, strong) NSMutableDictionary *calDAVSessionManagers;

+ (instancetype)sharedInstance;
- (void)createAPISessionManagerForAccount:(TalkAccount *)account;
- (void)removeAPISessionManagerForAccount:(TalkAccount *)account;
- (void)setupNCCommunicationForAccount:(TalkAccount *)account;
- (SDWebImageDownloaderRequestModifier *)getRequestModifierForAccount:(TalkAccount *)account;

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

// Internal method exposed for swift extension
- (void)checkResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account;
- (NSInteger)getResponseStatusCode:(NSURLResponse *)response;
- (void)checkResponseStatusCode:(NSInteger)statusCode forAccount:(TalkAccount *)account;
- (void)checkProxyResponseHeaders:(NSString * _Nullable)proxyHash forAccount:(TalkAccount *)account forRoom:(NSString *)token;
- (void)initSessionManagers;
@end
