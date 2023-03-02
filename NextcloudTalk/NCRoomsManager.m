/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "NCRoomsManager.h"

#import <Realm/Realm.h>

#import "AppDelegate.h"
#import "CallKitManager.h"
#import "NCChatViewController.h"
#import "NCChatBlock.h"
#import "NCChatController.h"
#import "NCChatMessage.h"
#import "NCDatabaseManager.h"
#import "NCExternalSignalingController.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "NewRoomTableViewController.h"
#import "NotificationCenterNotifications.h"
#import "RoomCreation2TableViewController.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCRoomsManagerDidJoinRoomNotification              = @"NCRoomsManagerDidJoinRoomNotification";
NSString * const NCRoomsManagerDidLeaveRoomNotification             = @"NCRoomsManagerDidLeaveRoomNotification";
NSString * const NCRoomsManagerDidUpdateRoomsNotification           = @"NCRoomsManagerDidUpdateRoomsNotification";
NSString * const NCRoomsManagerDidUpdateRoomNotification            = @"NCRoomsManagerDidUpdateRoomNotification";
NSString * const NCRoomsManagerDidStartCallNotification             = @"NCRoomsManagerDidStartCallNotification";
NSString * const NCRoomsManagerDidReceiveChatMessagesNotification   = @"ChatMessagesReceivedNotification";

static NSInteger kNotJoiningAnymoreStatusCode = 999;

@interface NCRoomsManager () <CallViewControllerDelegate>

@property (nonatomic, strong) NSMutableDictionary *activeRooms; //roomToken -> roomController
@property (nonatomic, strong) NSString *joiningRoomToken;
@property (nonatomic, strong) NSString *joiningSessionId;
@property (nonatomic, assign) NSInteger joiningAttempts;
@property (nonatomic, strong) NSURLSessionTask *joinRoomTask;
@property (nonatomic, strong) NSURLSessionTask *leaveRoomTask;
@property (nonatomic, strong) NSString *upgradeCallToken;
@property (nonatomic, strong) NSString *pendingToStartCallToken;
@property (nonatomic, assign) BOOL pendingToStartCallHasVideo;
@property (nonatomic, strong) NSDictionary *highlightMessageDict;

@end

@implementation NCRoomController
@end

@implementation NCRoomsManager

+ (NCRoomsManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCRoomsManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _activeRooms = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatWithLocalNotification:) name:NCLocalNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChat:) name:NCPushNotificationJoinChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForChat:) name:NCSelectedContactForChatNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomCreated:) name:NCRoomCreatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceptCallForRoom:) name:CallKitManagerDidAnswerCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startCallForRoom:) name:CallKitManagerDidStartCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkForCallUpgrades:) name:CallKitManagerDidEndCallNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChat:) name:NCChatViewControllerReplyPrivatelyNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatOfForwardedMessage:) name:NCChatViewControllerForwardNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChat:) name:NCChatViewControllerTalkToUserNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinOrCreateChatWithURL:) name:NCURLWantsToOpenConversationNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinChatHighlightingMessage:) name:NCPresentChatHighlightingMessageNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Room

- (void)joinRoom:(NSString *)token forCall:(BOOL)call
{
    // Clean up joining room flag and attemps
    _joiningRoomToken = nil;
    _joiningSessionId = nil;
    _joiningAttempts = 0;
    [_joinRoomTask cancel];

    [self joinRoomHelper:token forCall:call];
}

- (void)joinRoomHelper:(NSString *)token forCall:(BOOL)call
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    NCRoomController *roomController = [_activeRooms objectForKey:token];

    if (!roomController) {
        _joiningRoomToken = token;
        [self joinRoomHelper:token forCall:call withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger statusCode) {
            if (statusCode == kNotJoiningAnymoreStatusCode){
                // Not joining the room any more. Ignore response.
                return;
            }

            if (!error) {
                NCRoomController *controller = [[NCRoomController alloc] init];
                controller.userSessionId = sessionId;
                controller.inChat = !call;
                controller.inCall = call;
                [userInfo setObject:controller forKey:@"roomController"];

                // Set room as active room
                [self->_activeRooms setObject:controller forKey:token];
            } else {
                if (self->_joiningAttempts < 3) {
                    [NCUtils log:[NSString stringWithFormat:@"Error joining room, retrying. %ld", (long)self->_joiningAttempts]];
                    self->_joiningAttempts += 1;
                    [self joinRoomHelper:token forCall:call];
                    return;
                }

                // Add error to user info
                [userInfo setObject:error forKey:@"error"];
                [userInfo setObject:@(statusCode) forKey:@"statusCode"];
                [userInfo setObject:[self getJoinRoomErrorReason:statusCode] forKey:@"errorReason"];
                [NCUtils log:[NSString stringWithFormat:@"Could not join room. Status code: %ld. Error: %@", (long)statusCode, error.description]];
            }

            // Send join room notification
            [userInfo setObject:token forKey:@"token"];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidJoinRoomNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    } else {
        if (call) {
            roomController.inCall = YES;
        } else {
            roomController.inChat = YES;
        }
        [userInfo setObject:token forKey:@"token"];
        [userInfo setObject:roomController forKey:@"roomController"];
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidJoinRoomNotification
                                                            object:self
                                                          userInfo:userInfo];
    }
}

- (BOOL)isJoiningRoomWithToken:(NSString *)token
{
    return _joiningRoomToken && [_joiningRoomToken isEqualToString:token];
}

- (BOOL)isJoiningRoomWithSessionId:(NSString *)sessionId
{
    return _joiningSessionId && [_joiningSessionId isEqualToString:sessionId];
}

- (void)joinRoomHelper:(NSString *)token forCall:(BOOL)call withCompletionBlock:(JoinRoomCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token forAccount:activeAccount withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger statusCode) {

        // If we left the room before the request completed or tried to join another room, there's nothing for us to do here anymore
        if (![self isJoiningRoomWithToken:token]) {
            [NCUtils log:@"Not joining the room any more. Ignore response."];

            if (block) {
                block(nil, nil, kNotJoiningAnymoreStatusCode);
            }

            return;
        }

        // Failed to join room in NC.
        if (error) {
            if (block) {
                block(nil, error, statusCode);
            }

            return;
        }

        [NCUtils log:[NSString stringWithFormat:@"Joined room %@ in NC successfully.", token]];
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];

        if ([extSignalingController isEnabled]) {
            [NCUtils log:[NSString stringWithFormat:@"Trying to join room %@ in external signaling server...", token]];

            // Remember the latest sessionId we're using to join a room, to be able to check when joining the external signaling server
            self->_joiningSessionId = sessionId;

            [extSignalingController joinRoom:token withSessionId:sessionId withCompletionBlock:^(NSError *error) {
                // If the sessionId is not the same anymore we tried to join with, we either already left again before
                // joining the external signaling server succeeded, or we already have another join in process
                if (![self isJoiningRoomWithToken:token] || ![self isJoiningRoomWithSessionId:sessionId]) {
                    [NCUtils log:@"Not joining the room any more or joining the same room with a different sessionId. Ignore external signaling completion block."];

                    if (block) {
                        block(nil, nil, kNotJoiningAnymoreStatusCode);
                    }

                    return;
                }

                if (!error) {
                    [NCUtils log:[NSString stringWithFormat:@"Joined room %@ in external signaling server successfully.", token]];
                    block(sessionId, nil, 0);
                } else if (block) {
                    [NCUtils log:[NSString stringWithFormat:@"Failed joining room %@ in external signaling server.", token]];
                    block(nil, error, statusCode);
                }
            }];
        } else if (block) {
            // Joined room in NC successfully and no external signaling server configured.
            block(sessionId, nil, 0);
        }
    }];
}

- (NSString *)getJoinRoomErrorReason:(NSInteger)statusCode
{
    NSString *errorReason = NSLocalizedString(@"Unknown error occurred", nil);
    
    switch (statusCode) {
        case 0:
            errorReason = NSLocalizedString(@"No response from server", nil);
            break;
            
        case 403:
            errorReason = NSLocalizedString(@"The password is wrong", nil);
            break;
            
        case 404:
            errorReason = NSLocalizedString(@"Conversation not found", nil);
            break;
            
        case 409:
            // Currently not triggered, needs to be enabled in API with sending force=false
            errorReason = NSLocalizedString(@"Duplicate session", nil);
            break;
            
        case 503:
            errorReason = NSLocalizedString(@"Server is currently in maintenance mode", nil);
            break;
    }
    
    return errorReason;
}

- (void)rejoinRoom:(NSString *)token
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (roomController) {
        _joiningRoomToken = [token copy];
        _joinRoomTask = [[NCAPIController sharedInstance] joinRoom:token forAccount:activeAccount withCompletionBlock:^(NSString *sessionId, NSError *error, NSInteger statusCode) {
            if (!error) {
                roomController.userSessionId = sessionId;
                roomController.inChat = YES;
                NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
                if ([extSignalingController isEnabled]) {
                    [extSignalingController joinRoom:token withSessionId:sessionId withCompletionBlock:nil];
                }
            } else {
                NSLog(@"Could not re-join room. Status code: %ld. Error: %@", (long)statusCode, error.description);
            }
            self->_joiningRoomToken = nil;
            self->_joiningSessionId = nil;
        }];
    }
}

- (void)leaveRoom:(NSString *)token
{
    // Check if leaving the room we are joining
    if ([_joiningRoomToken isEqualToString:token]) {
        _joiningRoomToken = nil;
        _joiningSessionId = nil;
        [_joinRoomTask cancel];
    }
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    // Remove room controller and exit room
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController && !roomController.inCall && !roomController.inChat) {
        [_activeRooms removeObjectForKey:token];
        _leaveRoomTask = [[NCAPIController sharedInstance] exitRoom:token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            if (!error) {
                NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
                if ([extSignalingController isEnabled]) {
                    [extSignalingController leaveRoom:token];
                }
            } else {
                [userInfo setObject:error forKey:@"error"];
                NSLog(@"Could not exit room. Error: %@", error.description);
            }
            self->_leaveRoomTask = nil;
            [self checkForPendingToStartCalls];
            [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidLeaveRoomNotification
                                                                object:self
                                                              userInfo:userInfo];
        }];
    } else {
        [self checkForPendingToStartCalls];
    }
}

- (NSArray *)roomsForAccountId:(NSString *)accountId witRealm:(RLMRealm *)realm
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    RLMResults *managedRooms = nil;
    if (realm) {
        managedRooms = [NCRoom objectsInRealm:realm withPredicate:query];
    } else {
        managedRooms = [NCRoom objectsWithPredicate:query];
    }
    // Create an unmanaged copy of the rooms
    NSMutableArray *unmanagedRooms = [NSMutableArray new];
    for (NCRoom *managedRoom in managedRooms) {
        NCRoom *unmanagedRoom = [[NCRoom alloc] initWithValue:managedRoom];
        // Filter out breakout rooms with lobby enabled
        if ([unmanagedRoom isBreakoutRoom] && unmanagedRoom.lobbyState == NCRoomLobbyStateModeratorsOnly) {
            continue;
        }
        [unmanagedRooms addObject:unmanagedRoom];
    }
    // Sort by favorites
    NSSortDescriptor *favoriteSorting = [NSSortDescriptor sortDescriptorWithKey:@"" ascending:YES comparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NCRoom *first = (NCRoom*)obj1;
        NCRoom *second = (NCRoom*)obj2;
        BOOL favorite1 = first.isFavorite;
        BOOL favorite2 = second.isFavorite;
        if (favorite1 != favorite2) {
            return favorite2 - favorite1;
        }
        return NSOrderedSame;
    }];
    // Sort by lastActivity
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastActivity" ascending:NO];
    NSArray *descriptors = [NSArray arrayWithObjects:favoriteSorting, valueDescriptor, nil];
    [unmanagedRooms sortUsingDescriptors:descriptors];
    
    return unmanagedRooms;
}

- (NCRoom *)roomWithToken:(NSString *)token forAccountId:(NSString *)accountId
{
    NCRoom *unmanagedRoom = nil;
    NSPredicate *query = [NSPredicate predicateWithFormat:@"token = %@ AND accountId = %@", token, accountId];
    NCRoom *managedRoom = [NCRoom objectsWithPredicate:query].firstObject;
    if (managedRoom) {
        unmanagedRoom = [[NCRoom alloc] initWithValue:managedRoom];
    }
    return unmanagedRoom;
}

- (void)resendOfflineMessagesWithCompletionBlock:(SendOfflineMessagesCompletionBlock)block
{
    // Try to send offline messages for all rooms
    [self resendOfflineMessagesForToken:nil withCompletionBlock:block];
}

- (void)resendOfflineMessagesForToken:(NSString *)token withCompletionBlock:(SendOfflineMessagesCompletionBlock)block
{
    NSPredicate *query;

    if (!token) {
        query = [NSPredicate predicateWithFormat:@"isOfflineMessage = true"];
    } else {
        query = [NSPredicate predicateWithFormat:@"isOfflineMessage = true AND token = %@", token];
    }

    RLMRealm *realm = [RLMRealm defaultRealm];
    RLMResults *managedTemporaryMessages = [NCChatMessage objectsWithPredicate:query];
    NSInteger twelveHoursAgoTimestamp = [[NSDate date] timeIntervalSince1970] - (60 * 60 * 12);

    for (NCChatMessage *offlineMessage in managedTemporaryMessages) {
        // If we were unable to send a message after 12 hours, mark as failed
        if (offlineMessage.timestamp < twelveHoursAgoTimestamp) {
            [realm transactionWithBlock:^{
                NCChatMessage *managedChatMessage = [NCChatMessage objectsWhere:@"referenceId = %@ AND isTemporary = true", offlineMessage.referenceId].firstObject;
                managedChatMessage.isOfflineMessage = NO;
                managedChatMessage.sendingFailed = YES;
            }];

            NSMutableDictionary *userInfo = [NSMutableDictionary new];
            [userInfo setObject:offlineMessage forKey:@"message"];
            [userInfo setObject:@(NO) forKey:@"isOfflineMessage"];

            if (offlineMessage.referenceId) {
                [userInfo setObject:offlineMessage.referenceId forKey:@"referenceId"];
            }

            // Inform the callViewController about this change
            [[NSNotificationCenter defaultCenter] postNotificationName:NCChatControllerDidSendChatMessageNotification
                                                                object:self
                                                              userInfo:userInfo];
            return;
        }

        NCRoom *room = [[NCRoomsManager sharedInstance] roomWithToken:offlineMessage.token forAccountId:offlineMessage.accountId];
        NCChatController *chatController = [[NCChatController alloc] initForRoom:room];

        [chatController sendChatMessage:offlineMessage];
    }

    if (block) {
        block();
    }
}

- (void)updateRoomsUpdatingUserStatus:(BOOL)updateStatus
{
    [self updateRoomsUpdatingUserStatus:updateStatus withCompletionBlock:nil];
}

- (void)updateRoomsAndChatsUpdatingUserStatus:(BOOL)updateStatus withCompletionBlock:(UpdateRoomsAndChatsCompletionBlock)block
{
    [self updateRoomsUpdatingUserStatus:updateStatus withCompletionBlock:^(NSArray *roomsWithNewMessages, NSError *error) {
        if (error) {
            if (block) {
                block(error);
            }
            
            return;
        }
        
        NSLog(@"Finished rooms update with %lu rooms with new messages", [roomsWithNewMessages count]);
        dispatch_group_t chatUpdateGroup = dispatch_group_create();
        
        // Disable background message fetch until API v4
        
//        // When in low power mode, we only update the conversation list and don't load new messages for each room
//        if (![NSProcessInfo processInfo].isLowPowerModeEnabled) {
//            for (NCRoom *room in roomsWithNewMessages) {
//                dispatch_group_enter(chatUpdateGroup);
//
//                NSLog(@"Updating room %@", room.internalId);
//                NCChatController *chatController = [[NCChatController alloc] initForRoom:room];
//
//                [chatController updateHistoryInBackgroundWithCompletionBlock:^(NSError *error) {
//                    NSLog(@"Finished updating room %@", room.internalId);
//                    dispatch_group_leave(chatUpdateGroup);
//                }];
//            }
//        }

                
        dispatch_group_notify(chatUpdateGroup, dispatch_get_main_queue(), ^{
            // Notify backgroundFetch that we're finished
            if (block) {
                block(nil);
            }
        });
    }];
}

- (void)updateRoomsUpdatingUserStatus:(BOOL)updateStatus withCompletionBlock:(UpdateRoomsCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomsForAccount:activeAccount updateStatus:updateStatus withCompletionBlock:^(NSArray *rooms, NSError *error, NSInteger statusCode) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        NSMutableArray *roomsWithNewMessages = [NSMutableArray new];

        if (!error) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateRoomsTransaction" expirationHandler:nil];

            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                // Add or update rooms
                NSInteger updateTimestamp = [[NSDate date] timeIntervalSince1970];
                for (NSDictionary *roomDict in rooms) {
                    BOOL roomContainsNewMessages = [self updateRoomWithDict:roomDict withAccount:activeAccount withTimestamp:updateTimestamp withRealm:realm];

                    if (roomContainsNewMessages) {
                        NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                        [roomsWithNewMessages addObject:room];
                    }
                }

                // Delete old rooms
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND lastUpdate != %ld", activeAccount.accountId, (long)updateTimestamp];
                RLMResults *managedRoomsToBeDeleted = [NCRoom objectsWithPredicate:query];
                // Delete messages and chat blocks from old rooms
                for (NCRoom *managedRoom in managedRoomsToBeDeleted) {
                    NSPredicate *query2 = [NSPredicate predicateWithFormat:@"accountId = %@ AND token = %@", activeAccount.accountId, managedRoom.token];
                    [realm deleteObjects:[NCChatMessage objectsWithPredicate:query2]];
                    [realm deleteObjects:[NCChatBlock objectsWithPredicate:query2]];
                }
                [realm deleteObjects:managedRoomsToBeDeleted];
                NSLog(@"Rooms updated");
            }];

            [bgTask stopBackgroundTask];
        } else {
            [userInfo setObject:error forKey:@"error"];
            [NCUtils log:[NSString stringWithFormat:@"Could not update rooms. Error: %@", error.description]];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomsNotification
                                                            object:self
                                                          userInfo:userInfo];
        
        if (block) {
            block(roomsWithNewMessages, error);
        }
    }];
}

- (void)updateRoom:(NSString *)token withCompletionBlock:(GetRoomCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary new];
        if (!error) {
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                [self updateRoomWithDict:roomDict withAccount:activeAccount withTimestamp:[[NSDate date] timeIntervalSince1970] withRealm:realm];
                NSLog(@"Room updated");
            }];
            NCRoom *updatedRoom = [self roomWithToken:token forAccountId:activeAccount.accountId];
            [userInfo setObject:updatedRoom forKey:@"room"];
        } else {
            [userInfo setObject:error forKey:@"error"];
            NSLog(@"Could not update rooms. Error: %@", error.description);
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:NCRoomsManagerDidUpdateRoomNotification
                                                            object:self
                                                          userInfo:userInfo];

        if (block) {
            block(roomDict, error);
        }
    }];
}

- (BOOL)updateRoomWithDict:(NSDictionary *)roomDict withAccount:(TalkAccount *)activeAccount withTimestamp:(NSInteger)timestamp withRealm:(RLMRealm *)realm
{
    BOOL roomContainsNewMessages = NO;
    
    NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
    NSDictionary *messageDict = [roomDict objectForKey:@"lastMessage"];
    NCChatMessage *lastMessage = [NCChatMessage messageWithDictionary:messageDict andAccountId:activeAccount.accountId];
    room.lastUpdate = timestamp;
    room.lastMessageId = lastMessage.internalId;
    
    NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
    if (managedRoom) {
        if (room.lastActivity > managedRoom.lastActivity) {
            roomContainsNewMessages = YES;
        }
        
        [NCRoom updateRoom:managedRoom withRoom:room];
    } else if (room) {
        [realm addObject:room];
    }
    
    NCChatMessage *managedLastMessage = [NCChatMessage objectsWhere:@"internalId = %@", lastMessage.internalId].firstObject;
    if (managedLastMessage) {
        [NCChatMessage updateChatMessage:managedLastMessage withChatMessage:lastMessage isRoomLastMessage:YES];
    } else if (lastMessage) {
        NCChatController *chatController = [[NCChatController alloc] initForRoom:room];
        [chatController storeMessages:@[messageDict] withRealm:realm];
    }
    
    return roomContainsNewMessages;
}

- (void)updatePendingMessage:(NSString *)message forRoom:(NCRoom *)room
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"updatePendingMessage" expirationHandler:nil];
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.pendingMessage = message;
        }
    }];
    [bgTask stopBackgroundTask];
}

- (void)updateLastReadMessage:(NSInteger)lastReadMessage forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.lastReadMessage = lastReadMessage;
        }
    }];
}

- (void)updateLastMessage:(NCChatMessage *)message withNoUnreadMessages:(BOOL)noUnreadMessages forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom) {
            managedRoom.lastMessageId = message.internalId;
            managedRoom.lastActivity = message.timestamp;
            
            if (noUnreadMessages) {
                managedRoom.unreadMention = NO;
                managedRoom.unreadMentionDirect = NO;
                managedRoom.unreadMessages = 0;
            }
        }
    }];
}

- (void)updateLastCommonReadMessage:(NSInteger)messageId forRoom:(NCRoom *)room
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NCRoom *managedRoom = [NCRoom objectsWhere:@"internalId = %@", room.internalId].firstObject;
        if (managedRoom && messageId > managedRoom.lastCommonReadMessage) {
            managedRoom.lastCommonReadMessage = messageId;
        }
    }];
}

#pragma mark - Chat

- (void)startChatInRoom:(NCRoom *)room
{
    if (_callViewController) {
        NSLog(@"Not starting chat due to in a call.");
        return;
    }
    
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (!roomController) {
        // Workaround until external signaling supports multi-room
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if ([extSignalingController isEnabled]) {
            NSString *currentRoom = extSignalingController.currentRoom;
            if (![currentRoom isEqualToString:room.token]) {
                // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                // is no longer the room we want to leave (so no message is sent to the external signaling server).
                extSignalingController.currentRoom = nil;
            }
        }
    }
    
    if (!_chatViewController || ![_chatViewController.room.token isEqualToString:room.token]) {
        // Leave the previous chat
        //[[NCRoomsManager sharedInstance].chatViewController leaveChat];

        NSLog(@"Creating new chat view controller.");
        _chatViewController = [[NCChatViewController alloc] initForRoom:room];
        if (_highlightMessageDict && [[_highlightMessageDict objectForKey:@"token"] isEqualToString:room.token]) {
            _chatViewController.highlightMessageId = [[_highlightMessageDict objectForKey:@"messageId"] integerValue];
            _highlightMessageDict = nil;
        }
        [[NCUserInterfaceController sharedInstance] presentChatViewController:_chatViewController];
    } else {
        NSLog(@"Not creating new chat room: chatViewController for room %@ does already exist.", room.token);

        // Still make sure the current room is highlighted
        [[NCUserInterfaceController sharedInstance].roomsTableViewController setSelectedRoomToken:_chatViewController.room.token];
    }
}

- (void)startChatWithRoomToken:(NSString *)token
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NCRoom *room = [self roomWithToken:token forAccountId:activeAccount.accountId];
    if (room) {
        [self startChatInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
            if (!error) {
                NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
                [self startChatInRoom:room];
            }
        }];
    }
}

- (void)leaveChatInRoom:(NSString *)token;
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        roomController.inChat = NO;
    }
    
    [self leaveRoom:token];
}

#pragma mark - Call

- (void)startCall:(BOOL)video inRoom:(NCRoom *)room withVideoEnabled:(BOOL)enabled silently:(BOOL)silently andVoiceChatMode:(BOOL)voiceChatMode
{
    if (!_callViewController) {
        TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
        _callViewController = [[CallViewController alloc] initCallInRoom:room asUser:activeAccount.userDisplayName audioOnly:!video];
        _callViewController.videoDisabledAtStart = !enabled;
        _callViewController.voiceChatModeAtStart = voiceChatMode;
        _callViewController.silentCall = silently;
        [_callViewController setModalTransitionStyle:UIModalTransitionStyleCrossDissolve];
        _callViewController.delegate = self;

        NSString *chatViewControllerRoomToken = _chatViewController.room.token;
        NSString *joiningRoomToken = room.token;

        // Workaround until external signaling supports multi-room
        NCExternalSignalingController *extSignalingController = [[NCSettingsController sharedInstance] externalSignalingControllerForAccountId:activeAccount.accountId];
        if ([extSignalingController isEnabled]) {
            NSString *extSignalingRoomToken = extSignalingController.currentRoom;

            if (![extSignalingRoomToken isEqualToString:joiningRoomToken]) {
                // Since we are going to join another conversation, we don't need to leaveRoom() in extSignalingController.
                // That's why we set currentRoom = nil, so when leaveRoom() is called in extSignalingController the currentRoom
                // is no longer the room we want to leave (so no message is sent to the external signaling server).
                extSignalingController.currentRoom = nil;
            }
        }

        // Make sure the external signaling contoller is connected.
        // Could be that the call has been received while the app was inactive or in the background,
        // so the external signaling controller might be disconnected at this point.
        if ([extSignalingController disconnected]) {
            [extSignalingController forceConnect];
        }

        if (_chatViewController) {
            if ([chatViewControllerRoomToken isEqualToString:joiningRoomToken]) {
                // We're in the chat of the room we want to start a call, so stop chat for now
                [_chatViewController stopChat];
            } else {
                // We're in a different chat, so make sure we leave the chat and go back to the conversation list
                [_chatViewController leaveChat];
                [[NCUserInterfaceController sharedInstance] presentConversationsList];
            }
        }

        [[NCUserInterfaceController sharedInstance] presentCallViewController:_callViewController];
        [self joinRoom:room.token forCall:YES];
    } else {
        NSLog(@"Not starting call due to in another call.");
    }
}

- (void)joinCallWithCallToken:(NSString *)token withVideo:(BOOL)video
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
        if (!error) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
            [[CallKitManager sharedInstance] startCall:room.token withVideoEnabled:video andDisplayName:room.displayName silently:YES withAccountId:activeAccount.accountId];
        }
    }];
}

- (void)startCallWithCallToken:(NSString *)token withVideo:(BOOL)video enabledAtStart:(BOOL)enabled silently:(BOOL)silently andVoiceChatMode:(BOOL)voiceChatMode
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getRoomForAccount:activeAccount withToken:token withCompletionBlock:^(NSDictionary *roomDict, NSError *error) {
        if (!error) {
            NCRoom *room = [NCRoom roomWithDictionary:roomDict andAccountId:activeAccount.accountId];
            [self startCall:video inRoom:room withVideoEnabled:enabled silently:silently andVoiceChatMode:voiceChatMode];
        }
    }];
}

- (void)checkForPendingToStartCalls
{
    if (_pendingToStartCallToken) {
        // Pending calls can only happen when answering a new call. That's why we start with video disabled at start and in voice chat mode.
        // We also can start call silently because we are joining an already started call so no need to notify.
        [self startCallWithCallToken:_pendingToStartCallToken withVideo:_pendingToStartCallHasVideo enabledAtStart:NO silently:YES andVoiceChatMode:YES];
        _pendingToStartCallToken = nil;
    }
}

- (BOOL)areThereActiveCalls
{
    for (NCRoomController *roomController in [_activeRooms allValues]) {
        if (roomController.inCall) {
            return YES;
        }
    }
    return NO;
}

- (void)upgradeCallToVideoCall:(NCRoom *)room
{
    NCRoomController *roomController = [_activeRooms objectForKey:room.token];
    if (roomController) {
        roomController.inCall = NO;
    }
    _upgradeCallToken = room.token;
    [[CallKitManager sharedInstance] endCall:room.token];
}

- (void)leaveCallInRoom:(NSString *)token
{
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        roomController.inCall = NO;
    }

    [self leaveRoom:token];
}

- (void)callDidEndInRoomWithToken:(NSString *)token
{
    [self leaveCallInRoom:token];

    [[CallKitManager sharedInstance] endCall:token];
    
    if ([_chatViewController.room.token isEqualToString:token]) {
        [_chatViewController resumeChat];
    }
}

#pragma mark - Switch to

- (void)prepareSwitchToAnotherRoomFromRoom:(NSString *)token withCompletionBlock:(ExitRoomCompletionBlock)block
{
    if ([_chatViewController.room.token isEqualToString:token]) {
        [_chatViewController leaveChat];
        [[NCUserInterfaceController sharedInstance] popToConversationsList];
    }
    
    // Remove room controller and exit room
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NCRoomController *roomController = [_activeRooms objectForKey:token];
    if (roomController) {
        [_activeRooms removeObjectForKey:token];
        [[NCAPIController sharedInstance] exitRoom:token forAccount:activeAccount withCompletionBlock:block];
    } else {
        NSLog(@"Couldn't find a room controller from the room we are switching from");
        block(nil);
    }
}

#pragma mark - CallViewControllerDelegate

- (void)callViewControllerWantsToBeDismissed:(CallViewController *)viewController
{
    if (_callViewController == viewController && ![viewController isBeingDismissed]) {
        [viewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)callViewControllerWantsVideoCallUpgrade:(CallViewController *)viewController
{
    NCRoom *room = _callViewController.room;
    if (_callViewController == viewController) {
        _callViewController = nil;
        [self upgradeCallToVideoCall:room];
    }
}

- (void)callViewController:(CallViewController *)viewController wantsToSwitchCallFromCall:(NSString *)from toRoom:(NSString *)to
{
    if (_callViewController == viewController) {
        [[CallKitManager sharedInstance] switchCallFrom:from toCall:to];
    }
}

- (void)callViewControllerDidFinish:(CallViewController *)viewController
{
    if (_callViewController == viewController) {
        NSString *token = [_callViewController.room.token copy];
        _callViewController = nil;
        [self callDidEndInRoomWithToken:token];
        // Keep connection alive temporarily when a call was finished while the app in the background
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
            AppDelegate *appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
            [appDelegate keepExternalSignalingConnectionAliveTemporarily];
        }
    }
}

#pragma mark - Notifications

- (void)checkForCallUpgrades:(NSNotification *)notification
{
    if (_upgradeCallToken) {
        NSString *token = [_upgradeCallToken copy];
        _upgradeCallToken = nil;
        // Add some delay so CallKit doesn't fail requesting new call
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
            [self joinCallWithCallToken:token withVideo:YES];
        });
    }
}

- (void)checkForAccountChange:(NSString *)accountId
{
    // Change account if notification is from another account
    if (accountId && ![[[NCDatabaseManager sharedInstance] activeAccount].accountId isEqualToString:accountId]) {
        // Leave chat before changing accounts
        if ([[NCRoomsManager sharedInstance] chatViewController]) {
            [[[NCRoomsManager sharedInstance] chatViewController] leaveChat];
        }
        // Set notification account active
        [[NCSettingsController sharedInstance] setActiveAccountWithAccountId:accountId];
    }
}

- (void)acceptCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    BOOL waitForCallEnd = [[notification.userInfo objectForKey:@"waitForCallEnd"] boolValue];
    BOOL hasVideo = [[notification.userInfo objectForKey:@"hasVideo"] boolValue];
    BOOL activeCalls = [self areThereActiveCalls];
    if (!waitForCallEnd || (!activeCalls && !_leaveRoomTask)) {
        // Calls that have been answered start with video disabled by default, in voice chat mode and silently (without notification).
        [self startCallWithCallToken:roomToken withVideo:hasVideo enabledAtStart:NO silently:YES andVoiceChatMode:YES];
    } else {
        _pendingToStartCallToken = roomToken;
        _pendingToStartCallHasVideo = hasVideo;
    }
}

- (void)startCallForRoom:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    BOOL isVideoEnabled = [[notification.userInfo objectForKey:@"isVideoEnabled"] boolValue];
    BOOL silentCall = [[notification.userInfo objectForKey:@"silentCall"] boolValue];
    [self startCallWithCallToken:roomToken withVideo:isVideoEnabled enabledAtStart:YES silently:silentCall andVoiceChatMode:NO];
}

- (void)joinAudioCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:NO];
}

- (void)joinVideoCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    [self joinCallWithCallToken:pushNotification.roomToken withVideo:YES];
}

- (void)joinChat:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self checkForAccountChange:pushNotification.accountId];
    [self startChatWithRoomToken:pushNotification.roomToken];
}

- (void)joinOrCreateChatWithUser:(NSString *)userId usingAccountId:(NSString *)accountId
{
    NSArray *accountRooms = [[NCRoomsManager sharedInstance] roomsForAccountId:accountId witRealm:nil];
    
    for (NCRoom *room in accountRooms) {
        NSArray *participantsInRoom = [room.participants valueForKey:@"self"];
        
        if (room.type == kNCRoomTypeOneToOne && [participantsInRoom containsObject:userId]) {
            // Room already exists -> join the room
            [self startChatWithRoomToken:room.token];
            
            return;
        }
    }
    
    // Did not find a one-to-one room for this user -> create a new one
    [[NCAPIController sharedInstance] createRoomForAccount:[[NCDatabaseManager sharedInstance] activeAccount] with:userId
                                                    ofType:kNCRoomTypeOneToOne
                                                   andName:nil
                    withCompletionBlock:^(NSString *token, NSError *error) {
                        if (!error) {
                            [self startChatWithRoomToken:token];
                             NSLog(@"Room %@ with %@ created", token, userId);
                         } else {
                             NSLog(@"Failed creating a room with %@", userId);
                         }
                    }];
}

- (void)joinOrCreateChat:(NSNotification *)notification
{
    NSString *actorId = [notification.userInfo objectForKey:@"actorId"];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self joinOrCreateChatWithUser:actorId usingAccountId:activeAccount.accountId];
}

- (void)joinOrCreateChatWithURL:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSString *withUser = [notification.userInfo objectForKey:@"withUser"];
    NSString *roomToken = [notification.userInfo objectForKey:@"withRoomToken"];
    [self checkForAccountChange:accountId];

    if (withUser) {
        [self joinOrCreateChatWithUser:withUser usingAccountId:accountId];
    } else if (roomToken) {
        [self startChatWithRoomToken:roomToken];
    } // else: no chat specified, only change account
}

- (void)joinChatOfForwardedMessage:(NSNotification *)notification
{
    NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
    NSString *token = [notification.userInfo objectForKey:@"token"];
    [self checkForAccountChange:accountId];
    [self startChatWithRoomToken:token];
}

- (void)joinChatWithLocalNotification:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"roomToken"];
    if (roomToken) {
        NSString *accountId = [notification.userInfo objectForKey:@"accountId"];
        [self checkForAccountChange:accountId];
        [self startChatWithRoomToken:roomToken];
        
        // In case this notification occurred because of a failed chat-sending event, make sure the text is not lost
        // Note: This will override any stored pending message
        NSString *responseUserText = [notification.userInfo objectForKey:@"responseUserText"];
        if (_chatViewController && responseUserText) {
            [_chatViewController setChatMessage:responseUserText];
        }
    }
}

- (void)joinChatHighlightingMessage:(NSNotification *)notification
{
    _highlightMessageDict = notification.userInfo;
    NSString *token = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:token];
}

- (void)userSelectedContactForChat:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}

- (void)roomCreated:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self startChatWithRoomToken:roomToken];
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];

    // Try to send offline message when the connection state changes to connected again
    if (connectionState == kConnectionStateConnected) {
        [self resendOfflineMessagesWithCompletionBlock:nil];
    }
}

@end
