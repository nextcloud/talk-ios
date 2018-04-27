//
//  NCChatMessage.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatMessage.h"

#import "NCChatMention.h"
#import "NCSettingsController.h"

@implementation NCChatMessage

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict
{
    if (!messageDict) {
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
    
    id actorDisplayName = [messageDict objectForKey:@"actorDisplayName"];
    if (!actorDisplayName || [actorDisplayName isEqualToString:@""]) {
        message.actorDisplayName = @"Guest";
    } else {
        if ([actorDisplayName isKindOfClass:[NSString class]]) {
            message.actorDisplayName = actorDisplayName;
        } else {
            message.actorDisplayName = [actorDisplayName stringValue];
        }
    }
    
    return message;
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
    
    // Find mentions
    NSMutableArray *mentions = [NSMutableArray arrayWithCapacity:matches.count];
    for (int i = 0; i < matches.count; i++) {
        NSTextCheckingResult *match = [matches objectAtIndex:i];
        NSString* parameter = [originalMessage substringWithRange:match.range];
        NSString *parameterId = [[parameter stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                 stringByReplacingOccurrencesOfString:@"}" withString:@""];
        NSDictionary *parameterDict = [_messageParameters objectForKey:parameterId];
        if (parameterDict) {
            NSString *mentionName = [NSString stringWithFormat:@"@%@", [parameterDict objectForKey:@"name"]];
            NSString *mentionUserId = [parameterDict objectForKey:@"id"];
            parsedMessage = [parsedMessage stringByReplacingOccurrencesOfString:parameter withString:mentionName];
            
            NSRange searchRange = NSMakeRange(0,parsedMessage.length);
            if (i > 0) {
                NCChatMention *lastMention = [mentions objectAtIndex:i-1];
                NSInteger newRangeLocation = lastMention.range.location + lastMention.range.length;
                searchRange = NSMakeRange(newRangeLocation, parsedMessage.length - newRangeLocation);
            }
            NSRange foundRange = [parsedMessage rangeOfString:mentionName options:0 range:searchRange];
            
            NCChatMention *chatMention = [[NCChatMention alloc] init];
            chatMention.range = foundRange;
            chatMention.userId = mentionUserId;
            chatMention.name = mentionName;
            chatMention.ownMention = ([[NCSettingsController sharedInstance].ncUserId isEqualToString:mentionUserId]);
            [mentions insertObject:chatMention atIndex:i];
        }
    }
    
    // Create attributed strings for mentions
    NSMutableAttributedString *attributedMessage = [[NSMutableAttributedString alloc] initWithString:parsedMessage];
    for (NCChatMention *chatMention in mentions) {
        UIColor *mentionTextColor = [UIColor darkGrayColor];
        UIColor *mentionColor = [UIColor colorWithRed:0.90 green:0.90 blue:0.90 alpha:1.0]; //#e6e6e6
        UIColor *ownMentionTextColor = [UIColor whiteColor];
        UIColor *ownMentionColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
        [attributedMessage addAttribute:NSBackgroundColorAttributeName value:(chatMention.ownMention) ? ownMentionColor : mentionColor range:chatMention.range];
        [attributedMessage addAttribute:NSForegroundColorAttributeName value:(chatMention.ownMention) ? ownMentionTextColor : mentionTextColor range:chatMention.range];
        [attributedMessage addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:16.0f] range:chatMention.range];
    }
    
    return attributedMessage;
}

@end
