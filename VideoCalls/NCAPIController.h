//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NCRoom.h"
#import "NCUser.h"

typedef void (^GetContactsCompletionBlock)(NSMutableArray *contacts, NSError *error, NSInteger errorCode);

typedef void (^GetRoomsCompletionBlock)(NSMutableArray *rooms, NSError *error, NSInteger errorCode);
typedef void (^GetRoomCompletionBlock)(NSDictionary *room, NSError *error, NSInteger errorCode);
typedef void (^CreateRoomCompletionBlock)(NSString *token, NSError *error, NSInteger errorCode);
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
- (void)createRoom:(NSString *)user type:(NCRoomType)type invite:(NSString *)invite withCompletionBlock:(CreateRoomCompletionBlock)block;
- (void)renameRoom:(NSString *)token withName:(NSString *)newName andCompletionBlock:(RenameRoomCompletionBlock)block;
- (void)addParticipant:(NSString *)user toRoom:(NSString *)token withCompletionBlock:(AddParticipantCompletionBlock)block;
- (void)removeSelfFromRoom:(NSString *)token withCompletionBlock:(RemoveSelfFromRoomCompletionBlock)block;
- (void)makeRoomPublic:(NSString *)token withCompletionBlock:(MakeRoomPublicCompletionBlock)block;
- (void)makeRoomPrivate:(NSString *)token withCompletionBlock:(MakeRoomPrivateCompletionBlock)block;


// Call Controller
- (void)getPeersForCall:(NSString *)token withCompletionBlock:(GetPeersForCallCompletionBlock)block;
- (void)joinCall:(NSString *)token withCompletionBlock:(JoinCallCompletionBlock)block;
- (void)pingCall:(NSString *)token withCompletionBlock:(PingCallCompletionBlock)block;
- (void)leaveCall:(NSString *)token withCompletionBlock:(LeaveCallCompletionBlock)block;



@end
