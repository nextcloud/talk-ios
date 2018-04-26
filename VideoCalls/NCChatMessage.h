//
//  NCChatMessage.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NCChatMessage : NSObject

@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, assign) NSInteger timestamp;
@property (nonatomic, strong) NSString *token;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;

@end
