//
//  NCRoomsManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCRoom.h"
#import "CallViewController.h"

// Room
extern NSString * const NCRoomsManagerDidJoinRoomNotification;
extern NSString * const NCRoomsManagerDidLeaveRoomNotification;
extern NSString * const NCRoomsManagerDidUpdateRoomsNotification;
extern NSString * const NCRoomsManagerDidUpdateRoomNotification;
// Call
extern NSString * const NCRoomsManagerDidStartCallNotification;

@interface NCRoomsManager : NSObject

@property (nonatomic, strong) CallViewController *callViewController;

+ (instancetype)sharedInstance;
// Room
- (void)updateRooms;
- (void)updateRoom:(NSString *)token;
// Chat
- (void)startChatInRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message toRoom:(NCRoom *)room;
- (void)startReceivingChatMessagesInRoom:(NCRoom *)room;
- (void)stopReceivingChatMessagesInRoom:(NCRoom *)room;
- (void)leaveChatInRoom:(NCRoom *)room;
// Call
- (void)startCall:(BOOL)video inRoom:(NCRoom *)room;

@end
