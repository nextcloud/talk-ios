//
//  NCUserStatus.h
//  VideoCalls
//
//  Created by Ivan Sein on 16.09.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kUserStatusOnline;
extern NSString * const kUserStatusAway;
extern NSString * const kUserStatusDND;
extern NSString * const kUserStatusInvisible;
extern NSString * const kUserStatusOffline;

@interface NCUserStatus : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) BOOL statusIsUserDefined;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, assign) BOOL messageIsPredefined;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, assign) NSInteger clearAt;

+ (instancetype)userStatusWithDictionary:(NSDictionary *)userStatusDict;
+ (NSString *)readableUserStatusFromUserStatus:(NSString *)userStatus;
+ (NSString *)userStatusImageNameForStatus:(NSString *)userStatus ofSize:(NSInteger)size;
- (NSString *)readableUserStatus;
- (NSString *)userStatusImageNameOfSize:(NSInteger)size;

@end

NS_ASSUME_NONNULL_END
