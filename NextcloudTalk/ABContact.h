/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

@interface ABContact : RLMObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RLMArray<RLMString> *phoneNumbers;
@property (nonatomic, assign) NSInteger lastUpdate;

+ (instancetype)contactWithIdentifier:(NSString *)identifier name:(NSString *)name phoneNumbers:(NSArray *)phoneNumbers lastUpdate:(NSInteger)lastUpdate;
+ (void)updateContact:(ABContact *)managedContact withContact:(ABContact *)contact;

@end

