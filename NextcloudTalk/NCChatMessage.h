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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Realm/Realm.h>
#import "NCChatReaction.h"
#import "NCDatabaseManager.h"
#import "NCMessageParameter.h"
#import "NCMessageFileParameter.h"
#import "NCMessageLocationParameter.h"
#import "NCRoomParticipant.h"

extern NSInteger const kChatMessageGroupTimeDifference;

extern NSString * const kMessageTypeComment;
extern NSString * const kMessageTypeCommentDeleted;
extern NSString * const kMessageTypeSystem;
extern NSString * const kMessageTypeCommand;
extern NSString * const kMessageTypeVoiceMessage;

RLM_ARRAY_TYPE(NCChatReaction)

@interface NCChatMessage : RLMObject <NSCopying>

@property (nonatomic, strong) NSString *internalId; // accountId@token@messageId
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *messageParametersJSONString;
@property (nonatomic, assign) NSInteger timestamp;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *systemMessage;
@property (nonatomic, assign) BOOL isReplyable;
@property (nonatomic, strong) NSString *parentId;
@property (nonatomic, strong) NSString *referenceId;
@property (nonatomic, strong) NSString *messageType;
@property (nonatomic, strong) NSString *reactionsJSONString;
@property (nonatomic, assign) BOOL isTemporary;
@property (nonatomic, assign) BOOL sendingFailed;
@property (nonatomic, assign) BOOL isGroupMessage;
@property (nonatomic, assign) BOOL isDeleting;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict andAccountId:(NSString *)accountId;
+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage;

- (BOOL)isSystemMessage;
- (BOOL)isEmojiMessage;
- (BOOL)isUpdateMessage;
- (BOOL)isMessageFromUser:(NSString *)userId;
- (BOOL)isDeletableForAccount:(TalkAccount *)account andParticipantType:(NCParticipantType)participantType;
- (NCMessageFileParameter *)file;
- (NCMessageLocationParameter *)geoLocation;
- (NSDictionary *)messageParameters;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)systemMessageFormat;
- (NCChatMessage *)parent;
- (NSArray *)reactionsArray;

@end
