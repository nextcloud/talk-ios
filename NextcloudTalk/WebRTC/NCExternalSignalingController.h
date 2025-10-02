/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "NCSignalingMessage.h"

@class NCExternalSignalingController;
@class TalkAccount;
@class SignalingParticipant;

extern NSString * const NCExternalSignalingControllerDidUpdateParticipantsNotification;
extern NSString * const NCExternalSignalingControllerDidReceiveJoinOfParticipantNotification;
extern NSString * const NCExternalSignalingControllerDidReceiveLeaveOfParticipantNotification;
extern NSString * const NCExternalSignalingControllerDidReceiveStartedTypingNotification;
extern NSString * const NCExternalSignalingControllerDidReceiveStoppedTypingNotification;

typedef NS_ENUM(NSInteger, NCExternalSignalingSendMessageStatus) {
    SendMessageSuccess = 0,
    SendMessageSocketError,
    SendMessageApplicationError
};

@protocol NCExternalSignalingControllerDelegate <NSObject>

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedSignalingMessage:(NSDictionary *)signalingMessageDict;
- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedParticipantListMessage:(NSDictionary *)participantListMessageDict;
- (void)externalSignalingControllerShouldRejoinCall:(NCExternalSignalingController *)externalSignalingController;
- (void)externalSignalingControllerWillRejoinCall:(NCExternalSignalingController *)externalSignalingController;
- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController shouldSwitchToCall:(NSString *)roomToken;

@end

@interface NCExternalSignalingController : NSObject

typedef void (^SendMessageCompletionBlock)(NSURLSessionWebSocketTask *task, NCExternalSignalingSendMessageStatus status);
typedef void (^JoinRoomExternalSignalingCompletionBlock)(NSError *error);

@property (nonatomic, strong) NSString *currentRoom;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, assign) BOOL disconnected;
@property (nonatomic, weak) id<NCExternalSignalingControllerDelegate> delegate;

- (instancetype)initWithAccount:(TalkAccount *)account server:(NSString *)serverUrl andTicket:(NSString *)ticket;
- (BOOL)hasMCU;
- (NSString *)sessionId;
- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId withFederation:(NSDictionary * _Nullable)federationDict withCompletionBlock:(JoinRoomExternalSignalingCompletionBlock)block;
- (void)leaveRoom:(NSString *)roomId;
- (void)sendCallMessage:(NCSignalingMessage *)message;
- (void)sendSendOfferMessageWithSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType;
- (void)sendRoomMessageOfType:(NSString *)messageType andRoomType:(NSString *)roomType;
- (void)requestOfferForSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType;
- (SignalingParticipant * _Nullable)getParticipantFromSessionId:(NSString * _Nonnull)sessionId;
- (NSMutableDictionary * _Nonnull)getParticipantMap;
- (void)connect;
- (void)forceConnect;
- (void)disconnect;
- (void)forceReconnectForRejoin;

@end
