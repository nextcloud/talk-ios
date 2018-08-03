//
//  NCChatMessage.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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
// Group messages
@property (nonatomic, assign) BOOL groupMessage;
@property (nonatomic, assign) NSInteger groupMessageNumber;

+ (instancetype)messageWithDictionary:(NSDictionary *)messageDict;
- (NSMutableAttributedString *)parsedMessage;
- (NSMutableAttributedString *)lastRoomMessageFormat;

@end
