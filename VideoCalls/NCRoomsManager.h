//
//  NCRoomsManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCRoom.h"
#import "NCChatController.h"
#import "NCChatViewController.h"
#import "CallViewController.h"

// Room
extern NSString * const NCRoomsManagerDidJoinRoomNotification;
extern NSString * const NCRoomsManagerDidLeaveRoomNotification;
extern NSString * const NCRoomsManagerDidUpdateRoomsNotification;
extern NSString * const NCRoomsManagerDidUpdateRoomNotification;
// Call
extern NSString * const NCRoomsManagerDidStartCallNotification;

@interface NCRoomController : NSObject

@property (nonatomic, strong) NSString *userSessionId;
@property (nonatomic, assign) BOOL inCall;
@property (nonatomic, assign) BOOL inChat;

@end

@interface NCRoomsManager : NSObject

@property (nonatomic, strong) NCChatViewController *chatViewController;
@property (nonatomic, strong) CallViewController *callViewController;

+ (instancetype)sharedInstance;
// Room
- (NSArray *)roomsForAccountId:(NSString *)accountId;
- (NCRoom *)roomWithToken:(NSString *)token forAccountId:(NSString *)accountId;
- (void)updateRooms;
- (void)updateRoom:(NSString *)token;
- (void)joinRoom:(NSString *)token;
- (void)rejoinRoom:(NSString *)token;
// Chat
- (NCChatController *)chatContollerForRoom:(NCRoom *)room;
- (void)startChatInRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message replyTo:(NSInteger)replyTo referenceId:(NSString *)referenceId toRoom:(NCRoom *)room;
- (void)stopReceivingChatMessagesInRoom:(NCRoom *)room;
- (void)leaveChatInRoom:(NSString *)token;
// Call
- (void)startCall:(BOOL)video inRoom:(NCRoom *)room;
- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video;

@end
