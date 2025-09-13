/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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
    NSString *_threadTitle;
    NSMutableArray *_temporaryReactions;
    BOOL _urlDetectionDone;
    NSString *_urlDetected;
    BOOL _referenceDataDone;
    NSDictionary *_referenceData;
    NSMutableAttributedString *_parsedMarkdownForChat;
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
    message.isMarkdownMessage = [[messageDict objectForKey:@"markdown"] boolValue];
    message.lastEditActorId = [messageDict objectForKey:@"lastEditActorId"];
    message.lastEditActorType = [messageDict objectForKey:@"lastEditActorType"];
    message.lastEditActorDisplayName = [messageDict objectForKey:@"lastEditActorDisplayName"];
    message.lastEditTimestamp = [[messageDict objectForKey:@"lastEditTimestamp"] integerValue];
    message.isSilent = [[messageDict objectForKey:@"silent"] boolValue];
    message.threadId = [[messageDict objectForKey:@"threadId"] integerValue];
    message.isThread = [[messageDict objectForKey:@"isThread"] boolValue];
    message.threadTitle = [messageDict objectForKey:@"threadTitle"];
    message.threadReplies = [[messageDict objectForKey:@"threadReplies"] integerValue];

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

        NCChatMessage *parent = [NCChatMessage messageWithDictionary:[messageDict objectForKey:@"parent"] andAccountId:accountId];
        message.parentId = parent.internalId;
    }
    
    return message;
}

+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage isRoomLastMessage:(BOOL)isRoomLastMessage;
{
    int previewImageHeight = 0;
    int previewImageWidth = 0;

    // Try to keep our locally saved previewImageHeight when updating this messages with the server message
    // This happens when updating the last message of a room for example
    if (managedChatMessage.file && chatMessage.file) {
        // Only do this, if the new message does not include a height, to prevent an infinite recursion
        if (managedChatMessage.file.previewImageHeight > 0 && chatMessage.file.previewImageHeight == 0) {
            previewImageHeight = managedChatMessage.file.previewImageHeight;
        }

        if (managedChatMessage.file.previewImageWidth > 0 && chatMessage.file.previewImageWidth == 0) {
            previewImageWidth = managedChatMessage.file.previewImageWidth;
        }
    }

    NSDictionary *fileParameterDict;

    if (isRoomLastMessage && managedChatMessage.file && chatMessage.file) {
        // We need to keep the file information when updating from the last update message,
        // because the file information might be inaccurate on the last message
        fileParameterDict = [managedChatMessage.messageParameters objectForKey:@"file"];
    }

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
    managedChatMessage.isMarkdownMessage = chatMessage.isMarkdownMessage;
    managedChatMessage.lastEditActorId = chatMessage.lastEditActorId;
    managedChatMessage.lastEditActorType = chatMessage.lastEditActorType;
    managedChatMessage.lastEditActorDisplayName = chatMessage.lastEditActorDisplayName;
    managedChatMessage.lastEditTimestamp = chatMessage.lastEditTimestamp;

    if (!isRoomLastMessage) {
        managedChatMessage.reactionsSelfJSONString = chatMessage.reactionsSelfJSONString;
        managedChatMessage.threadId = chatMessage.threadId;
        managedChatMessage.isThread = chatMessage.isThread;
        managedChatMessage.threadTitle = chatMessage.threadTitle;
        managedChatMessage.threadReplies = chatMessage.threadReplies;
    }

    if (fileParameterDict) {
        NSMutableDictionary *messageParameterDict = [[NSMutableDictionary alloc] initWithDictionary:managedChatMessage.messageParameters];
        [messageParameterDict setObject:fileParameterDict forKey:@"file"];

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messageParameterDict
                                                           options:0
                                                             error:nil];

        if (jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

            // Only the JSON String is stored inside of the database
            managedChatMessage.messageParametersJSONString = jsonString;
        }
    }

    if (!managedChatMessage.parentId && chatMessage.parentId) {
        managedChatMessage.parentId = chatMessage.parentId;
    }

    if (previewImageHeight > 0 && previewImageWidth > 0) {
        [managedChatMessage setPreviewImageSize:CGSizeMake(previewImageWidth, previewImageHeight)];
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
    messageCopy.isMarkdownMessage = _isMarkdownMessage;
    messageCopy.lastEditActorId = _lastEditActorId;
    messageCopy.lastEditActorType = _lastEditActorType;
    messageCopy.lastEditActorDisplayName = _lastEditActorDisplayName;
    messageCopy.lastEditTimestamp = _lastEditTimestamp;
    messageCopy.threadId = _threadId;
    messageCopy.isThread = _isThread;
    messageCopy.threadTitle = _threadTitle;
    messageCopy.threadReplies = _threadReplies;

    return messageCopy;
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

- (NSString *)objectShareLink;
{
    if (!_objectShareLink && [self isObjectShare]) {
        _objectShareLink = [[self.messageParameters objectForKey:@"object"] objectForKey:@"link"];
    }

    return _objectShareLink;
}

- (NSMutableAttributedString *)parsedMessage
{
    if (!self.message) {
        return nil;
    }

    NSString *originalMessage = self.file.contactName ? self.file.contactName : self.message;
    if (self.collapsedMessage && self.isCollapsed) {
        originalMessage = self.collapsedMessage;
    }
    NSString *parsedMessage = originalMessage;
    NSError *error = nil;

    static NSRegularExpression *parameterRegex;

    if (!parameterRegex) {
        parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([a-z\\-_.0-9]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    }

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
        if (self.collapsedMessage && self.isCollapsed) {
            parameterDict = [[self collapsedMessageParameters] objectForKey:parameterKey];
        }
        if (parameterDict) {
            NCMessageParameter *messageParameter = [[NCMessageParameter alloc] initWithDictionary:parameterDict] ;
            // Default replacement string is the parameter name
            NSString *replaceString = messageParameter.name;
            // Format user and call mentions
            if ([messageParameter isMention]) {
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

    UIColor *defaultColor = [UIColor labelColor];

    NSMutableAttributedString *attributedMessage = [[NSMutableAttributedString alloc] initWithString:parsedMessage];
    [attributedMessage addAttribute:NSForegroundColorAttributeName value:defaultColor range:NSMakeRange(0, parsedMessage.length)];

    if (self.isEmojiMessage) {
        [attributedMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:36.0f] range:NSMakeRange(0, parsedMessage.length)];
    } else {
        [attributedMessage addAttribute:NSFontAttributeName value:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] range:NSMakeRange(0, parsedMessage.length)];
    }

    UIColor *highlightedColor = nil;

    for (NCMessageParameter *param in parameters) {
        //Set color for mentions
        if ([param isMention]) {
            if (param.shouldBeHighlighted) {
                if (!highlightedColor) {
                    // Only get the elementColor if we really need it to reduce realm queries
                    highlightedColor = [NCAppBranding elementColor];
                }

                [attributedMessage addAttribute:NSForegroundColorAttributeName value:highlightedColor range:param.range];
            } else {
                [attributedMessage addAttribute:NSForegroundColorAttributeName value:defaultColor range:param.range];
            }

            [attributedMessage addAttribute:NSFontAttributeName value:[UIFont preferredFontFor:UIFontTextStyleBody weight:UIFontWeightBold] range:param.range];
        }
        //Create a link if parameter contains a link
        else if (param.link) {
            // Do not create links for files. File preview images will redirect to files client or browser.
            if ([param.type isEqualToString:@"file"]) {
                [attributedMessage addAttribute:NSFontAttributeName value:[UIFont preferredFontFor:UIFontTextStyleBody weight:UIFontWeightBold] range:param.range];
            } else {
                [attributedMessage addAttribute:NSLinkAttributeName value:param.link range:param.range];
            }
        }
    }

    return attributedMessage;
}

- (NSMutableAttributedString *)parsedMarkdown
{
    NSMutableAttributedString *parsedMessage = self.parsedMessage;

    if (!parsedMessage) {
        return nil;
    }

    if (!_isMarkdownMessage) {
        return parsedMessage;
    }

    return [SwiftMarkdownObjCBridge parseMarkdownWithMarkdownString:parsedMessage];
}

- (NSMutableAttributedString *)parsedMarkdownForChat
{
    if (_parsedMarkdownForChat) {
        return _parsedMarkdownForChat;
    }

    // In some circumstances we want/need to hide the message in the chat, but still want to show it in other parts like the conversation list
    if ([self getDeckCardUrlForReferenceProvider]) {
        return nil;
    }

    // Hide the filename for image and video files, in case there's no caption
    if (self.file && self.file.previewAvailable && ([NCUtils isImageWithFileType:self.file.mimetype] || [NCUtils isVideoWithFileType:self.file.mimetype])) {
        if ([self.message isEqualToString:@"{file}"]) {
            return nil;
        }
    }

    NSMutableAttributedString *parsedMessage = self.parsedMessage;

    if (!parsedMessage) {
        return nil;
    }

    if (!_isMarkdownMessage) {
        return parsedMessage;
    }

    _parsedMarkdownForChat = [SwiftMarkdownObjCBridge parseMarkdownWithMarkdownString:parsedMessage];

    return _parsedMarkdownForChat;
}

- (NSMutableArray *)temporaryReactions
{
    if (!_temporaryReactions) {
        _temporaryReactions = [NSMutableArray new];
    }
    return _temporaryReactions;
}

- (void)mergeTemporaryReactionsWithReactions:(NSMutableArray *)reactions
{
    for (NCChatReaction *temporaryReaction in [self temporaryReactions]) {
        if (temporaryReaction.state == NCChatReactionStateAdding || temporaryReaction.state == NCChatReactionStateAdded) {
            [self addTemporaryReaction:temporaryReaction.reaction inReactions:reactions];
        } else if (temporaryReaction.state == NCChatReactionStateRemoving || temporaryReaction.state == NCChatReactionStateRemoved) {
            [self removeReactionTemporarily:temporaryReaction.reaction inReactions:reactions];
        }
    }
}

- (void)addTemporaryReaction:(NSString *)reaction inReactions:(NSMutableArray *)reactions
{
    BOOL includedReaction = NO;
    for (NCChatReaction *currentReaction in reactions) {
        if ([currentReaction.reaction isEqualToString:reaction]) {
            // Do not need to increase the count since it was already increased on "adding" state
            if (currentReaction.userReacted) {return;}

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
        if ([currentReaction.reaction isEqualToString:reaction] && currentReaction.userReacted) {
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

- (NSMutableArray<NCChatReaction *> *)reactionsArray
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
    if (!self.message) {
        return NO;
    }
    
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

- (void)setPreviewImageSize:(CGSize)size
{
    // Since the messageParameters property is a non-mutable dictionary, we create a mutable copy
    NSMutableDictionary *messageParameterDict = [[NSMutableDictionary alloc] initWithDictionary:self.messageParameters];
    NSMutableDictionary *fileParameterDict = [[NSMutableDictionary alloc] initWithDictionary:[messageParameterDict objectForKey:@"file"]];

    if (!fileParameterDict) {
        return;
    }

    [messageParameterDict setObject:fileParameterDict forKey:@"file"];
    [fileParameterDict setObject:@(size.height) forKey:@"preview-image-height"];
    [fileParameterDict setObject:@(size.width) forKey:@"preview-image-width"];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messageParameterDict
                                                       options:0
                                                         error:nil];

    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        // Only the JSON String is stored inside of the database
        self.messageParametersJSONString = jsonString;

        // Since we previously accessed the 'file' property, it would not be created from the JSON String again
        // Manually set it for the lifetime of this message
        self.file.previewImageHeight = size.height;
        self.file.previewImageWidth = size.width;

        // Save our changes to the database
        RLMRealm *realm = [RLMRealm defaultRealm];

        void (^update)(void) = ^void(){
            NCChatMessage *managedMessage = [NCChatMessage objectsWhere:@"internalId = %@", self.internalId].firstObject;
            [NCChatMessage updateChatMessage:managedMessage withChatMessage:self isRoomLastMessage:NO];
        };

        if ([realm inWriteTransaction]) {
            update();
        } else {
            [realm transactionWithBlock:^{
                update();
            }];
        }
    }
}

- (BOOL)isThreadOriginalMessage
{
    return self.threadId > 0 && self.isThread && self.threadId == self.messageId;
}

- (BOOL)isThreadMessage
{
    return self.threadId > 0 && self.isThread && self.threadId != self.messageId;
}

- (NSString *)threadTitle;
{
    if (!_threadTitle && [self isThreadMessage]) {
        _threadTitle = [[self.messageParameters objectForKey:@"title"] objectForKey:@"name"];
    }

    return _threadTitle;
}

@end
