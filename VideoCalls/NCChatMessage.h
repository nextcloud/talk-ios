//
//  NCChatMessage.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Realm/Realm.h>
#import "NCMessageParameter.h"

extern NSInteger const kChatMessageMaxGroupNumber;
extern NSInteger const kChatMessageGroupTimeDifference;

@interface NCChatMessage : RLMObject

@property (nonatomic, strong) NSString *internalId; // accountId@token@messageId
@property (nonatomic, strong) NSString *accountId;
@property (nonatomic, strong) NSString *actorDisplayName;
@property (nonatomic, strong) NSString *actorId;
@property (nonatomic, strong) NSString *actorType;
@property (nonatomic, assign) NSInteger messageId;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *messageParametersJSONString;
@property (nonatomic, assign) NSInteger timestamp;
@property (nonatomic, strong) NSString *token;
@property (nonatomic, strong) NSString *systemMessage;
@property (nonatomic, assign) BOOL isReplyable;
@property (nonatomic, strong) NCChatMessage *parent;
// Group messages
@property (nonatomic, assign) BOOL groupMessage;
@property (nonatomic, assign) NSInteger groupMessageNumber;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict andAccountId:(NSString *)accountId;
+ (void)updateChatMessage:(NCChatMessage *)managedChatMessage withChatMessage:(NCChatMessage *)chatMessage;

- (BOOL)isSystemMessage;
- (NCMessageParameter *)file;
- (NSDictionary *)messageParameters;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)systemMessageFormat;

@end
