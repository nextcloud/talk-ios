/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

@class NCUser;

@interface NCContact : RLMObject

@property (nonatomic, copy) NSString *internalId; // accountId@identifier
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *cloudId;
@property (nonatomic, assign) NSInteger lastUpdate;

+ (instancetype)contactWithIdentifier:(NSString *)identifier cloudId:(NSString *)cloudId lastUpdate:(NSInteger)lastUpdate andAccountId:(NSString *)accountId;
+ (void)updateContact:(NCContact *)managedContact withContact:(NCContact *)contact;
+ (NSArray<NCUser *> *)contactsForAccountId:(NSString *)accountId contains:(NSString * _Nullable)searchString;
- (NSString *)userId;
- (NSString *)name;

@end

