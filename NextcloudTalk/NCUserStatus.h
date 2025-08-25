/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const kUserStatusOnline;
extern NSString * const kUserStatusAway;
extern NSString * const kUserStatusBusy;
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
+ (UIImage *)getOnlineSFIcon;
+ (UIImage *)getAwaySFIcon;
+ (UIImage *)getBusySFIcon;
+ (UIImage *)getDoNotDisturbSFIcon;
+ (UIImage *)getInvisibleSFIcon;
- (NSString *)readableUserStatus;
- (NSString *)readableUserStatusMessage;
- (NSString *)readableUserStatusOrMessage;
- (nullable UIImage *)getSFUserStatusIcon;
- (BOOL)hasVisibleStatusIcon;

@end

NS_ASSUME_NONNULL_END
