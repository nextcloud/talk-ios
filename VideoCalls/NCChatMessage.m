//
//  NCChatMessage.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatMessage.h"

#import "NCSettingsController.h"

NSInteger const kChatMessageMaxGroupNumber      = 10;
NSInteger const kChatMessageGroupTimeDifference = 30;

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
    
    if (!managedChatMessage.parentId && chatMessage.parentId) {
        managedChatMessage.parentId = chatMessage.parentId;
    }
}

+ (NSString *)primaryKey {
    return @"internalId";
}

- (BOOL)isSystemMessage
{
    if (self.systemMessage && ![self.systemMessage isEqualToString:@""]) {
        return YES;
    }
    return NO;
}

- (NCMessageParameter *)file;
{
    NCMessageParameter *fileParam = nil;
    for (NSDictionary *parameterDict in [[self messageParameters] allValues]) {
        NCMessageParameter *parameter = [NCMessageParameter parameterWithDictionary:parameterDict] ;
        if ([parameter.type isEqualToString:@"file"]) {
            if (!fileParam) {
                fileParam = parameter;
            } else {
                // If there is more than one file in the message,
                // we don't display any preview.
                return nil;
            }
        }
    }
    return fileParam;
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
    NSString *originalMessage = self.message;
    NSString *parsedMessage = originalMessage;
    NSError *error = nil;
    
    NSRegularExpression *parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^}]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    NSArray *matches = [parameterRegex matchesInString:originalMessage
                                               options:0
                                                 range:NSMakeRange(0, [originalMessage length])];
    
    // Find message parameters
    NSMutableArray *parameters = [NSMutableArray arrayWithCapacity:matches.count];
    for (int i = 0; i < matches.count; i++) {
        NSTextCheckingResult *match = [matches objectAtIndex:i];
        NSString* parameter = [originalMessage substringWithRange:match.range];
        NSString *parameterKey = [[parameter stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                 stringByReplacingOccurrencesOfString:@"}" withString:@""];
        NSDictionary *parameterDict = [[self messageParameters] objectForKey:parameterKey];
        if (parameterDict) {
            NCMessageParameter *messageParameter = [NCMessageParameter parameterWithDictionary:parameterDict] ;
            // Default replacement string is the parameter name
            NSString *replaceString = messageParameter.name;
            // Format user and call mentions
            if ([messageParameter.type isEqualToString:@"user"] || [messageParameter.type isEqualToString:@"guest"] || [messageParameter.type isEqualToString:@"call"]) {
                replaceString = [NSString stringWithFormat:@"@%@", [parameterDict objectForKey:@"name"]];
            }
            parsedMessage = [parsedMessage stringByReplacingOccurrencesOfString:parameter withString:replaceString];
            // Calculate parameter range
            NSRange searchRange = NSMakeRange(0,parsedMessage.length);
            if (i > 0) {
                NCMessageParameter *lastParameter = [parameters objectAtIndex:i-1];
                NSInteger newRangeLocation = lastParameter.range.location + lastParameter.range.length;
                searchRange = NSMakeRange(newRangeLocation, parsedMessage.length - newRangeLocation);
            }
            messageParameter.range = [parsedMessage rangeOfString:replaceString options:0 range:searchRange];
            [parameters insertObject:messageParameter atIndex:i];
        }
    }
    
    NSMutableAttributedString *attributedMessage = [[NSMutableAttributedString alloc] initWithString:parsedMessage];
    [attributedMessage addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16.0f] range:NSMakeRange(0,parsedMessage.length)];
    [attributedMessage addAttribute:NSForegroundColorAttributeName value:[UIColor darkGrayColor] range:NSMakeRange(0,parsedMessage.length)];
    
    for (NCMessageParameter *param in parameters) {
        //Set color for mentions
        if ([param.type isEqualToString:@"user"] || [param.type isEqualToString:@"guest"] || [param.type isEqualToString:@"call"]) {
            UIColor *defaultColor = [UIColor darkGrayColor];
            UIColor *highlightedColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
            [attributedMessage addAttribute:NSForegroundColorAttributeName value:(param.shouldBeHighlighted) ? highlightedColor : defaultColor range:param.range];
            [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:param.range];
        }
        //Create a link if parameter contains a link
        else if (param.link) {
            // Do not create links for files. File preview images will redirect to files client or browser.
            if ([param.type isEqualToString:@"file"]) {
                [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:param.range];
            } else {
                [attributedMessage addAttribute: NSLinkAttributeName value:param.link range:param.range];
            }
        }
    }
    
    return attributedMessage;
}

- (NSMutableAttributedString *)systemMessageFormat
{
    NSMutableAttributedString *message = [self parsedMessage];
    [message addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:0 alpha:0.3] range:NSMakeRange(0,message.length)];
    
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
