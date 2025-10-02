/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCContact.h"

#import "ABContact.h"
#import "NCUser.h"

@implementation NCContact

+ (instancetype)contactWithIdentifier:(NSString *)identifier cloudId:(NSString *)cloudId lastUpdate:(NSInteger)lastUpdate andAccountId:(NSString *)accountId
{
    NCContact *contact = [[NCContact alloc] init];
    contact.identifier = identifier;
    contact.cloudId = cloudId;
    contact.lastUpdate = lastUpdate;
    contact.accountId = accountId;
    contact.internalId = [NSString stringWithFormat:@"%@@%@", contact.accountId, contact.identifier];
    return contact;
}

+ (void)updateContact:(NCContact *)managedContact withContact:(NCContact *)contact
{
    managedContact.cloudId = contact.cloudId;
    managedContact.lastUpdate = contact.lastUpdate;
}

- (NSString *)userId
{
    if (self.cloudId) {
        NSArray *components = [self.cloudId componentsSeparatedByString:@"@"];
        if (components.count > 1) {
            NSString *userId = components[0];
            // If there are more than 2 components grab everything as userId until last separator.
            if (components.count > 2) {
                for (NSInteger i = 1; i <= components.count - 2; i++) {
                    userId = [userId stringByAppendingString:[NSString stringWithFormat:@"@%@", components[i]]];
                }

            }
            return userId;
        }
    }
    
    return nil;
}

- (NSString *)name
{
    if (self.identifier) {
        ABContact *unmanagedABContact = nil;
        ABContact *managedABContact = [ABContact objectsWhere:@"identifier = %@", self.identifier].firstObject;
        if (managedABContact) {
            unmanagedABContact = [[ABContact alloc] initWithValue:managedABContact];
        }
        
        NSString *contactDisplayName = unmanagedABContact.name;
        if (!contactDisplayName || [contactDisplayName isEqualToString:@""]) {
            // If the address book contact was stored without name return
            // the first phone number (it should have at least one phone number) as display name.
            contactDisplayName = unmanagedABContact.phoneNumbers.firstObject;
        }
        return contactDisplayName;
    }
    
    return nil;
}

+ (NSArray<NCUser *> *)contactsForAccountId:(NSString *)accountId contains:(NSString *)searchString
{
    RLMResults *managedContacts = [NCContact objectsWhere:@"accountId = %@", accountId];
    NSMutableArray *filteredContacts = nil;
    // Create an unmanaged copy of the stored contacts
    NSMutableArray *contacts = [NSMutableArray new];
    for (NCContact *managedContact in managedContacts) {
        NCContact *contact = [[NCContact alloc] initWithValue:managedContact];
        NCUser *user = [NCUser userFromNCContact:contact];
        [contacts addObject:user];
    }
    
    filteredContacts = contacts;
    
    if (searchString && ![searchString isEqualToString:@""]) {
        NSString *filter = @"%K CONTAINS[cd] %@ || %K CONTAINS[cd] %@";
        NSArray* args = @[@"name", searchString, @"userId", searchString];
        NSPredicate* predicate = [NSPredicate predicateWithFormat:filter argumentArray:args];
        filteredContacts = [[NSMutableArray alloc] initWithArray:[contacts filteredArrayUsingPredicate:predicate]];
    }
    
    return filteredContacts;
}

@end
