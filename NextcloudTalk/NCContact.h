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

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>


@interface NCContact : RLMObject

@property (nonatomic, copy) NSString *internalId; // accountId@identifier
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *cloudId;
@property (nonatomic, assign) NSInteger lastUpdate;

+ (instancetype)contactWithIdentifier:(NSString *)identifier cloudId:(NSString *)cloudId lastUpdate:(NSInteger)lastUpdate andAccountId:(NSString *)accountId;
+ (void)updateContact:(NCContact *)managedContact withContact:(NCContact *)contact;
+ (NSMutableArray *)contactsForAccountId:(NSString *)accountId contains:(NSString *)searchString;
- (NSString *)userId;
- (NSString *)name;

@end

