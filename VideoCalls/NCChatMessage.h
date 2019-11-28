//
//  NCChatMessage.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "NCMessageParameter.h"

extern NSInteger const kChatMessageMaxGroupNumber;
extern NSInteger const kChatMessageGroupTimeDifference;

@interface NCChatMessage : NSObject

@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSDictionary *messageParameters;
@property (nonatomic, assign) NSInteger timestamp;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *systemMessage;
@property (nonatomic, assign) BOOL isReplyable;
@property (nonatomic, strong) NCChatMessage *parent;
// Group messages
@property (nonatomic, assign) BOOL groupMessage;
@property (nonatomic, assign) NSInteger groupMessageNumber;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
- (BOOL)isSystemMessage;
- (NCMessageParameter *)file;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)systemMessageFormat;

@end
