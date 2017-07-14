//
//  NCUser.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NCUser : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;

+ (instancetype)userWithDictionary:(NSDictionary *)userDict;

@end
