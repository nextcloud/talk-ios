//
//  NCUser.h
//  VideoCalls
//
//  Created by Ivan Sein on 13.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum NCShareType {
    NCShareTypeUser = 0,
    NCShareTypeGroup = 1,
    NCShareTypeEmail = 4,
    NCShareTypeCircle = 7
} NCShareType;

extern NSString * const kParticipantTypeUser;
extern NSString * const kParticipantTypeGroup;
extern NSString * const kParticipantTypeEmail;
extern NSString * const kParticipantTypeCircle;

@interface NCUser : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSString *source;

+ (instancetype)userWithDictionary:(NSDictionary *)userDict;

@end
