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

@class NCRoom;

@interface NCChatMessage : RLMObject <NSCopying>

@property (nonatomic, strong) NSString *internalId; // accountId@token@messageId
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong, nullable) NSString *messageParametersJSONString;
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
@property (nonatomic, strong) RLMArray<RLMInt> *collapsedMessages;
@property (nonatomic, strong, nullable) NCChatMessage *collapsedBy;
@property (nonatomic, strong) NSString *collapsedMessage;
@property (nonatomic, strong) NSString *collapsedMessageParametersJSONString;
@property (nonatomic, assign) BOOL collapsedIncludesActorSelf;
@property (nonatomic, assign) BOOL collapsedIncludesUserSelf;
@property (nonatomic, assign) BOOL isCollapsed;
@property (nonatomic, assign) BOOL isMarkdownMessage;
@property (nonatomic, strong, nullable) NSString *lastEditActorType;
@property (nonatomic, strong, nullable) NSString *lastEditActorId;
@property (nonatomic, strong, nullable) NSString *lastEditActorDisplayName;
@property (nonatomic, assign) NSInteger lastEditTimestamp;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict andAccountId:(NSString *)accountId;
+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage isRoomLastMessage:(BOOL)isRoomLastMessage;

- (NCMessageFileParameter *)file;
- (NCMessageLocationParameter *)geoLocation;
- (NCDeckCardParameter *)deckCard;
- (NSString *)objectShareLink;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)parsedMarkdown;
- (NSMutableAttributedString *)parsedMarkdownForChat;
- (NSArray<NCChatReaction *> * _Nonnull)reactionsArray;
- (BOOL)containsURL;
- (void)getReferenceDataWithCompletionBlock:(GetReferenceDataCompletionBlock _Nullable)block;
- (void)setPreviewImageHeight:(CGFloat)height;

// Public for swift extension
- (NSMutableArray * _Nonnull)temporaryReactions;

@end
