/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCContactsManager.h"

#import <Contacts/Contacts.h>

#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "ABContact.h"
#import "NCContact.h"

#import "NextcloudTalk-Swift.h"

@interface NCContactsManager ()

@property (nonatomic, strong) CNContactStore *contactStore;

@end

@implementation NCContactsManager

NSString * const NCContactsManagerContactsUpdatedNotification       = @"NCContactsManagerContactsUpdatedNotification";
NSString * const NCContactsManagerContactsAccessUpdatedNotification = @"NCContactsManagerContactsAccessUpdatedNotification";

+ (NCContactsManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCContactsManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        _contactStore = [[CNContactStore alloc] init];
    }
    return self;
}

- (void)requestContactsAccess:(void (^)(BOOL granted))completionHandler
{
    [_contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
        completionHandler(granted);
        [[NSNotificationCenter defaultCenter] postNotificationName:NCContactsManagerContactsAccessUpdatedNotification
                                                            object:self
                                                          userInfo:nil];
    }];
}

- (BOOL)isContactAccessDetermined
{
    return [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] != CNAuthorizationStatusNotDetermined;
}

- (BOOL)isContactAccessAuthorized
{
    return [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusAuthorized;
}

- (BOOL)isTimeToSyncContacts
{
    // Update address book contacts and search for matches in the server only once per day.
    NSDate *lastUpdate = [NSDate dateWithTimeIntervalSince1970:[[NCDatabaseManager sharedInstance] activeAccount].lastContactSync];
    return ![[NSCalendar currentCalendar] isDate:lastUpdate inSameDayAsDate:[NSDate date]];
}

- (void)searchInServerForAddressBookContacts:(BOOL)forceSync
{
    if (![[NCSettingsController sharedInstance] isContactSyncEnabled]) {
        return;
    }
    
    if ([self isContactAccessAuthorized] && ([self isTimeToSyncContacts] || forceSync)) {
        NSMutableDictionary *phoneNumbersDict = [NSMutableDictionary new];
        NSMutableArray *contacts = [NSMutableArray new];
        NSInteger updateTimestamp = [[NSDate date] timeIntervalSince1970];
        NSError *error = nil;
        NSArray *keysToFetch = @[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey];
        CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keysToFetch];
        [_contactStore enumerateContactsWithFetchRequest:request error:&error usingBlock:^(CNContact * __nonnull contact, BOOL * __nonnull stop) {
            NSMutableArray *phoneNumbers = [NSMutableArray new];
            for (CNLabeledValue *phoneNumberValue in contact.phoneNumbers) {
                [phoneNumbers addObject:[[phoneNumberValue valueForKey:@"value"] valueForKey:@"digits"]];
            }
            if (phoneNumbers.count > 0) {
                NSString *identifier = [contact valueForKey:@"identifier"];
                NSString *givenName = [contact valueForKey:@"givenName"];
                NSString *familyName = [contact valueForKey:@"familyName"];
                NSString *name = [[NSString stringWithFormat:@"%@ %@", givenName, familyName] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                ABContact *abContact = [ABContact contactWithIdentifier:identifier name:name phoneNumbers:phoneNumbers lastUpdate:updateTimestamp];
                if (abContact) {
                    [contacts addObject:abContact];
                }
                [phoneNumbersDict setValue:phoneNumbers forKey:identifier];
            }
        }];
        [self updateAddressBookCopyWithContacts:contacts andTimestamp:updateTimestamp];
        [self searchForPhoneNumbers:phoneNumbersDict forAccount:[[NCDatabaseManager sharedInstance] activeAccount]];
    } else if (![self isContactAccessDetermined]) {
        [self requestContactsAccess:^(BOOL granted) {
            if (granted) {
                [self searchInServerForAddressBookContacts:YES];
            }
        }];
    }
}

- (void)updateAddressBookCopyWithContacts:(NSArray *)contacts andTimestamp:(NSInteger)timestamp
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        // Add or update contacts
        for (ABContact *contact in contacts) {
            ABContact *managedABContact = [ABContact objectsWhere:@"identifier = %@", contact.identifier].firstObject;
            if (managedABContact) {
                [ABContact updateContact:managedABContact withContact:contact];
            } else {
                [realm addObject:contact];
            }
        }
        // Delete old contacts
        NSPredicate *query = [NSPredicate predicateWithFormat:@"lastUpdate != %ld", (long)timestamp];
        RLMResults *managedABContactsToBeDeleted = [ABContact objectsWithPredicate:query];
        // Delete matching nc contacts
        for (ABContact *managedABContact in managedABContactsToBeDeleted) {
            NSPredicate *query2 = [NSPredicate predicateWithFormat:@"identifier = %@", managedABContact.identifier];
            [realm deleteObjects:[NCContact objectsWithPredicate:query2]];
        }
        [realm deleteObjects:managedABContactsToBeDeleted];
        NSLog(@"Address Book Contacts updated");
    }];
}

- (void)searchForPhoneNumbers:(NSDictionary *)phoneNumbers forAccount:(TalkAccount *)account
{
    [[NCAPIController sharedInstance] searchContactsForAccount:account withPhoneNumbers:phoneNumbers andCompletionBlock:^(NSDictionary *contacts, NSError *error) {
        if (!error) {
            BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"NCUpdateContacts" expirationHandler:nil];
            RLMRealm *realm = [RLMRealm defaultRealm];
            [realm transactionWithBlock:^{
                NSInteger updateTimestamp = [[NSDate date] timeIntervalSince1970];
                // Add or update matched contacts
                if (contacts.count > 0) {
                    for (NSString *identifier in contacts.allKeys) {
                        NSString *cloudId = [contacts objectForKey:identifier];
                        NCContact *contact = [NCContact contactWithIdentifier:identifier cloudId:cloudId lastUpdate:updateTimestamp andAccountId:account.accountId];
                        // Filter out app user (it could have its own phone number in address book)
                        if ([contact.userId isEqualToString:account.userId]) {
                            continue;
                        }
                        NCContact *managedNCContact = [NCContact objectsWhere:@"identifier = %@ AND accountId = %@", identifier, account.accountId].firstObject;
                        if (managedNCContact) {
                            [NCContact updateContact:managedNCContact withContact:contact];
                        } else {
                            [realm addObject:contact];
                        }
                    }
                }
                // Delete old contacts
                NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@ AND lastUpdate != %ld", account.accountId, (long)updateTimestamp];
                RLMResults *managedNCContactsToBeDeleted = [NCContact objectsWithPredicate:query];
                [realm deleteObjects:managedNCContactsToBeDeleted];
                // Update last sync for account
                NSPredicate *accountQuery = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
                TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:accountQuery].firstObject;
                managedAccount.lastContactSync = updateTimestamp;
                NSLog(@"Matched NC Contacts updated");
                [[NSNotificationCenter defaultCenter] postNotificationName:NCContactsManagerContactsUpdatedNotification
                                                                    object:self
                                                                  userInfo:nil];
                [bgTask stopBackgroundTask];
            }];
        }
    }];
}

- (void)removeStoredContacts
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    TalkAccount *account = [TalkAccount objectsWhere:(@"active = true")].firstObject;
    // Remove stored contacts for active account
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", account.accountId];
    RLMResults *managedNCContactsToBeDeleted = [NCContact objectsWithPredicate:query];
    [realm deleteObjects:managedNCContactsToBeDeleted];
    account.lastContactSync = 0;
    // If there are no other account with contact sync enabled -> delete address book copy
    TalkAccount *accountWithContactSyncEnabled = [TalkAccount objectsWhere:(@"hasContactSyncEnabled = true AND active = false")].firstObject;
    if (!accountWithContactSyncEnabled) {
        [realm deleteObjects:[ABContact allObjects]];
    }
    [realm commitWriteTransaction];
}

@end
