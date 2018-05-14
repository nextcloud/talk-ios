//
//  NCRoomsManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCRoom.h"

extern NSString * const NCRoomsManagerDidJoinRoomNotification;
extern NSString * const NCRoomsManagerDidLeaveRoomNotification;
extern NSString * const NCRoomsManagerDidStartCallNotification;
extern NSString * const NCRoomsManagerDidReceiveChatMessagesNotification;

@interface NCRoomsManager : NSObject

@property (nonatomic, strong) NCRoom *currentRoom;
@property (nonatomic, copy) NSString *userSessionId;
@property (nonatomic, copy) NSString *userDisplayName;

+ (instancetype)sharedInstance;
- (void)joinRoom:(NCRoom *)room;
- (void)leaveRoom:(NCRoom *)room;
- (void)sendChatMessage:(NSString *)message toRoom:(NCRoom *)room;
- (void)startCall:(BOOL)video inRoom:(NCRoom *)room;
- (void)endCallInRoom:(NCRoom *)room;

@end
