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

#import "NCAppBranding.h"
#import "NextcloudTalk-Swift.h"

NSInteger const kChatMessageGroupTimeDifference = 30;

NSString * const kMessageTypeComment        = @"comment";
NSString * const kMessageTypeCommentDeleted = @"comment_deleted";
NSString * const kMessageTypeSystem         = @"system";
NSString * const kMessageTypeCommand        = @"command";
NSString * const kMessageTypeVoiceMessage   = @"voice-message";

@interface NCChatMessage ()
{
    NCMessageFileParameter *_fileParameter;
    NCMessageLocationParameter *_locationParameter;
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

+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage
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
    messageCopy.isTemporary = _isTemporary;
    messageCopy.sendingFailed = _sendingFailed;
    messageCopy.isGroupMessage = _isGroupMessage;
    messageCopy.isDeleting = _isDeleting;
    
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

- (BOOL)isMessageFromUser:(NSString *)userId
{
    return [self.actorId isEqualToString:userId] && [self.actorType isEqualToString:@"users"];
}

- (BOOL)isDeletableForAccount:(TalkAccount *)account andParticipantType:(NCParticipantType)participantType
{
    NSInteger sixHoursAgoTimestamp = [[NSDate date] timeIntervalSince1970] - (6 * 3600);
    BOOL canServerDeleteMessages = [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityDeleteMessages forAccountId:account.accountId];
    if ([self.messageType isEqualToString:kMessageTypeComment] && !self.isDeleting && !self.file && self.timestamp >= sixHoursAgoTimestamp && canServerDeleteMessages &&
        (participantType == kNCParticipantTypeOwner || participantType == kNCParticipantTypeModerator || [self isMessageFromUser:account.userId])) {
        return YES;
    }
    
    return NO;
}

- (NCMessageParameter *)file;
{
    if (!_fileParameter) {
        for (NSDictionary *parameterDict in [[self messageParameters] allValues]) {
            NCMessageFileParameter *parameter = [[NCMessageFileParameter alloc] initWithDictionary:parameterDict] ;
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

- (NCMessageLocationParameter *)geoLocation;
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

- (NSMutableAttributedString *)systemMessageFormat
{
    NSMutableAttributedString *message = [self parsedMessage];
    
    if (@available(iOS 13.0, *)) {
        //TODO: Further adjust for dark-mode ?
        [message addAttribute:NSForegroundColorAttributeName value:[UIColor tertiaryLabelColor] range:NSMakeRange(0,message.length)];
    } else {
        [message addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:0 alpha:0.3] range:NSMakeRange(0,message.length)];
    }
    
    
    return message;
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

@end
