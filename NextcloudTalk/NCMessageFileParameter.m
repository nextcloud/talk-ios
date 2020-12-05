//
//  NCMessageFileParameter.m
//  NextcloudTalk
//
//  Created by Marcel Müller on 05.12.20.
//

#import "NCMessageFileParameter.h"

@implementation NCMessageFileParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super initWithDictionary:parameterDict];
    if (self) {      
        self.path = [parameterDict objectForKey:@"path"];
        self.mimetype = [parameterDict objectForKey:@"mimetype"];
        self.previewAvailable = [[parameterDict objectForKey:@"preview-available"] boolValue];
    }
    
    return self;
}

@end
