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

// Internal method exposed for swift extension
- (void)checkResponseHeaders:(NSDictionary *)headers forAccount:(TalkAccount *)account;
- (NSInteger)getResponseStatusCode:(NSURLResponse *)response;
- (void)checkResponseStatusCode:(NSInteger)statusCode forAccount:(TalkAccount *)account;
- (void)checkProxyResponseHeaders:(NSString * _Nullable)proxyHash forAccount:(TalkAccount *)account forRoom:(NSString *)token;
- (void)initSessionManagers;

@end
