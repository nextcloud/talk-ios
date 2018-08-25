//
//  NCMessageParameter.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCMessageParameter.h"

#import "NCSettingsController.h"

@implementation NCMessageParameter

+ (instancetype)parameterWithDictionary:(NSDictionary *)parameterDict
{
    if (!parameterDict || ![parameterDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NCMessageParameter *messageParameter = [[NCMessageParameter alloc] init];
    messageParameter.parameterId = [parameterDict objectForKey:@"id"];
    messageParameter.name = [parameterDict objectForKey:@"name"];
    messageParameter.type = [parameterDict objectForKey:@"type"];
    messageParameter.path = [parameterDict objectForKey:@"path"];
    messageParameter.link = [parameterDict objectForKey:@"link"];
    
    return messageParameter;
}

- (BOOL)isOwnMention
{
    return [_type isEqualToString:@"user"] && [[NCSettingsController sharedInstance].ncUserId isEqualToString:_parameterId];
}

@end
