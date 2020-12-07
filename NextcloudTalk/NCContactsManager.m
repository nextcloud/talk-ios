/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "NCContactsManager.h"

#import <Contacts/Contacts.h>

#import "NCAPIController.h"
#import "NCDatabaseManager.h"

@interface NCContactsManager ()

@property (nonatomic, strong) CNContactStore *contactStore;

@end

@implementation NCContactsManager

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

- (void)requestContactsAccess
{
    [_contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (granted) {
            [self searchInServerForAddressBookContacts];
        }
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

- (void)searchInServerForAddressBookContacts
{
    if ([self isContactAccessAuthorized]) {
        NSMutableDictionary *phoneNumbersDict = [NSMutableDictionary new];
        NSError *error = nil;
        NSArray *keysToFetch = @[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey];
        CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keysToFetch];
        [_contactStore enumerateContactsWithFetchRequest:request error:&error usingBlock:^(CNContact * __nonnull contact, BOOL * __nonnull stop) {
            // Get all phone numbers from contact
            NSMutableArray *contactPhoneNumbers = [NSMutableArray new];
            for (CNLabeledValue *phoneNumberValue in contact.phoneNumbers) {
                [contactPhoneNumbers addObject:[[phoneNumberValue valueForKey:@"value"] valueForKey:@"digits"]];
            }
            if (contactPhoneNumbers.count > 0) {
                NSString *contactIdentifier = [contact valueForKey:@"identifier"];
                [phoneNumbersDict setValue:contactPhoneNumbers forKey:contactIdentifier];
            }
        }];
        if (phoneNumbersDict.count > 0) {
            [self searchForPhoneNumbers:phoneNumbersDict];
        }
    } else if (![self isContactAccessDetermined]) {
        [self requestContactsAccess];
    }
}

- (void)searchForPhoneNumbers:(NSDictionary *)phoneNumbers
{
    [[NCAPIController sharedInstance] searchContactsForAccount:[[NCDatabaseManager sharedInstance] activeAccount] withPhoneNumbers:phoneNumbers andCompletionBlock:^(NSArray *contactList, NSError *error) {
        NSLog(@"Search for contacts returned:%@ and error:%@", contactList, error);
    }];
}

@end
