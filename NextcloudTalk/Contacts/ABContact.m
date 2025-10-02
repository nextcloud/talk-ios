/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ABContact.h"

@implementation ABContact

+ (instancetype)contactWithIdentifier:(NSString *)identifier name:(NSString *)name phoneNumbers:(NSArray *)phoneNumbers lastUpdate:(NSInteger)lastUpdate
{
    ABContact *contact = [[ABContact alloc] init];
    contact.identifier = identifier;
    contact.name = name;
    contact.phoneNumbers = (RLMArray<RLMString> *)phoneNumbers;
    contact.lastUpdate = lastUpdate;
    return contact;
}

+ (void)updateContact:(ABContact *)managedContact withContact:(ABContact *)contact
{
    managedContact.name = contact.name;
    managedContact.phoneNumbers = contact.phoneNumbers;
    managedContact.lastUpdate = contact.lastUpdate;
}

@end
