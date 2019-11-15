//
//  NCExternalSignalingController.h
//  VideoCalls
//
//  Created by Ivan Sein on 07.09.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCSignalingMessage.h"

@class NCExternalSignalingController;
@class TalkAccount;

@protocol NCExternalSignalingControllerDelegate <NSObject>

- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedSignalingMessage:(NSDictionary *)signalingMessageDict;
- (void)externalSignalingController:(NCExternalSignalingController *)externalSignalingController didReceivedParticipantListMessage:(NSDictionary *)participantListMessageDict;
- (void)externalSignalingControllerShouldRejoinCall:(NCExternalSignalingController *)externalSignalingController;
- (void)externalSignalingControllerWillRejoinCall:(NCExternalSignalingController *)externalSignalingController;

@end

@interface NCExternalSignalingController : NSObject

@property (nonatomic, strong) NSString *currentRoom;
@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, weak) id<NCExternalSignalingControllerDelegate> delegate;

- (instancetype)initWithAccount:(TalkAccount *)account server:(NSString *)serverUrl andTicket:(NSString *)ticket;
- (BOOL)isEnabled;
- (BOOL)hasMCU;
- (NSString *)sessionId;
- (void)joinRoom:(NSString *)roomId withSessionId:(NSString *)sessionId;
- (void)leaveRoom:(NSString *)roomId;
- (void)sendCallMessage:(NCSignalingMessage *)message;
- (void)requestOfferForSessionId:(NSString *)sessionId andRoomType:(NSString *)roomType;
- (NSString *)getUserIdFromSessionId:(NSString *)sessionId;
- (void)disconnect;
- (void)forceReconnect;

@end
