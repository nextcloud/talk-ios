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

#import "NCNotification.h"

@implementation NCNotification

+ (instancetype)notificationWithDictionary:(NSDictionary *)notificationDict
{
    if (!notificationDict || ![notificationDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NCNotification *notification = [[NCNotification alloc] init];
    notification.notificationId = [[notificationDict objectForKey:@"notification_id"] integerValue];
    notification.app = [notificationDict objectForKey:@"app"];
    notification.objectId = [notificationDict objectForKey:@"object_id"];
    notification.objectType = [notificationDict objectForKey:@"object_type"];
    notification.subject = [notificationDict objectForKey:@"subject"];
    notification.subjectRich = [notificationDict objectForKey:@"subjectRich"];
    notification.subjectRichParameters = [notificationDict objectForKey:@"subjectRichParameters"];
    notification.message = [notificationDict objectForKey:@"message"];
    notification.messageRich = [notificationDict objectForKey:@"messageRich"];
    notification.messageRichParameters = [notificationDict objectForKey:@"messageRichParameters"];
    
    if (![notification.subjectRichParameters isKindOfClass:[NSDictionary class]]) {
        notification.subjectRichParameters = @{};
    }
    
    if (![notification.messageRichParameters isKindOfClass:[NSDictionary class]]) {
        notification.messageRichParameters = @{};
    }
    
    return notification;
}

- (NCNotificationType)notificationType
{
    NCNotificationType type = kNCNotificationTypeRoom;
    if ([_objectType isEqualToString:@"chat"]) {
        type = kNCNotificationTypeChat;
    } else if ([_objectType isEqualToString:@"call"]) {
        type = kNCNotificationTypeCall;
    }
    return type;
}

- (NSString *)roomToken
{
    // Starting with NC 24 objectId additionally contains the messageId: "{roomToken}/{messageId}"
    if ([_objectId containsString:@"/"]) {
        NSArray *objectIdComponents = [_objectId componentsSeparatedByString:@"/"];
        return objectIdComponents[0];
    }

    return _objectId;
}

- (NSString *)chatMessageAuthor
{
    NSString *author = [[_subjectRichParameters objectForKey:@"user"] objectForKey:@"name"];
    NSString *guest = [[_subjectRichParameters objectForKey:@"guest"] objectForKey:@"name"];
    if (guest) {
        author = [NSString stringWithFormat:@"%@ (%@)", guest, NSLocalizedString(@"guest", nil)];
    }
    return author ? author : NSLocalizedString(@"Guest", nil);
}

- (NSString *)chatMessageTitle
{
    NSString *title = [self chatMessageAuthor];
    // Check if the room has a name
    NSArray *parameters = [self getParametersFromRichText:_subjectRich];
    for (int i = 0; i < parameters.count; i++) {
        NSTextCheckingResult *match = [parameters objectAtIndex:i];
        NSString* parameter = [_subjectRich substringWithRange:match.range];
        NSString *parameterKey = [[parameter stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"}" withString:@""];
        if ([parameterKey isEqualToString:@"reaction"]) {
            return _subject;
        }
        if ([parameterKey isEqualToString:@"call"]) {
            NSString *inString = NSLocalizedString(@"in", nil);
            title = [title stringByAppendingString:[NSString stringWithFormat:@" %@ %@", inString, [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"name"]]];
        }
    }
    return title;
}

- (NSString *)callDisplayName
{
    NSString *displayName = [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"name"];
    NSString *callType = [[_subjectRichParameters objectForKey:@"call"] objectForKey:@"call-type"];
    if ([callType isEqualToString:@"one2one"]) {
        displayName = [[_subjectRichParameters objectForKey:@"user"] objectForKey:@"name"];
    }
    if (!displayName || [displayName isEqualToString:@"a conversation"]) {
        displayName = NSLocalizedString(@"Incoming call", nil);
    }
    return displayName;
}

- (NSArray *)getParametersFromRichText:(NSString *)text
{
    NSError *error = nil;
    NSRegularExpression *parameterRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{([^}]+)\\}" options:NSRegularExpressionCaseInsensitive error:&error];
    return [parameterRegex matchesInString:text options:0 range:NSMakeRange(0, [text length])];
}

@end
