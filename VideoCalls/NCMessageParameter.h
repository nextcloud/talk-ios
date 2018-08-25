//
//  NCMessageParameter.h
//  VideoCalls
//
//  Created by Ivan Sein on 24.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NCMessageParameter : NSObject

@property (nonatomic, strong) NSString *parameterId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSString *link;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, assign) NSRange range;

+ (instancetype)parameterWithDictionary:(NSDictionary *)parameterDict;
- (BOOL)isOwnMention;

@end
