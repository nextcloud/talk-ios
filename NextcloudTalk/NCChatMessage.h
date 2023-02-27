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
#import "NCDeckCardParameter.h"
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

extern NSString * const kSharedItemTypeAudio;
extern NSString * const kSharedItemTypeDeckcard;
extern NSString * const kSharedItemTypeFile;
extern NSString * const kSharedItemTypeLocation;
extern NSString * const kSharedItemTypeMedia;
extern NSString * const kSharedItemTypeOther;
extern NSString * const kSharedItemTypeVoice;
extern NSString * const kSharedItemTypePoll;
extern NSString * const kSharedItemTypeRecording;

@class NCChatMessage;

typedef void (^GetReferenceDataCompletionBlock)(NCChatMessage *message, NSDictionary *referenceData, NSString *url);

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
@property (nonatomic, strong) NSString *reactionsSelfJSONString;
@property (nonatomic, assign) NSInteger expirationTimestamp;
@property (nonatomic, assign) BOOL isTemporary;
@property (nonatomic, assign) BOOL sendingFailed;
@property (nonatomic, assign) BOOL isGroupMessage;
@property (nonatomic, assign) BOOL isDeleting;
@property (nonatomic, assign) BOOL isSilent;
@property (nonatomic, assign) BOOL isOfflineMessage;
@property (nonatomic, assign) NSInteger offlineMessageRetryCount;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict andAccountId:(NSString *)accountId;
+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage isRoomLastMessage:(BOOL)isRoomLastMessage;

- (BOOL)isSystemMessage;
- (BOOL)isEmojiMessage;
- (BOOL)isUpdateMessage;
- (BOOL)isDeletedMessage;
- (BOOL)isVoiceMessage;
- (BOOL)isCommandMessage;
- (BOOL)isMessageFromUser:(NSString *)userId;
- (BOOL)isDeletableForAccount:(TalkAccount *)account andParticipantType:(NCParticipantType)participantType;
- (BOOL)isObjectShare;
- (NSDictionary *)richObjectFromObjectShare;
- (NCMessageFileParameter *)file;
- (NCMessageLocationParameter *)geoLocation;
- (NCDeckCardParameter *)deckCard;
- (NCMessageParameter *)poll;
- (NCMessageParameter *)objectShareParameter;
- (NSString *)objectShareLink;
- (NSDictionary *)messageParameters;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)parsedMessageForChat;
- (NSMutableAttributedString *)systemMessageFormat;
- (NSString *)sendingMessage;
- (NCChatMessage *)parent;
- (NSInteger)parentMessageId;
- (NSMutableArray *)reactionsArray;
- (BOOL)isReactionBeingModified:(NSString *)reaction;
- (void)addTemporaryReaction:(NSString *)reaction;
- (void)removeReactionTemporarily:(NSString *)reaction;
- (void)removeReactionFromTemporayReactions:(NSString *)reaction;
- (BOOL)containsURL;
- (void)getReferenceDataWithCompletionBlock:(GetReferenceDataCompletionBlock)block;
- (BOOL)isSameMessage:(NCChatMessage *)message;

@end
