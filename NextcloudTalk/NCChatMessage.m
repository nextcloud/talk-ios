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

#import "NCChatMessage.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NextcloudTalk-Swift.h"

NSInteger const kChatMessageGroupTimeDifference = 30;

NSString * const kMessageTypeComment        = @"comment";
NSString * const kMessageTypeCommentDeleted = @"comment_deleted";
NSString * const kMessageTypeSystem         = @"system";
NSString * const kMessageTypeCommand        = @"command";
NSString * const kMessageTypeVoiceMessage   = @"voice-message";

NSString * const kSharedItemTypeAudio       = @"audio";
NSString * const kSharedItemTypeDeckcard    = @"deckcard";
NSString * const kSharedItemTypeFile        = @"file";
NSString * const kSharedItemTypeLocation    = @"location";
NSString * const kSharedItemTypeMedia       = @"media";
NSString * const kSharedItemTypeOther       = @"other";
NSString * const kSharedItemTypeVoice       = @"voice";
NSString * const kSharedItemTypePoll        = @"poll";
NSString * const kSharedItemTypeRecording   = @"recording";

@interface NCChatMessage ()
{
    NCMessageFileParameter *_fileParameter;
    NCMessageLocationParameter *_locationParameter;
    NCDeckCardParameter *_deckCardParameter;
    NSString *_objectShareLink;
    NSMutableArray *_temporaryReactions;
    BOOL _urlDetectionDone;
    NSString *_urlDetected;
    BOOL _referenceDataDone;
    NSDictionary *_referenceData;
}

@end

@implementation NCChatMessage

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict
{
    if (!messageDict || ![messageDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NCChatMessage *message = [[NCChatMessage alloc] init];
    message.actorId = [messageDict objectForKey:@"actorId"];
    message.actorType = [messageDict objectForKey:@"actorType"];
    message.messageId = [[messageDict objectForKey:@"id"] integerValue];
    message.message = [messageDict objectForKey:@"message"];
    message.timestamp = [[messageDict objectForKey:@"timestamp"] integerValue];
    message.token = [messageDict objectForKey:@"token"];
    message.systemMessage = [messageDict objectForKey:@"systemMessage"];
    message.isReplyable = [[messageDict objectForKey:@"isReplyable"] boolValue];
    message.referenceId = [messageDict objectForKey:@"referenceId"];
    message.messageType = [messageDict objectForKey:@"messageType"];
    message.expirationTimestamp = [[messageDict objectForKey:@"expirationTimestamp"] integerValue];
    
    id actorDisplayName = [messageDict objectForKey:@"actorDisplayName"];
    if (!actorDisplayName) {
        message.actorDisplayName = @"";
    } else {
        if ([actorDisplayName isKindOfClass:[NSString class]]) {
            message.actorDisplayName = actorDisplayName;
        } else {
            message.actorDisplayName = [actorDisplayName stringValue];
        }
    }
    
    id messageParameters = [messageDict objectForKey:@"messageParameters"];
    if ([messageParameters isKindOfClass:[NSDictionary class]]) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messageParameters
                                                           options:0
                                                             error:&error];
        if (jsonData) {
            message.messageParametersJSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        } else {
            NSLog(@"Error generating message parameters JSON string: %@", error);
        }
    }
    
    id reactions = [messageDict objectForKey:@"reactions"];
    if ([reactions isKindOfClass:[NSDictionary class]]) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:reactions
                                                           options:0
                                                             error:&error];
        if (jsonData) {
            message.reactionsJSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        } else {
            NSLog(@"Error generating reactions JSON string: %@", error);
        }
    }
    
    id reactionsSelf = [messageDict objectForKey:@"reactionsSelf"];
    if ([reactionsSelf isKindOfClass:[NSArray class]]) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:reactionsSelf
                                                           options:0
                                                             error:&error];
        if (jsonData) {
            message.reactionsSelfJSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        } else {
            NSLog(@"Error generating reactionsSelf JSON string: %@", error);
        }
    }
    
    return message;
}

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict andAccountId:(NSString *)accountId
{
    NCChatMessage *message = [NCChatMessage messageWithDictionary:messageDict];
    if (message) {
        message.accountId = accountId;
        message.internalId = [NSString stringWithFormat:@"%@@%@@%ld", accountId, message.token, (long)message.messageId];
    }
    
    return message;
}

+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage isRoomLastMessage:(BOOL)isRoomLastMessage
{
    managedChatMessage.actorDisplayName = chatMessage.actorDisplayName;
    managedChatMessage.actorId = chatMessage.actorId;
    managedChatMessage.actorType = chatMessage.actorType;
    managedChatMessage.message = chatMessage.message;
    managedChatMessage.messageParametersJSONString = chatMessage.messageParametersJSONString;
    managedChatMessage.timestamp = chatMessage.timestamp;
    managedChatMessage.systemMessage = chatMessage.systemMessage;
    managedChatMessage.isReplyable = chatMessage.isReplyable;
    managedChatMessage.messageType = chatMessage.messageType;
    managedChatMessage.reactionsJSONString = chatMessage.reactionsJSONString;
    managedChatMessage.expirationTimestamp = chatMessage.expirationTimestamp;
    
    if (!isRoomLastMessage) {
        managedChatMessage.reactionsSelfJSONString = chatMessage.reactionsSelfJSONString;
    }
    
    if (!managedChatMessage.parentId && chatMessage.parentId) {
        managedChatMessage.parentId = chatMessage.parentId;
    }
}

+ (NSString *)primaryKey {
    return @"internalId";
}

- (id)copyWithZone:(NSZone *)zone
{
    NCChatMessage *messageCopy = [[NCChatMessage alloc] init];
    
    messageCopy.internalId = [_internalId copyWithZone:zone];
    messageCopy.accountId = [_accountId copyWithZone:zone];
    messageCopy.actorDisplayName = [_actorDisplayName copyWithZone:zone];
    messageCopy.actorId = [_actorId copyWithZone:zone];
    messageCopy.actorType = [_actorType copyWithZone:zone];
    messageCopy.messageId = _messageId;
    messageCopy.message = [_message copyWithZone:zone];
    messageCopy.messageParametersJSONString = [_messageParametersJSONString copyWithZone:zone];
    messageCopy.timestamp = _timestamp;
    messageCopy.token = [_token copyWithZone:zone];
    messageCopy.systemMessage = [_systemMessage copyWithZone:zone];
    messageCopy.isReplyable = _isReplyable;
    messageCopy.parentId = [_parentId copyWithZone:zone];
    messageCopy.referenceId = [_referenceId copyWithZone:zone];
    messageCopy.messageType = [_messageType copyWithZone:zone];
    messageCopy.reactionsJSONString = [_reactionsJSONString copyWithZone:zone];
    messageCopy.reactionsSelfJSONString = [_reactionsSelfJSONString copyWithZone:zone];
    messageCopy.expirationTimestamp = _expirationTimestamp;
    messageCopy.isTemporary = _isTemporary;
    messageCopy.sendingFailed = _sendingFailed;
    messageCopy.isGroupMessage = _isGroupMessage;
    messageCopy.isDeleting = _isDeleting;
    messageCopy.isOfflineMessage = _isOfflineMessage;
    messageCopy.isSilent = _isSilent;
    
    return messageCopy;
}

- (BOOL)isSystemMessage
{
    if (self.systemMessage && ![self.systemMessage isEqualToString:@""]) {
        return YES;
    }
    return NO;
}

- (BOOL)isEmojiMessage
{
    if (self.message && self.message.containsOnlyEmoji && self.message.emojiCount <= 3) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isUpdateMessage
{
    return  [self.systemMessage isEqualToString:@"message_deleted"] ||
            [self.systemMessage isEqualToString:@"reaction"] ||
            [self.systemMessage isEqualToString:@"reaction_revoked"] ||
            [self.systemMessage isEqualToString:@"reaction_deleted"] ||
            [self.systemMessage isEqualToString:@"poll_voted"];
}

- (BOOL)isDeletedMessage
{
    return [_messageType isEqualToString:kMessageTypeCommentDeleted];
}

- (BOOL)isVoiceMessage
{
    return [_messageType isEqualToString:kMessageTypeVoiceMessage];
}

- (BOOL)isCommandMessage
{
    return [_messageType isEqualToString:kMessageTypeCommand];
}

- (BOOL)isMessageFromUser:(NSString *)userId
{
    return [self.actorId isEqualToString:userId] && [self.actorType isEqualToString:@"users"];
}

- (BOOL)isDeletableForAccount:(TalkAccount *)account andParticipantType:(NCParticipantType)participantType
{
    NSInteger sixHoursAgoTimestamp = [[NSDate date] timeIntervalSince1970] - (6 * 3600);
    
    BOOL severCanDeleteMessage =
    // Delete normal messages
    ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDeleteMessages forAccountId:account.accountId] && [self.messageType isEqualToString:kMessageTypeComment] && !self.file && ![self isObjectShare]) ||
    // Delete files or shared objects
    ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityRichObjectDelete forAccountId:account.accountId] && (self.file || [self isVoiceMessage] ||[self isObjectShare]));
    
    BOOL userCanDeleteMessage = (participantType == kNCParticipantTypeOwner || participantType == kNCParticipantTypeModerator || [self isMessageFromUser:account.userId]);
    
    if (severCanDeleteMessage && userCanDeleteMessage && !self.isDeleting && self.timestamp >= sixHoursAgoTimestamp) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isObjectShare
{
    if ([self.message isEqualToString:@"{object}"] && [self.messageParameters objectForKey:@"object"]) {
        return YES;
    }
    return NO;
}

- (NSDictionary *)richObjectFromObjectShare
{
    NSDictionary *richObjectDict = @{};
    if ([self isObjectShare]) {
        NSDictionary *objectDict = [self.messageParameters objectForKey:@"object"];
        NSError *error;
        NSString *jsonString = @"";
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:objectDict
                                                           options:0
                                                             error:&error];
        if (!jsonData) {
            NSLog(@"Got an error: %@", error);
        } else {
            jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
        NCMessageParameter *parameter = [[NCMessageParameter alloc] initWithDictionary:objectDict];
        richObjectDict = @{@"objectType": parameter.type,
                           @"objectId": parameter.parameterId,
                           @"metaData": jsonString};
    }
    return richObjectDict;
}

- (NCMessageParameter *)file
{
    if (!_fileParameter) {
        for (NSDictionary *parameterDict in [[self messageParameters] allValues]) {
            NCMessageFileParameter *parameter = [[NCMessageFileParameter alloc] initWithDictionary:parameterDict];
            if (![parameter.type isEqualToString:@"file"]) {
                continue;
            }
            
            if (!_fileParameter) {
                _fileParameter = parameter;
            } else {
                // If there is more than one file in the message,
                // we don't display any preview.
                _fileParameter = nil;
                return nil;
            }
        }
    }

    return _fileParameter;
}

- (NCMessageLocationParameter *)geoLocation
{
    if (!_locationParameter) {
        for (NSDictionary *parameterDict in [[self messageParameters] allValues]) {
            NCMessageLocationParameter *parameter = [[NCMessageLocationParameter alloc] initWithDictionary:parameterDict] ;
            if ([parameter.type isEqualToString:@"geo-location"]) {
                _locationParameter = parameter;
                break;
            }
        }
    }

    return _locationParameter;
}

- (NCDeckCardParameter *)deckCard
{
    if (!_deckCardParameter) {
        for (NSDictionary *parameterDict in [[self messageParameters] allValues]) {
            NCDeckCardParameter *parameter = [[NCDeckCardParameter alloc] initWithDictionary:parameterDict] ;
            if ([parameter.type isEqualToString:@"deck-card"]) {
                _deckCardParameter = parameter;
                break;
            }
        }
    }

    return _deckCardParameter;
}

- (NCMessageParameter *)poll
{
    if ([self isObjectShare]) {
        NCMessageParameter *objectParameter = [[NCMessageParameter alloc] initWithDictionary:[self.messageParameters objectForKey:@"object"]];
        if ([objectParameter.type isEqualToString:@"talk-poll"]) {
            return objectParameter;
        }
    }
    
    return nil;
}

- (NCMessageParameter *)objectShareParameter
{
    if ([self isObjectShare]) {
        NCMessageParameter *objectParameter = [[NCMessageParameter alloc] initWithDictionary:[self.messageParameters objectForKey:@"object"]];
        return objectParameter;
    }
    
    return nil;
}

- (NSString *)objectShareLink;
{
    if (!_objectShareLink && [self isObjectShare]) {
        _objectShareLink = [[self.messageParameters objectForKey:@"object"] objectForKey:@"link"];
    }

    return _objectShareLink;
}

- (NSDictionary *)messageParameters
{
    NSDictionary *messageParametersDict = @{};
    NSData *data = [self.messageParametersJSONString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        NSError* error;
        NSDictionary* jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&error];
        if (jsonData) {
            messageParametersDict = jsonData;
        } else {
            NSLog(@"Error retrieving message parameters JSON data: %@", error);
        }
    }
    return messageParametersDict;
}

- (NSMutableAttributedString *)parsedMessage
{
    if (!self.message) {
        return nil;
    }
    
    NSString *originalMessage = self.file.contactName ? self.file.contactName : self.message;
    NSString *parsedMessage = originalMessage;
    NSError *error = nil;
    
    NSRegularExpression *parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^}]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    NSArray *matches = [parameterRegex matchesInString:originalMessage
                                               options:0
                                                 range:NSMakeRange(0, [originalMessage length])];
    
    // Find message parameters
    NSMutableArray *parameters = [NSMutableArray new];
    for (NSTextCheckingResult *match in matches) {
        NSString* parameter = [originalMessage substringWithRange:match.range];
        NSString *parameterKey = [[parameter stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                 stringByReplacingOccurrencesOfString:@"}" withString:@""];
        NSDictionary *parameterDict = [[self messageParameters] objectForKey:parameterKey];
        if (parameterDict) {
            NCMessageParameter *messageParameter = [[NCMessageParameter alloc] initWithDictionary:parameterDict] ;
            // Default replacement string is the parameter name
            NSString *replaceString = messageParameter.name;
            // Format user and call mentions
            if ([messageParameter.type isEqualToString:@"user"] || [messageParameter.type isEqualToString:@"guest"] || [messageParameter.type isEqualToString:@"call"]) {
                replaceString = [NSString stringWithFormat:@"@%@", [parameterDict objectForKey:@"name"]];
            }
            parsedMessage = [parsedMessage stringByReplacingOccurrencesOfString:parameter withString:replaceString];
            // Calculate parameter range
            NSRange searchRange = NSMakeRange(0,parsedMessage.length);
            if (parameters.count > 0) {
                NCMessageParameter *lastParameter = [parameters objectAtIndex:parameters.count - 1];
                NSInteger newRangeLocation = lastParameter.range.location + lastParameter.range.length;
                searchRange = NSMakeRange(newRangeLocation, parsedMessage.length - newRangeLocation);
            }
            messageParameter.range = [parsedMessage rangeOfString:replaceString options:0 range:searchRange];
            [parameters addObject:messageParameter];
        }
    }
    
    UIColor *defaultColor = [NCAppBranding chatForegroundColor];
    UIColor *highlightedColor = [NCAppBranding elementColor];
    
    NSMutableAttributedString *attributedMessage = [[NSMutableAttributedString alloc] initWithString:parsedMessage];
    [attributedMessage addAttribute:NSForegroundColorAttributeName value:defaultColor range:NSMakeRange(0,parsedMessage.length)];
    
    if (self.isEmojiMessage) {
        [attributedMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:36.0f] range:NSMakeRange(0,parsedMessage.length)];
    } else {
        [attributedMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16.0f] range:NSMakeRange(0,parsedMessage.length)];
    }
    
    for (NCMessageParameter *param in parameters) {
        //Set color for mentions
        if ([param.type isEqualToString:@"user"] || [param.type isEqualToString:@"guest"] || [param.type isEqualToString:@"call"]) {
            [attributedMessage addAttribute:NSForegroundColorAttributeName value:(param.shouldBeHighlighted) ? highlightedColor : defaultColor range:param.range];
            [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:param.range];
        }
        //Create a link if parameter contains a link
        else if (param.link) {
            // Do not create links for files. File preview images will redirect to files client or browser.
            if ([param.type isEqualToString:@"file"]) {
                [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:param.range];
            } else {
                [attributedMessage addAttribute:NSLinkAttributeName value:param.link range:param.range];
            }
        }
    }
    
    return attributedMessage;
}

- (NSMutableAttributedString *)parsedMessageForChat
{
    // In some circumstances we want/need to hide the message in the chat, but still want to show it in other parts like the conversation list
    if ([self getDeckCardUrlForReferenceProvider]) {
        return nil;
    }

    return self.parsedMessage;
}

- (NSMutableAttributedString *)systemMessageFormat
{
    NSMutableAttributedString *message = [self parsedMessage];

    //TODO: Further adjust for dark-mode ?
    [message addAttribute:NSForegroundColorAttributeName value:[UIColor tertiaryLabelColor] range:NSMakeRange(0,message.length)];
    
    return message;
}

- (NSString *)sendingMessage
{
    NSString *resultMessage = [[self.message copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    for (NSString *parameterKey in self.messageParameters.allKeys) {
        NCMessageParameter *parameter = [[NCMessageParameter alloc] initWithDictionary:[self.messageParameters objectForKey:parameterKey]];
        NSString *parameterKeyString = [[NSString alloc] initWithFormat:@"{%@}", parameterKey];
        resultMessage = [resultMessage stringByReplacingOccurrencesOfString:parameterKeyString withString:parameter.mentionId];
    }
    
    return resultMessage;
}

- (NCChatMessage *)parent
{
    if (self.parentId) {
        NCChatMessage *unmanagedChatMessage = nil;
        NCChatMessage *managedChatMessage = [NCChatMessage objectsWhere:@"internalId = %@", self.parentId].firstObject;
        if (managedChatMessage) {
            unmanagedChatMessage = [[NCChatMessage alloc] initWithValue:managedChatMessage];
        }
        return unmanagedChatMessage;
    }
    
    return nil;
}

- (NSInteger)parentMessageId
{
    NSInteger messageId = self.parent ? self.parent.messageId : -1;
    return messageId;
}

- (NSMutableArray *)temporaryReactions
{
    if (!_temporaryReactions) {
        _temporaryReactions = [NSMutableArray new];
    }
    return _temporaryReactions;
}

- (BOOL)isReactionBeingModified:(NSString *)reaction
{
    for (NCChatReaction *temporaryReaction in [self temporaryReactions]) {
        if ([temporaryReaction.reaction isEqualToString:reaction]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeReactionFromTemporayReactions:(NSString *)reaction
{
    NCChatReaction *removeReaction = nil;
    for (NCChatReaction *temporaryReaction in [self temporaryReactions]) {
        if ([temporaryReaction.reaction isEqualToString:reaction]) {
            removeReaction = temporaryReaction;
            break;
        }
    }
    if (removeReaction) {
        [[self temporaryReactions] removeObject:removeReaction];
    }
}

- (void)addTemporaryReaction:(NSString *)reaction
{
    NCChatReaction *temporaryReaction = [[NCChatReaction alloc] init];
    temporaryReaction.reaction = reaction;
    temporaryReaction.state = NCChatReactionStateAdding;
    [[self temporaryReactions] addObject:temporaryReaction];
}

- (void)removeReactionTemporarily:(NSString *)reaction
{
    NCChatReaction *temporaryReaction = [[NCChatReaction alloc] init];
    temporaryReaction.reaction = reaction;
    temporaryReaction.state = NCChatReactionStateRemoving;
    [[self temporaryReactions] addObject:temporaryReaction];
}

- (void)mergeTemporaryReactionsWithReactions:(NSMutableArray *)reactions
{
    for (NCChatReaction *temporaryReaction in [self temporaryReactions]) {
        if (temporaryReaction.state == NCChatReactionStateAdding) {
            [self addTemporaryReaction:temporaryReaction.reaction inReactions:reactions];
        } else if (temporaryReaction.state == NCChatReactionStateRemoving) {
            [self removeReactionTemporarily:temporaryReaction.reaction inReactions:reactions];
        }
    }
}

- (void)addTemporaryReaction:(NSString *)reaction inReactions:(NSMutableArray *)reactions
{
    BOOL includedReaction = NO;
    for (NCChatReaction *currentReaction in reactions) {
        if ([currentReaction.reaction isEqualToString:reaction]) {
            currentReaction.count += 1;
            currentReaction.userReacted = YES;
            includedReaction = YES;
        }
    }
    if (!includedReaction) {
        NCChatReaction *newReaction = [[NCChatReaction alloc] init];
        newReaction.reaction = reaction;
        newReaction.count = 1;
        newReaction.userReacted = YES;
        [reactions addObject:newReaction];
    }
}

- (void)removeReactionTemporarily:(NSString *)reaction inReactions:(NSMutableArray *)reactions
{
    NCChatReaction *removeReaction = nil;
    for (NCChatReaction *currentReaction in reactions) {
        if ([currentReaction.reaction isEqualToString:reaction]) {
            currentReaction.state = NCChatReactionStateRemoving;
            if (currentReaction.count > 1) {
                currentReaction.count -= 1;
                currentReaction.userReacted = NO;
            } else {
                removeReaction = currentReaction;
            }
        }
    }
    if (removeReaction) {
        [reactions removeObject:removeReaction];
    }
}

- (NSDictionary *)reactionsDictionary
{
    NSDictionary *reactionsDictionary = @{};
    NSData *data = [self.reactionsJSONString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        NSError* error;
        NSDictionary* jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&error];
        if (jsonData) {
            reactionsDictionary = jsonData;
        } else {
            NSLog(@"Error retrieving reactions JSON data: %@", error);
        }
    }
    return reactionsDictionary;
}

- (NSArray *)reactionsSelfArray
{
    NSArray *reactionsSelfArray = @[];
    NSData *data = [self.reactionsSelfJSONString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        NSError* error;
        NSArray* jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                            options:0
                                                              error:&error];
        if (jsonData) {
            reactionsSelfArray = jsonData;
        } else {
            NSLog(@"Error retrieving reactionsSelf JSON data: %@", error);
        }
    }
    return reactionsSelfArray;
}

- (NSMutableArray *)reactionsArray
{
    NSMutableArray *reactionsArray = [NSMutableArray new];
    // Grab message reactions
    NSDictionary *reactionsDict = [self reactionsDictionary];
    for (NSString *reactionKey in reactionsDict.allKeys) {
        // We need to keep this check for users who installed v14.0 (beta 1)
        if ([reactionKey isEqualToString:@"self"]) {continue;}
        NCChatReaction *reaction = [NCChatReaction initWithReaction:reactionKey andCount:[[reactionsDict objectForKey:reactionKey] integerValue]];
        [reactionsArray addObject:reaction];
    }
    // Set flag for own reactions
    for (NSString *ownReaction in [self reactionsSelfArray]) {
        for (NCChatReaction *reaction in reactionsArray) {
            if ([reaction.reaction isEqualToString:ownReaction]) {
                reaction.userReacted = YES;
            }
        }
    }
    // Merge with temporary reactions
    [self mergeTemporaryReactionsWithReactions:reactionsArray];
    // Sort by reactions count
    NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"count" ascending:NO];
    NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
    [reactionsArray sortUsingDescriptors:descriptors];
    return reactionsArray;
}

- (BOOL)isReferenceApiSupported
{
    // Check capabilities directly, otherwise NCSettingsController introduces new dependencies in NotificationServiceExtension
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities  = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    if (serverCapabilities) {
        return serverCapabilities.referenceApiSupported;
    }
    return NO;
}

- (NSString *)getDeckCardUrlForReferenceProvider
{
    // Check if the message is a shared deck card and a reference provider can be used to retrieve details
    if (self.deckCard != nil && self.deckCard.link != nil && [self.deckCard.link length] > 0) {
        if ([self isReferenceApiSupported]) {
            return _deckCardParameter.link;
        }
    }

    return nil;
}

- (BOOL)containsURL
{
    if (_urlDetectionDone) {
        return ([_urlDetected length] != 0);
    }

    if (![self isReferenceApiSupported]) {
        _urlDetectionDone = YES;
        return NO;
    }

    NSString *deckCardUrl = [self getDeckCardUrlForReferenceProvider];

    if (deckCardUrl != nil) {
        _urlDetectionDone = YES;
        _urlDetected = deckCardUrl;
        return YES;
    }

    NSDataDetector *dataDetector = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink error:nil];
    NSArray *urlMatches = [dataDetector matchesInString:self.message options:0 range:NSMakeRange(0, [self.message length])];

    _urlDetectionDone = YES;

    for (NSTextCheckingResult *match in urlMatches) {
        NSURL *url = [match URL];
        NSString *scheme = [url scheme];

        // Check that the scheme is either https or http, because other schemes (like mailto) would be recognized as well
        if ([[scheme lowercaseString] isEqualToString:@"http"] || [[scheme lowercaseString] isEqualToString:@"https"]) {
            _urlDetected = [url absoluteString];
            return true;
        }
    }

    return false;
}

- (void)getReferenceDataWithCompletionBlock:(GetReferenceDataCompletionBlock)block
{
    if (_referenceDataDone) {
        if (block) {
            block(self, _referenceData, _urlDetected);
        }
    } else {
        TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:_accountId];

        [[NCAPIController sharedInstance] getReferenceForUrlString:_urlDetected forAccount:account withCompletionBlock:^(NSDictionary *references, NSError *error) {
            if (block) {
                block(self, references, self->_urlDetected);
            }

            self->_referenceData = references;
            self->_referenceDataDone = YES;
        }];
    }
}

- (BOOL)isSameMessage:(NCChatMessage *)message
{
    if (self.isTemporary) {
        if ([self.referenceId isEqualToString:message.referenceId]) {
            return YES;
        }
    } else {
        if (self.messageId == message.messageId) {
            return YES;
        }
    }

    return NO;
}

@end
