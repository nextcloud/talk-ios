//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^GetContactsCompletionBlock)(NSMutableArray *contacts, NSError *error, NSInteger errorCode);

typedef void (^GetRoomsCompletionBlock)(NSMutableArray *rooms, NSError *error, NSInteger errorCode);
typedef void (^GetRoomCompletionBlock)(NSDictionary *room, NSError *error, NSInteger errorCode);
typedef void (^CreateOneToOneRoomCompletionBlock)(NSString *token, NSError *error, NSInteger errorCode);
typedef void (^CreateGroupRoomCompletionBlock)(NSString *token, NSError *error, NSInteger errorCode);
typedef void (^CreatePublicRoomCompletionBlock)(NSString *token, NSError *error, NSInteger errorCode);
typedef void (^RenameRoomCompletionBlock)(NSError *error, NSInteger errorCode);
typedef void (^AddParticipantCompletionBlock)(NSError *error, NSInteger errorCode);
typedef void (^RemoveSelfFromRoomCompletionBlock)(NSError *error, NSInteger errorCode);
typedef void (^MakeRoomPublicCompletionBlock)(NSError *error, NSInteger errorCode);
typedef void (^MakeRoomPrivateCompletionBlock)(NSError *error, NSInteger errorCode);

typedef void (^GetPeersForCallCompletionBlock)(NSMutableArray *peers, NSError *error, NSInteger errorCode);
typedef void (^JoinCallCompletionBlock)(NSString *sessionId, NSError *error, NSInteger errorCode);
typedef void (^PingCallCompletionBlock)(NSError *error, NSInteger errorCode);
typedef void (^LeaveCallCompletionBlock)(NSError *error, NSInteger errorCode);


@interface NCAPIController : NSObject

+ (instancetype)sharedInstance;
- (void)setNCServer:(NSString *)serverUrl;
- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token;

// Contacts Controller
- (void)getContactsWithCompletionBlock:(GetContactsCompletionBlock)block;

// Rooms Controller
- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block;
- (void)getRoom:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block;
- (void)createOneToOneRoom:(NSString *)user withCompletionBlock:(CreateOneToOneRoomCompletionBlock)block;
- (void)createGroupRoom:(NSString *)group withCompletionBlock:(CreateGroupRoomCompletionBlock)block;
- (void)createPublicRoomWithCompletionBlock:(CreatePublicRoomCompletionBlock)block;
- (void)renameRoom:(NSString *)roomId withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block;
- (void)addParticipant:(NSString *)user toRoom:(NSString *)roomId withCompletionBlock:(AddParticipantCompletionBlock)block;
- (void)removeSelfFromRoom:(NSString *)roomId withCompletionBlock:(RemoveSelfFromRoomCompletionBlock)block;
- (void)makeRoomPublic:(NSString *)roomId withCompletionBlock:(MakeRoomPublicCompletionBlock)block;
- (void)makeRoomPrivate:(NSString *)roomId withCompletionBlock:(MakeRoomPrivateCompletionBlock)block;


// Call Controller
- (void)getPeersForCall:(NSString *)token WithCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (void)joinCall:(NSString *)token WithCompletionBlock:(JoinCallCompletionBlock)block;
- (void)pingCall:(NSString *)token WithCompletionBlock:(PingCallCompletionBlock)block;
- (void)leaveCallWithCompletionBlock:(LeaveCallCompletionBlock)block;



@end
