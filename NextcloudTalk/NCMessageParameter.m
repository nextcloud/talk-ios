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

#import "NCMessageParameter.h"

#import "NCDatabaseManager.h"

@implementation NCMessageParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super init];
    if (self) {
        if (!parameterDict || ![parameterDict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        
        self.parameterId = [parameterDict objectForKey:@"id"];
        self.name = [parameterDict objectForKey:@"name"];
        self.link = [parameterDict objectForKey:@"link"];
        self.type = [parameterDict objectForKey:@"type"];
        
        id parameterId = [parameterDict objectForKey:@"id"];
        if ([parameterId isKindOfClass:[NSString class]]) {
            self.parameterId = parameterId;
        } else {
            self.parameterId = [parameterId stringValue];
        }
        
        self.contactName = [parameterDict objectForKey:@"contact-name"];
        self.contactPhoto = [parameterDict objectForKey:@"contact-photo"];
        self.mentionId = [parameterDict objectForKey:@"mentionId"];
        self.mentionDisplayName = [parameterDict objectForKey:@"mentionDisplayName"];
    }
    
    return self;
}

- (BOOL)shouldBeHighlighted
{
    // Own mentions
    // Call mentions
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    return ([_type isEqualToString:@"user"] && [activeAccount.userId isEqualToString:_parameterId]) || [_type isEqualToString:@"call"];
}

- (UIImage *)contactPhotoImage
{
    if (self.contactPhoto) {
        NSString *base64String = [NSString stringWithFormat:@"%@%@", @"data:image/png;base64,", self.contactPhoto];
        NSURL *url = [NSURL URLWithString:base64String];
        NSData *imageData = [NSData dataWithContentsOfURL:url];
        return [UIImage imageWithData:imageData];
    }
    
    return nil;
}

+ (NSDictionary *)dictionaryFromMessageParameter:(NCMessageParameter *)messageParameter
{
    if (!messageParameter || ![messageParameter isKindOfClass:[NCMessageParameter class]]) {
        return nil;
    }

    NSMutableDictionary *messageParameterDict = [NSMutableDictionary new];
    if (messageParameter.parameterId) {
        [messageParameterDict setObject:messageParameter.parameterId forKey:@"id"];
    }
    if (messageParameter.name) {
        [messageParameterDict setObject:messageParameter.name forKey:@"name"];
    }
    if (messageParameter.link) {
        [messageParameterDict setObject:messageParameter.link forKey:@"link"];
    }
    if (messageParameter.type) {
        [messageParameterDict setObject:messageParameter.type forKey:@"type"];
    }
    if (messageParameter.contactName) {
        [messageParameterDict setObject:messageParameter.contactName forKey:@"contact-name"];
    }
    if (messageParameter.contactPhoto) {
        [messageParameterDict setObject:messageParameter.contactPhoto forKey:@"contact-photo"];
    }
    if (messageParameter.mentionId) {
        [messageParameterDict setObject:messageParameter.mentionId forKey:@"mentionId"];
    }
    if (messageParameter.mentionDisplayName) {
        [messageParameterDict setObject:messageParameter.mentionDisplayName forKey:@"mentionDisplayName"];
    }

    return [[NSDictionary alloc] initWithDictionary:messageParameterDict];
}


+ (NSDictionary *)messageParametersDictionaryFromDictionary:(NSDictionary *)parametersDict
{
    if (!parametersDict || ![parametersDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSMutableDictionary *messageParametersDict = [NSMutableDictionary new];
    for (NSString *parameterKey in parametersDict) {
        NCMessageParameter *parameter = [parametersDict objectForKey:parameterKey];
        NSDictionary *parameterDict = [NCMessageParameter dictionaryFromMessageParameter:parameter];
        if (parameterDict) {
            [messageParametersDict setObject:parameterDict forKey:parameterKey];
        }
    }

    return [[NSDictionary alloc] initWithDictionary:messageParametersDict];
}

+ (NSString *)messageParametersJSONStringFromDictionary:(NSDictionary *)parametersDict
{
    if (!parametersDict || ![parametersDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *messageParametersJSONString = nil;
    NSDictionary *messageParameters = [self messageParametersDictionaryFromDictionary:parametersDict];
    if ([messageParameters isKindOfClass:[NSDictionary class]]) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messageParameters
                                                           options:0
                                                             error:&error];
        if (jsonData) {
            messageParametersJSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        } else {
            NSLog(@"Error generating message parameters JSON string: %@", error);
        }
    }

    return messageParametersJSONString;
}

+ (NSDictionary *)messageParametersDictFromJSONString:(NSString *)parametersJSONString
{
    NSDictionary *parametersDict = @{};
    NSData *data = [parametersJSONString dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        NSError* error;
        NSDictionary* jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&error];
        if (jsonData) {
            parametersDict = jsonData;
        } else {
            NSLog(@"Error retrieving message parameters JSON data: %@", error);
        }
    }
    NSMutableDictionary *messageParametersDict = [NSMutableDictionary new];
    for (NSString *parameterKey in parametersDict) {
        NCMessageParameter *parameter = [[NCMessageParameter alloc] initWithDictionary:[parametersDict objectForKey:parameterKey]];
        if (parameter) {
            [messageParametersDict setObject:parameter forKey:parameterKey];
        }
    }

    return messageParametersDict;
}

@end
