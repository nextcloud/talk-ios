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
    message.messageParameters = [messageDict objectForKey:@"messageParameters"];
    message.timestamp = [[messageDict objectForKey:@"timestamp"] integerValue];
    message.token = [messageDict objectForKey:@"token"];
    message.systemMessage = [messageDict objectForKey:@"systemMessage"];
    
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
    
    if (![message.messageParameters isKindOfClass:[NSDictionary class]]) {
        message.messageParameters = @{};
    }
    
    return message;
}

- (BOOL)isSystemMessage
{
    if (_systemMessage && ![_systemMessage isEqualToString:@""]) {
        return YES;
    }
    return NO;
}

- (NCMessageParameter *)file;
{
    NCMessageParameter *fileParam = nil;
    for (NSDictionary *parameterDict in _messageParameters.allValues) {
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

- (NSMutableAttributedString *)parsedMessage
{
    NSString *originalMessage = _message;
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
        NSDictionary *parameterDict = [_messageParameters objectForKey:parameterKey];
        if (parameterDict) {
            NCMessageParameter *messageParameter = [NCMessageParameter parameterWithDictionary:parameterDict] ;
            // Default replacement string is the parameter name
            NSString *replaceString = messageParameter.name;
            // Format user and call mentions
            if ([messageParameter.type isEqualToString:@"user"] || [messageParameter.type isEqualToString:@"call"]) {
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
        if ([param.type isEqualToString:@"user"] || [param.type isEqualToString:@"call"]) {
            UIColor *defaultColor = [UIColor darkGrayColor];
            UIColor *highlightedColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
            [attributedMessage addAttribute:NSForegroundColorAttributeName value:(param.shouldBeHighlighted) ? highlightedColor : defaultColor range:param.range];
            [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:param.range];
        }
        //Create a link if parameter contains a link
        else if (param.link) {
            [attributedMessage addAttribute: NSLinkAttributeName value:param.link range:param.range];
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

@end
