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
