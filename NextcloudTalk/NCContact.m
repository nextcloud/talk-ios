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

#import "NCContact.h"

#import "ABContact.h"
#import "NCDatabaseManager.h"

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
        return unmanagedABContact.name;
    }
    
    return nil;
}

@end
