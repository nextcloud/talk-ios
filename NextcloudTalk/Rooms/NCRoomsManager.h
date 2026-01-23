/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCAPIController.h"
#import "NCRoom.h"
#import "NCChatController.h"

typedef void (^SendOfflineMessagesCompletionBlock)(void);
typedef void (^RoomDeletionStartedBlock)(void);
typedef void (^RoomDeletionAdditionalOptionBlock)(BOOL success);
typedef void (^RoomDeletionFinishedBlock)(BOOL success);

@class ChatViewController;
@class CallViewController;
@class NCPushNotification;

@interface NCRoomController : NSObject

@property (nonatomic, strong) NSString *userSessionId;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) BOOL inChat;

@end

@interface NCRoomsManager : NSObject

@property (nonatomic, strong) ChatViewController *chatViewController;
@property (nonatomic, strong) CallViewController *callViewController;

// START - Public for swift migration
@property (nonatomic, strong) NSMutableDictionary *activeRooms; //roomToken -> roomController
@property (nonatomic, strong, nullable) NSString *joiningRoomToken;
@property (nonatomic, strong, nullable) NSString *leavingRoomToken;
@property (nonatomic, strong, nullable) NSString *joiningSessionId;
@property (nonatomic, assign) NSInteger joiningAttempts;
@property (nonatomic, strong, nullable) NSURLSessionTask *joinRoomTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *leaveRoomTask;
@property (nonatomic, strong) NSString *upgradeCallToken;
@property (nonatomic, strong) NSString *pendingToStartCallToken;
@property (nonatomic, assign) BOOL pendingToStartCallHasVideo;
@property (nonatomic, strong) NSDictionary *highlightMessageDict;
@property (nonatomic, strong) NCPushNotification *showThreadPushNotification;

- (void)checkForPendingToStartCalls;
// END

+ (instancetype)sharedInstance;

// Chat
- (void)startChatInRoom:(NCRoom *)room;
- (void)leaveChatInRoom:(NSString *)token;
- (void)startChatWithRoomToken:(NSString *)token;
// Call
- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video asInitiator:(BOOL)initiator recordingConsent:(BOOL)recordingConsent;
- (BOOL)isCallOngoingWithCallToken:(NSString *)token;
// Switch to
- (void)prepareSwitchToAnotherRoomFromRoom:(NSString *)token withCompletionBlock:(PrepareSwitchRoomCompletionBlock)block;

@end
