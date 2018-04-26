//
//  NCRoomController.h
//  VideoCalls
//
//  Created by Ivan Sein on 25.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCPeerConnection.h"
#import "NCRoom.h"

@class NCRoomController;

typedef void (^RoomControllerCompletionBlock)(NSError *error);

@protocol NCRoomControllerDelegate<NSObject>

- (void)roomController:(NCRoomController *)roomController didReceiveChatMessages:(NSMutableArray *)messages;

@end

@interface NCRoomController : NSObject

@property (nonatomic, weak) id<NCRoomControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, copy) NSString *userSessionId;
@property (nonatomic, copy) NSString *userDisplayName;


- (instancetype)initWithDelegate:(id<NCRoomControllerDelegate>)delegate inRoom:(NCRoom *)room;
- (void)joinRoomWithCompletionBlock:(RoomControllerCompletionBlock)block;
- (void)leaveRoomWithCompletionBlock:(RoomControllerCompletionBlock)block;
- (void)sendChatMessage:(NSString *)message;

@end
